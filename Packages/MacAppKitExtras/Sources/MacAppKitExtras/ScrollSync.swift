//
//  ScrollSync.swift
//  MacAppKitExtras
//
//  Keeps several scroll views at the same vertical offset without routing it through SwiftUI state.
//

#if os(macOS)
import AppKit

/// Keeps registered scroll views (an editor and its preview, say) in step by scrolling the clip views directly.
/// Scroll positions never pass through SwiftUI state, so scrolling doesn't re-evaluate
/// the hosting view (which could re-render expensive content on every frame).
/// Hold one in `@State`; the stored origin restores the position when a scroll view is
/// registered again (for example after a view mode change).
@MainActor
public final class ScrollSync {
    public private(set) var originY: CGFloat = 0
    private let scrollViews = NSHashTable<NSScrollView>.weakObjects()
    private var isSyncing = false

    public init() {}

    /// Adds a scroll view and moves it to the shared position once it has laid out.
    public func register(_ scrollView: NSScrollView) {
        scrollViews.add(scrollView)
        DispatchQueue.main.async { [weak self, weak scrollView] in
            guard let self = self, let scrollView = scrollView else { return }
            self.isSyncing = true
            ScrollSync.scroll(scrollView, toY: self.originY)
            self.isSyncing = false
        }
    }

    /// Call from a scroll view's bounds-change observer; scrolls every other registered view.
    public func scrollViewDidScroll(_ scrollView: NSScrollView) {
        guard !isSyncing else { return }
        let y = scrollView.contentView.bounds.origin.y
        guard abs(y - originY) > 0.5 else { return }
        originY = y
        isSyncing = true
        for other in scrollViews.allObjects where other !== scrollView {
            ScrollSync.scroll(other, toY: y)
        }
        isSyncing = false
    }

    private static func scroll(_ scrollView: NSScrollView, toY y: CGFloat) {
        let clipView = scrollView.contentView
        guard abs(clipView.bounds.origin.y - y) > 0.5 else { return }
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clipView)
    }
}

#else
import UIKit

/// iOS counterpart of the AppKit `ScrollSync`: keeps the source editor and preview at the same
/// vertical offset by setting `contentOffset` directly, never through SwiftUI state.
@MainActor
public final class ScrollSync {
    public private(set) var originY: CGFloat = 0
    private let scrollViews = NSHashTable<UIScrollView>.weakObjects()
    private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var isSyncing = false

    public init() {}

    /// Adds a scroll view, moves it to the shared position once it has laid out, and follows it.
    public func register(_ scrollView: UIScrollView) {
        scrollViews.add(scrollView)
        observations[ObjectIdentifier(scrollView)] = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] view, _ in
            MainActor.assumeIsolated { self?.scrollViewDidScroll(view) }
        }
        DispatchQueue.main.async { [weak self, weak scrollView] in
            guard let self = self, let scrollView = scrollView else { return }
            self.isSyncing = true
            ScrollSync.scroll(scrollView, toY: self.originY)
            self.isSyncing = false
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isSyncing, scrollView.isTracking || scrollView.isDecelerating else { return }
        let y = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        guard abs(y - originY) > 0.5 else { return }
        originY = y
        isSyncing = true
        for other in scrollViews.allObjects where other !== scrollView {
            ScrollSync.scroll(other, toY: y)
        }
        isSyncing = false
    }

    private static func scroll(_ scrollView: UIScrollView, toY y: CGFloat) {
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        let target = min(max(0, y), maxY) - scrollView.adjustedContentInset.top
        guard abs(scrollView.contentOffset.y - target) > 0.5 else { return }
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target), animated: false)
    }
}
#endif
