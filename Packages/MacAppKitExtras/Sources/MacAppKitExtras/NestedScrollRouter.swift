//
//  NestedScrollRouter.swift
//  MacAppKitExtras
//
//  Lets vertical scroll gestures pass through nested horizontal scroll views.
//

#if os(macOS)
import AppKit

/// Content such as tables and code blocks often sits in horizontal scroll views inside a vertical
/// one. AppKit sends a whole scroll gesture to the view under the pointer when it starts, so a
/// vertical swipe that begins over a nested view stalls there. This local monitor sends gestures
/// that start mostly vertical over a nested scroll view to the outer scroll view, for the whole
/// gesture including momentum, and leaves mostly horizontal gestures to the nested view.
/// Keep the router alive as long as the outer scroll view; it removes its monitor on deinit.
@MainActor
public final class NestedScrollRouter {
    private weak var scrollView: NSScrollView?
    private var monitor: Any?
    /// The decision for the trackpad gesture in progress, made at its `.began` event.
    private var forwardingGesture = false

    public init(scrollView: NSScrollView) {
        self.scrollView = scrollView
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            return self.route(event)
        }
    }

    deinit {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
    }

    public func route(_ event: NSEvent) -> NSEvent? {
        guard let scrollView = scrollView, event.window != nil, event.window === scrollView.window,
              shouldForward(phase: event.phase, momentumPhase: event.momentumPhase,
                            deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                            pointInWindow: event.locationInWindow) else { return event }
        scrollView.scrollWheel(with: event)
        return nil
    }

    /// Whether this scroll event should go to the outer scroll view instead of the view under the pointer.
    public func shouldForward(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, deltaX: CGFloat, deltaY: CGFloat, pointInWindow: NSPoint) -> Bool {
        guard let scrollView = scrollView else { return false }
        let isVertical = abs(deltaY) >= abs(deltaX)

        // Mouse wheels have no phases and aren't latched, so decide per event.
        if phase.isEmpty && momentumPhase.isEmpty {
            return isVertical && isOverNestedScrollView(pointInWindow, in: scrollView)
        }

        if phase.contains(.began) {
            forwardingGesture = isVertical && isOverNestedScrollView(pointInWindow, in: scrollView)
        }
        let forward = forwardingGesture
        if momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) {
            forwardingGesture = false
        }
        return forward
    }

    /// True when the pointer is over the outer scroll view's content and the closest scroll view
    /// there is a nested one rather than the outer one.
    private func isOverNestedScrollView(_ pointInWindow: NSPoint, in scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView, let contentView = scrollView.window?.contentView else { return false }
        let point = contentView.superview?.convert(pointInWindow, from: nil) ?? pointInWindow
        guard let hit = contentView.hitTest(point), hit.isDescendant(of: documentView) else { return false }
        var view: NSView? = hit
        while let current = view {
            if let nested = current as? NSScrollView { return nested !== scrollView }
            view = current.superview
        }
        return false
    }
}
#endif
