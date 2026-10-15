import AppKit
import SwiftUI

/// Keep both the document and review controls usable in compact windows.
/// SwiftUI owns the requested size; AppKit only enforces the window boundary.
struct ReaderWindowMinimumSize: NSViewRepresentable {
    let minimumHeight: CGFloat

    func makeNSView(context: Context) -> MinimumSizeView { MinimumSizeView() }

    func updateNSView(_ view: MinimumSizeView, context: Context) {
        view.minimumHeight = minimumHeight
        view.applyMinimum()
    }

    final class MinimumSizeView: NSView {
        var minimumHeight: CGFloat = 300

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyMinimum()
        }

        func applyMinimum() {
            guard let window else { return }
            let decoration = max(0, window.frame.height - window.contentLayoutRect.height)
            let available = window.screen.map { $0.visibleFrame.height - decoration } ?? minimumHeight
            let height = min(minimumHeight, available)
            window.contentMinSize = NSSize(width: 480, height: height)
            let growth = height - window.contentLayoutRect.height
            guard growth > 1 else { return }
            var frame = window.frame
            frame.size.height += growth
            frame.origin.y -= growth
            window.setFrame(window.constrainFrameRect(frame, to: window.screen), display: true)
        }
    }
}
