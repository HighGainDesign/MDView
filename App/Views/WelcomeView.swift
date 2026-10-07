import SwiftUI

struct WelcomeView: View {
    let open: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.richtext").font(.system(size: 52, weight: .light)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Markdown, ready to read.").font(.title2.weight(.semibold))
            Text("Open a file to view it. Changes appear automatically.\nYou can also preview a draft or use Finder’s Quick Look.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open Markdown…", action: open).buttonStyle(.borderedProminent).keyboardShortcut("o")
            Text("Read-only • Tables • Links • Code blocks").font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
