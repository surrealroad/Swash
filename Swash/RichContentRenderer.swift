//
//  RichContentRenderer.swift
//  Swash
//
//  Typesets TeX math with KaTeX and draws Mermaid diagrams, fully offline, using an offscreen
//  WKWebView that loads the bundled Swash/Rendering/ page. Each formula or diagram is
//  snapshotted to an NSImage and cached by source, kind, size and appearance.
//

import AppKit
import WebKit
import os

@MainActor
final class RichContentRenderer: NSObject {
    enum Kind: String {
        case inlineMath = "inline"
        case displayMath = "display"
        case mermaid
    }

    struct Request: Hashable, Sendable {
        let kind: Kind
        let source: String
        let dark: Bool
        let fontSize: CGFloat

        init(kind: Kind, source: String, dark: Bool, fontSize: CGFloat = 13) {
            self.kind = kind
            self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
            self.dark = dark
            self.fontSize = fontSize
        }
    }

    /// Snapshots are never mutated after rendering, so they can be handed across isolation domains.
    struct Rendered: @unchecked Sendable {
        let image: NSImage
        /// Distance from the top of the image to the text baseline (inline math).
        let baseline: CGFloat
        var descent: CGFloat { max(0, image.size.height - baseline) }
    }

    enum Outcome: @unchecked Sendable {
        case rendered(Rendered)
        case failed(String)

        var rendered: Rendered? {
            if case .rendered(let r) = self { return r }
            return nil
        }
    }

    static let shared = RichContentRenderer()

    /// Posted on the main thread when a render finishes, so views showing a fallback can refresh.
    nonisolated static let didRender = Notification.Name("RichContentRendererDidRender")

    /// Folder holding swash-render.html, KaTeX and Mermaid. Tests point SWASH_RENDER_RESOURCES at
    /// Swash/Rendering; the app and extensions use their bundle (resources are copied flat).
    nonisolated static let resourceDirectory: URL? = {
        if let path = ProcessInfo.processInfo.environment["SWASH_RENDER_RESOURCES"] {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            return FileManager.default.fileExists(atPath: url.appendingPathComponent("swash-render.html").path) ? url : nil
        }
        let bundle = Bundle(for: RichContentRenderer.self)
        return bundle.url(forResource: "swash-render", withExtension: "html")?.deletingLastPathComponent()
    }()

    nonisolated static var isAvailable: Bool { resourceDirectory != nil }

    /// For styling code that runs on the main thread but is not main-actor isolated (the editor
    /// styler, preview inline text): the cached outcome, or nil after queueing the render.
    nonisolated static func cachedOutcome(_ request: Request) -> Outcome? {
        MainActor.assumeIsolated { shared.cached(request) }
    }

    /// `owner` identifies the requester's slot (say, a formula block in one editor). A newer
    /// request from the same owner replaces its older one if that hasn't started rendering, so
    /// typing inside a formula doesn't queue a render of every intermediate state.
    nonisolated static func cachedOrRequest(_ request: Request, owner: AnyHashable? = nil) -> Outcome? {
        MainActor.assumeIsolated {
            if let outcome = shared.cached(request) { return outcome }
            if isAvailable { shared.requestSpeculatively(request, owner: owner) }
            return nil
        }
    }

    /// Pixel density of the snapshots (crisp on Retina, still fine on 1x displays).
    static let scale: CGFloat = 2
    private static let log = Logger(subsystem: "com.surrealroad.Swash", category: "RichContent")
    private static let cacheLimit = 400
    private static let timeout: TimeInterval = 15

    private var cache: [Request: Outcome] = [:]
    private var cacheOrder: [Request] = []
    private var waiters: [Request: [(id: Int, callback: (Outcome) -> Void)]] = [:]
    private var nextWaiterID = 0
    /// Owners of fire-and-forget requests, and the latest request of each owner.
    private var requestOwners: [Request: Set<AnyHashable>] = [:]
    private var ownerRequests: [AnyHashable: Request] = [:]
    private var didRenderScheduled = false
    private var queue: [Request] = []
    private var current: Request?
    private var currentToken = 0
    private var webView: WKWebView?
    private var pageReady = false
    /// Consecutive timeouts; after a few the renderer gives up for the session (e.g. WebKit cannot
    /// run in this process) and everything falls back immediately.
    private var timeouts = 0
    private var gaveUp = false

    /// Number of snapshots taken (for tests).
    private(set) var renderCount = 0

