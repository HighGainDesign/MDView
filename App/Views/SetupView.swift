import SwiftUI

struct SetupView: View {
    @Bindable var session: SetupSession
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Make MDView part of your workflow").font(.title2.weight(.semibold))
                    Text("Two optional ways to preview your Markdown.").foregroundStyle(.secondary)
                }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    IntegrationHeading(title: "Finder Quick Look", symbol: "doc.viewfinder",
                                       subtitle: "Preview files without opening a document window.")
                    QuickLookInstructions()
                    HStack {
                        Button("Open Extension Settings…") { session.openQuickLookSettings() }
                        Spacer()
                        Text("Enable once").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    IntegrationHeading(title: "Drafts", symbol: "square.and.pencil",
                                       subtitle: "Add Preview in MDView to view a draft without changing it.")
                    HStack {
                        Button("Install Drafts Action…") { Task { await session.installDraftsAction() } }
                            .disabled(!session.draftsAvailable || session.installingDrafts)
                        Spacer()
                        Text(session.draftsAvailable ? "Drafts detected" : "Drafts isn’t installed")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let status = session.draftsStatus {
                        Text(status).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("You can return to these options in MDView Settings.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Divider()
            HStack {
                Toggle("Don’t show again", isOn: $session.dontShowAgain).toggleStyle(.checkbox)
                Spacer()
                Button("Done", action: done).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 620)
    }
}
