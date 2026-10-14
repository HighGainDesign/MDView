import AppKit
import SwiftUI

/// The eligibility check is evaluated both when an event arrives and when its
/// coalesced announcement is delivered. Losing focus never replays a backlog.
struct ReaderWindowContext: NSViewRepresentable {
    let reader: ReaderState
    func makeNSView(context: Context) -> Probe { Probe(reader: reader) }
    func updateNSView(_ view: Probe, context: Context) {}
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.reader?.announcements.cancel() }

    final class Probe: NSView {
        weak var reader: ReaderState?
        init(reader: ReaderState) { self.reader = reader; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reader?.announcements.isEligible = { [weak self] in
                self?.window?.isKeyWindow == true && NSApp.isActive
            }
        }
    }
}
