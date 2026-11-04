#if os(macOS)
import AppKit
import Testing
@testable import MacAppKitExtras

@MainActor
struct ScrollSyncTests {
    /// `register` positions a scroll view on the next main-queue turn; suspending lets it run.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test func scrollingOnePaneScrollsTheOthersAndLaterPanesStartThere() async throws {
        let sync = ScrollSync()
        var observers: [NSObjectProtocol] = []
        defer { observers.forEach(NotificationCenter.default.removeObserver) }
        func pane() -> NSScrollView {
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 5000))
            scrollView.contentView.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: nil) { _ in
                MainActor.assumeIsolated { sync.scrollViewDidScroll(scrollView) }
            })
            sync.register(scrollView)
            return scrollView
        }

        let editor = pane(), preview = pane()
        try await settle()
        editor.contentView.scroll(to: NSPoint(x: 0, y: 420))
        editor.reflectScrolledClipView(editor.contentView)
        #expect(preview.contentView.bounds.origin.y == 420)
        #expect(sync.originY == 420)

        let later = pane()
        try await settle()
        #expect(later.contentView.bounds.origin.y == 420)
    }
}

@MainActor
struct NestedScrollRouterTests {
    /// An outer vertical scroll view whose content holds one nested horizontal scroll view.
    private func makeWindow() -> (NSWindow, outer: NSScrollView, overNested: NSPoint, overContent: NSPoint) {
        let frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        let outer = NSScrollView(frame: frame)
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 2000))
        let nested = NSScrollView(frame: NSRect(x: 0, y: 100, width: 400, height: 100))
        nested.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 100))
        document.addSubview(nested)
        outer.documentView = document
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = outer
        window.layoutIfNeeded()
        let overNested = nested.convert(NSPoint(x: nested.bounds.midX, y: nested.bounds.midY), to: nil)
        let overContent = document.convert(NSPoint(x: 200, y: 20), to: nil)
        return (window, outer, overNested, overContent)
    }

    @Test func routesVerticalGesturesThatStartOverANestedView() {
        let (window, outer, overNested, overContent) = makeWindow()
        defer { window.close() }
        let router = NestedScrollRouter(scrollView: outer)
        let vertical = (dx: CGFloat(0), dy: CGFloat(-6)), horizontal = (dx: CGFloat(-6), dy: CGFloat(1))
        func forward(_ phase: NSEvent.Phase, _ momentum: NSEvent.Phase = [], _ delta: (dx: CGFloat, dy: CGFloat), _ point: NSPoint) -> Bool {
            router.shouldForward(phase: phase, momentumPhase: momentum, deltaX: delta.dx, deltaY: delta.dy, pointInWindow: point)
        }

        // A vertical gesture that begins over the nested view goes to the outer view, momentum included
        #expect(forward(.began, [], vertical, overNested))
        #expect(forward(.changed, [], horizontal, overContent))
        #expect(forward([], .changed, vertical, overContent))
        #expect(forward([], .ended, vertical, overContent))
        #expect(!forward([], .changed, vertical, overContent))

        // A horizontal gesture stays with the nested view
        #expect(!forward(.began, [], horizontal, overNested))
        #expect(!forward(.changed, [], vertical, overNested))

        // Mouse wheels are decided per event
        #expect(forward([], [], vertical, overNested))
        #expect(!forward([], [], horizontal, overNested))
        #expect(!forward([], [], vertical, overContent))
    }
}
#endif
