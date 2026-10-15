import SwiftUI

struct WelcomeView: View {
    let open: () -> Void
    let liveStreaming: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    Text("Read, review, listen.").font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text("Open Markdown to read it, follow saved changes or listen with Read Aloud.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 380)
                    VStack(spacing: 10) {
                        Button("Open Markdown…", action: open).buttonStyle(.borderedProminent).keyboardShortcut("o")
                        Button("Live Streaming Preview", action: liveStreaming).buttonStyle(.bordered)
                    }.controlSize(.large)
                    Text("Read-only by default. Save checklist progress when you choose.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(32).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
            }
        }
    }
}