    func cached(_ request: Request) -> Outcome? {
        cache[request]
    }

    /// Renders (or returns the cached result) and calls back on the main thread.
    func render(_ request: Request, completion: @escaping (Outcome) -> Void) {
        _ = addWaiter(request, completion)
    }
    
    /// Queues `request` with a waiter; returns the waiter's id, or nil when it completed at once.
    private func addWaiter(_ request: Request, _ completion: @escaping (Outcome) -> Void) -> Int? {
        if let outcome = cache[request] {
            completion(outcome)
            return nil
        }
        guard Self.isAvailable, !gaveUp else {
            completion(.failed(gaveUp ? "Renderer unavailable" : "Rendering resources are not bundled"))
            return nil
        }
        nextWaiterID += 1
        let id = nextWaiterID
        waiters[request, default: []].append((id, completion))
        enqueue(request)
        return id
    }
    
    private func enqueue(_ request: Request) {
        guard current != request, !queue.contains(request) else { return }
        queue.append(request)
        pump()
    }
    
    /// Queues a render nobody waits on (the caller re-reads the cache after `didRender`).
    private func requestSpeculatively(_ request: Request, owner: AnyHashable?) {
        guard !gaveUp else { return }
        if let owner = owner {
            if let previous = ownerRequests[owner], previous != request {
                requestOwners[previous]?.remove(owner)
                dropIfUnwanted(previous)
            }
            ownerRequests[owner] = request
            requestOwners[request, default: []].insert(owner)
        }
        enqueue(request)
    }
    
    /// Removes a queued (not yet started) request that no waiter or owner wants any more.
    private func dropIfUnwanted(_ request: Request) {
        guard current != request, waiters[request]?.isEmpty ?? true, requestOwners[request]?.isEmpty ?? true,
              let index = queue.firstIndex(of: request) else { return }
        queue.remove(at: index)
        waiters[request] = nil
        requestOwners[request] = nil
    }

