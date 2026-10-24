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

    struct RichPreviewSlot: Hashable, Sendable {
        let owner: ObjectIdentifier
        let location: Int

        init(owner: ObjectIdentifier, location: Int) {
            self.owner = owner
            self.location = location
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
    /// Requests being rendered: one diagram, or a batch of formulas sharing one snapshot.
    private var inFlight: [Request] = []
    /// Formulas typeset together and snapshotted once (§4.2 of the performance audit).
    private static let batchLimit = 16
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
        guard !inFlight.contains(request), !queue.contains(request) else { return }
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
        guard !inFlight.contains(request), waiters[request]?.isEmpty ?? true, requestOwners[request]?.isEmpty ?? true,
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
        guard let request = state.request, let id = state.id, !inFlight.contains(request),
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
        guard !gaveUp, inFlight.isEmpty, !queue.isEmpty, let webView = ensureWebView(), pageReady else { return }
        // Formulas go in batches (up to batchLimit, in queue order); a diagram goes alone
        let batch: [Request]
        if queue[0].kind == .mermaid {
            batch = [queue.removeFirst()]
        } else {
            var picked: [Request] = []
            var remaining: [Request] = []
            for request in queue {
                if request.kind != .mermaid && picked.count < Self.batchLimit { picked.append(request) } else { remaining.append(request) }
            }
            queue = remaining
            batch = picked
        }
        inFlight = batch
        currentToken += 1
        let token = currentToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            guard let self = self, self.currentToken == token, !self.inFlight.isEmpty else { return }
            self.timeouts += 1
            if self.timeouts >= 2 { self.gaveUp = true }
            self.finishAll(self.inFlight, .failed("Timed out"))
            if self.gaveUp {
                for pending in self.queue { self.finish(pending, .failed("Renderer unavailable"), cache: false) }
                self.queue.removeAll()
            }
            self.resetWebView()
        }
        if batch[0].kind == .mermaid {
            render(batch[0], in: webView, token: token)
        } else {
            renderBatch(batch, in: webView, token: token)
        }
    }
    
    private func render(_ request: Request, in webView: WKWebView, token: Int) {
        webView.callAsyncJavaScript(
            "return await swashRender(kind, source, dark, fontSize)",
            arguments: ["kind": request.kind.rawValue, "source": request.source, "dark": request.dark, "fontSize": Double(request.fontSize)],
            in: nil, in: .page
        ) { [weak self] result in
            guard let self = self, self.currentToken == token, self.inFlight.contains(request) else { return }
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
    
    /// Typesets the formulas together, takes one snapshot of them all and crops out each one.
    private func renderBatch(_ batch: [Request], in webView: WKWebView, token: Int) {
        let items: [[String: Any]] = batch.map { ["kind": $0.kind.rawValue, "source": $0.source, "dark": $0.dark, "fontSize": Double($0.fontSize)] }
        webView.callAsyncJavaScript("return await swashRenderBatch(items)", arguments: ["items": items], in: nil, in: .page) { [weak self] result in
            guard let self = self, self.currentToken == token, !self.inFlight.isEmpty else { return }
            guard case .success(let value) = result, let info = value as? [String: Any],
                  let results = info["items"] as? [[String: Any]], results.count == batch.count,
                  let width = (info["width"] as? NSNumber)?.doubleValue,
                  let height = (info["height"] as? NSNumber)?.doubleValue else {
                let message: String
                if case .failure(let error) = result { message = error.localizedDescription } else { message = "Render failed" }
                self.finishAll(batch, .failed(message))
                return
            }
            var frames: [(request: Request, rect: CGRect, baseline: CGFloat)] = []
            for (request, item) in zip(batch, results) {
                guard item["ok"] as? Bool == true,
                      let x = (item["x"] as? NSNumber)?.doubleValue, let y = (item["y"] as? NSNumber)?.doubleValue,
                      let w = (item["width"] as? NSNumber)?.doubleValue, let h = (item["height"] as? NSNumber)?.doubleValue, w > 0, h > 0 else {
                    self.finish(request, .failed((item["error"] as? String) ?? "Render failed"), pumpAfter: false)
                    continue
                }
                frames.append((request, CGRect(x: x, y: y, width: w, height: h), CGFloat((item["baseline"] as? NSNumber)?.doubleValue ?? h)))
            }
            guard !frames.isEmpty, width > 0, height > 0 else {
                self.pumpIfIdle()
                return
            }
            self.snapshotBatch(frames, token: token, size: CGSize(width: width, height: height))
        }
    }
    
    private func snapshotBatch(_ frames: [(request: Request, rect: CGRect, baseline: CGFloat)], token: Int, size: CGSize) {
        guard let webView = webView else { return }
        let needed = NSSize(width: max(1200, size.width * Self.scale), height: max(800, size.height * Self.scale))
        if webView.frame.width < needed.width || webView.frame.height < needed.height {
            webView.frame = NSRect(origin: .zero, size: needed)
        }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: size.width * Self.scale, height: size.height * Self.scale)
        configuration.snapshotWidth = NSNumber(value: Double(size.width))
        configuration.afterScreenUpdates = true
        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            guard let self = self, self.currentToken == token, !self.inFlight.isEmpty else { return }
            guard let image = image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                self.finishAll(frames.map(\.request), .failed(error?.localizedDescription ?? "Snapshot failed"))
                return
            }
            self.renderCount += 1
            self.timeouts = 0
            // Pixels per CSS pixel of the snapshot (it comes back at the display's backing scale)
            let scale = CGFloat(cgImage.width) / size.width
            for frame in frames {
                let pixels = CGRect(x: (frame.rect.minX * scale).rounded(.down), y: (frame.rect.minY * scale).rounded(.down),
                                    width: (frame.rect.width * scale).rounded(.up), height: (frame.rect.height * scale).rounded(.up))
                    .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
                if let cropped = cgImage.cropping(to: pixels) {
                    let piece = NSImage(cgImage: cropped, size: frame.rect.size)
                    self.finish(frame.request, .rendered(Rendered(image: piece, baseline: frame.baseline)), pumpAfter: false)
                } else {
                    self.finish(frame.request, .failed("Snapshot failed"), pumpAfter: false)
                }
            }
            self.pumpIfIdle()
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
            guard let self = self, self.currentToken == token, self.inFlight.contains(request) else { return }
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
    
    /// Fails every request in `requests` without caching (timeouts, a stopped page) and moves on.
    private func finishAll(_ requests: [Request], _ outcome: Outcome) {
        for request in requests { finish(request, outcome, cache: false, pumpAfter: false) }
        pumpIfIdle()
    }
    
    private func pumpIfIdle() {
        if inFlight.isEmpty {
            postDidRender()
            pump()
        }
    }

    private func finish(_ request: Request, _ outcome: Outcome, cache shouldCache: Bool = true, pumpAfter: Bool = true) {
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
        inFlight.removeAll { $0 == request }
        let callbacks = waiters.removeValue(forKey: request) ?? []
        for owner in requestOwners.removeValue(forKey: request) ?? [] where ownerRequests[owner] == request {
            ownerRequests[owner] = nil
        }
        for waiter in callbacks { waiter.callback(outcome) }
        if pumpAfter {
            postDidRender()
            pump()
        }
    }
    
    /// Observers restyle or re-render on `didRender`, so a burst of renders (a document with many
    /// formulas) is announced every 150 ms and once the queue empties, not once per render.
    private func postDidRender() {
        if queue.isEmpty && inFlight.isEmpty {
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
        let stopped = inFlight
        currentToken += 1
        for request in stopped { finish(request, .failed("Renderer stopped"), cache: false, pumpAfter: false) }
        resetWebView()
    }

    /// The page itself could not load: fail everything queued rather than retrying forever.
    private func failAll(_ webView: WKWebView, _ error: Error) {
        guard webView === self.webView else { return }
        let pending = queue + inFlight
        queue.removeAll()
        inFlight.removeAll()
        self.webView?.navigationDelegate = nil
        self.webView = nil   // the next request tries loading the page again
        for request in pending {
            finish(request, .failed(error.localizedDescription), cache: false)
        }
    }
}
