import SwiftUI

struct SettingsView: View {
    @AppStorage("wideLayout") private var wideLayout = true
    @AppStorage(ReaderPreferences.appearanceKey, store: ReaderPreferences.defaults) private var documentAppearance = DocumentAppearance.system
    @State private var integration = SetupSession()

    var body: some View {
        Form {
            Section {
                Picker("Document appearance", selection: $documentAppearance) {
                    ForEach(DocumentAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }.pickerStyle(.segmented)
                Toggle("Full width by default", isOn: $wideLayout)
            } header: {
                Text("Reading")
            } footer: {
                Text("Appearance updates all open documents and new Finder Quick Look previews. Width is the default for every document you open; use the Reading width button to change an individual window.")
            }
            Section("Document content") {
                PolicyRow(String(localized: "Local images"), value: String(localized: "Automatic"), help: String(localized: "Local images load automatically from relative paths, absolute paths, file URLs and symlinks wherever macOS allows access. MDView does not require image-folder grants. Image formats are handled by WebKit. Quick Look supports embedded data images only."))
                PolicyRow(String(localized: "Remote images"), value: String(localized: "Off by default"), help: String(localized: "In a document’s Reading options (…) choose Load Remote Images to allow HTTPS images for that window. Hosts can see your IP address and image requests. MDView sends no document referrer. The choice resets on closing; Quick Look never loads remote images."))
                PolicyRow(String(localized: "Embedded HTML"), value: String(localized: "Not rendered"), help: String(localized: "HTML tags written directly in Markdown, such as <div> or <iframe>, are omitted to prevent active embedded content. Standard Markdown tables, links and images work. Scripts and embedded websites cannot run."))
            }
            Section("Integrations") {
                VStack(alignment: .leading, spacing: 10) {
                    IntegrationHeading(title: String(localized: "Live streaming"), symbol: "dot.radiowaves.left.and.right",
                                       subtitle: String(localized: "Follow an editor’s Marked-compatible preview stream."))
                    Button("Open Live Preview") { (NSApp.delegate as? AppDelegate)?.showLiveStreamingPreview() }
                        .padding(.leading, 40)
                }.padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 10) {
                    IntegrationHeading(title: String(localized: "Finder Quick Look"), symbol: "doc.viewfinder",
                                       subtitle: String(localized: "Preview Markdown in Finder with the Space bar."))
                    Button("Open Extension Settings…") { integration.openQuickLookSettings() }
                        .padding(.leading, 40)
                        .help("Choose By Category → Quick Look, then enable MDView. Another enabled Markdown previewer may take priority.")
                }.padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 10) {
                    IntegrationHeading(title: String(localized: "Drafts"), symbol: "square.and.pencil",
                                       subtitle: String(localized: "Preview the current draft without changing it."))
                    HStack {
                        Button("Install Drafts Action…") { Task { await integration.installDraftsAction() } }
                            .disabled(!integration.draftsAvailable || integration.installingDrafts)
                        if !integration.draftsAvailable {
                            Text("Drafts isn’t installed").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.leading, 40)
                    if let status = integration.draftsStatus {
                        Text(status).font(.callout).foregroundStyle(.secondary).padding(.leading, 40)
                    }
                }.padding(.vertical, 4)
            }
            Section {
                Button("Show Setup Guide…") { (NSApp.delegate as? AppDelegate)?.showStartupTips(force: true) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 680)
    }
}

private struct PolicyRow: View {
    let title: String
    let value: String
    let explanation: String
    @State private var showingHelp = false

    init(_ title: String, value: String, help: String) {
        self.title = title
        self.value = value
        explanation = help
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
            Button { showingHelp.toggle() } label: {
                Image(systemName: "info.circle").frame(minWidth: 24, minHeight: 24).contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("About \(title)")
                .help(explanation)
                .popover(isPresented: $showingHelp, arrowEdge: .trailing) {
                    Text(explanation).font(.callout).padding(16).frame(width: 320)
                        .fixedSize(horizontal: false, vertical: true)
                }
        }.help(explanation)
    }
}