    /// Awaits the render. If the awaiting task is cancelled (its view went away or now shows
    /// something else), a render that hasn't started is dropped.
    func render(_ request: Request) async -> Outcome {
        let state = WaiterState()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: cache[request] ?? .failed("Cancelled"))
                    return
                }
                state.request = request
                state.id = addWaiter(request) { continuation.resume(returning: $0) }
            }
        } onCancel: {
            Task { @MainActor in self.cancelWaiter(state) }
        }
    }
    
    private final class WaiterState: @unchecked Sendable {
        var request: Request?
        var id: Int?
    }
    
    private func cancelWaiter(_ state: WaiterState) {
        guard let request = state.request, let id = state.id, current != request,
              let index = waiters[request]?.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters[request]!.remove(at: index)
        waiter.callback(.failed("Cancelled"))
        dropIfUnwanted(request)
    }

    /// Starts loading the page ahead of the first request.
    func warmUp() {
        guard Self.isAvailable else { return }
        _ = ensureWebView()
    }

    // MARK: Pipeline

    private func ensureWebView() -> WKWebView? {
        if let webView = webView { return webView }
        guard let directory = Self.resourceDirectory else { return nil }
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.pageZoom = Self.scale
        view.navigationDelegate = self
        webView = view
        pageReady = false
        view.loadFileURL(directory.appendingPathComponent("swash-render.html"), allowingReadAccessTo: directory)
        return view
    }

    private func pump() {
        guard !gaveUp, current == nil, !queue.isEmpty, let webView = ensureWebView(), pageReady else { return }
        let request = queue.removeFirst()
        current = request
        currentToken += 1
        let token = currentToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            guard let self = self, self.current == request, self.currentToken == token else { return }
            self.timeouts += 1
            if self.timeouts >= 2 { self.gaveUp = true }
            self.finish(request, .failed("Timed out"), cache: false)
            if self.gaveUp {
                for pending in self.queue { self.finish(pending, .failed("Renderer unavailable"), cache: false) }
                self.queue.removeAll()
            }
            self.resetWebView()
        }
        webView.callAsyncJavaScript(
            "return await swashRender(kind, source, dark, fontSize)",
            arguments: ["kind": request.kind.rawValue, "source": request.source, "dark": request.dark, "fontSize": Double(request.fontSize)],
            in: nil, in: .page
        ) { [weak self] result in
            guard let self = self, self.current == request, self.currentToken == token else { return }
            switch result {
            case .failure(let error):
                self.finish(request, .failed(error.localizedDescription))
            case .success(let value):
                guard let info = value as? [String: Any], info["ok"] as? Bool == true,
                      let width = (info["width"] as? NSNumber)?.doubleValue,
                      let height = (info["height"] as? NSNumber)?.doubleValue, width > 0, height > 0 else {
                    let message = ((value as? [String: Any])?["error"] as? String) ?? "Render failed"
                    self.finish(request, .failed(message))
                    return
                }
                let baseline = (info["baseline"] as? NSNumber)?.doubleValue ?? height
                self.snapshot(request, token: token, size: CGSize(width: width, height: height), baseline: CGFloat(baseline))
            }
        }
    }

    private func snapshot(_ request: Request, token: Int, size: CGSize, baseline: CGFloat) {
        guard let webView = webView else { return }
        // The view must cover the content (in zoomed points) for the snapshot rect to be valid
        let needed = NSSize(width: max(1200, size.width * Self.scale), height: max(800, size.height * Self.scale))
        if webView.frame.width < needed.width || webView.frame.height < needed.height {
            webView.frame = NSRect(origin: .zero, size: needed)
        }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: size.width * Self.scale, height: size.height * Self.scale)
        configuration.snapshotWidth = NSNumber(value: Double(size.width))   // points: the image comes back at the backing scale
        configuration.afterScreenUpdates = true
        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            guard let self = self, self.current == request, self.currentToken == token else { return }
            guard let image = image else {
                self.finish(request, .failed(error?.localizedDescription ?? "Snapshot failed"))
                return
            }
            self.renderCount += 1
            self.timeouts = 0
            image.size = size
            self.finish(request, .rendered(Rendered(image: image, baseline: baseline)))
        }
    }

    private func finish(_ request: Request, _ outcome: Outcome, cache shouldCache: Bool = true) {
        switch outcome {
        case .rendered(let rendered):
            Self.log.debug("Rendered \(request.kind.rawValue, privacy: .public) \(Int(rendered.image.size.width))×\(Int(rendered.image.size.height))")
        case .failed(let message):
            Self.log.notice("Could not render \(request.kind.rawValue, privacy: .public): \(message, privacy: .public)")
        }
        if shouldCache {
            cache[request] = outcome
            cacheOrder.append(request)
            if cacheOrder.count > Self.cacheLimit + Self.cacheLimit / 4 {
                // Evict in batches: removeFirst on the order array is O(n)
                for evicted in cacheOrder.prefix(cacheOrder.count - Self.cacheLimit) { cache[evicted] = nil }
                cacheOrder.removeFirst(cacheOrder.count - Self.cacheLimit)
            }
        }
        current = nil
        let callbacks = waiters.removeValue(forKey: request) ?? []
        for owner in requestOwners.removeValue(forKey: request) ?? [] where ownerRequests[owner] == request {
            ownerRequests[owner] = nil
        }
        for waiter in callbacks { waiter.callback(outcome) }
        postDidRender()
        pump()
    }
    
    /// Observers restyle or re-render on `didRender`, so a burst of renders (a document with many
    /// formulas) is announced every 150 ms and once the queue empties, not once per render.
    private func postDidRender() {
        if queue.isEmpty && current == nil {
            didRenderScheduled = false
            NotificationCenter.default.post(name: Self.didRender, object: self)
            return
        }
        guard !didRenderScheduled else { return }
        didRenderScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self, self.didRenderScheduled else { return }
            self.didRenderScheduled = false
            NotificationCenter.default.post(name: Self.didRender, object: self)
        }
    }

    private func resetWebView() {
        webView?.navigationDelegate = nil
        webView = nil
        pageReady = false
        pump()
    }
}

extension RichContentRenderer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        pageReady = true
        pump()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failAll(webView, error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failAll(webView, error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        if let request = current { finish(request, .failed("Renderer stopped"), cache: false) }
        resetWebView()
    }

    /// The page itself could not load: fail everything queued rather than retrying forever.
    private func failAll(_ webView: WKWebView, _ error: Error) {
        guard webView === self.webView else { return }
        let pending = queue + (current.map { [$0] } ?? [])
        queue.removeAll()
        current = nil
        self.webView?.navigationDelegate = nil
        self.webView = nil   // the next request tries loading the page again
        for request in pending {
            finish(request, .failed(error.localizedDescription), cache: false)
        }
    }
}
