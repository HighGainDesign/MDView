import SwiftUI

struct ReaderView: View {
    @Bindable var reader: ReaderState
    @FocusState private var searchFocused: Bool
    @AppStorage(ReaderPreferences.appearanceKey, store: ReaderPreferences.defaults) private var documentAppearance = DocumentAppearance.system
    @State private var showChanges = false

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if reader.showFind { findBar; Divider() }
            if reader.imagePermissionRequired {
                HStack {
                    Image(systemName: "photo")
                    Text("Grant folder access to show this document’s local images.")
                    Spacer()
                    Button("Grant Image Folder…") { reader.allowImageFolder() }
                }.font(.callout).padding(12).background(.quaternary)
                Divider()
            }
            if let message = reader.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message).textSelection(.enabled)
                    Spacer()
                    Button("Retry") { reader.reload() }
                }.font(.callout).padding(12).background(.quaternary)
            }
            HStack(spacing: 0) {
                if reader.showOutline { outline; Divider() }
                if let rendered = reader.rendered {
                    MarkdownWebView(reader: reader, html: rendered.html)
                } else {
                    ProgressView("Rendering Markdown…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 300)
        .preferredColorScheme(documentAppearance == .system ? nil : (documentAppearance == .dark ? .dark : .light))
        .task { reader.documentAppearance = documentAppearance; await reader.watchFile() }
        .onChange(of: documentAppearance) { reader.documentAppearance = documentAppearance; reader.render() }
        .onChange(of: reader.wide) { reader.render() }
        .onChange(of: reader.loadRemoteImages) { reader.render() }
        .onChange(of: reader.showFind) { searchFocused = reader.showFind }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { reader.showOutline.toggle() } label: { Image(systemName: "sidebar.left") }
                .help("Toggle outline (⌥⌘O)").accessibilityLabel("Toggle outline")
            if let headings = reader.rendered?.headings, !headings.isEmpty {
                Menu {
                    ForEach(headings) { heading in
                        Button(String(repeating: "  ", count: max(0, heading.level - 1)) + heading.title) {
                            reader.navigate(to: heading.id)
                        }
                    }
                } label: { Label("Outline", systemImage: "list.bullet.indent") }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Jump to a heading without opening the sidebar")
            }
            Spacer(minLength: 8)
            if reader.fileURL != nil {
                Button { showChanges.toggle() } label: {
                    Label(reader.changes.count == 0 ? "Live" : "\(reader.changes.count) changes", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(reader.changes.count == 0 ? Color.secondary : Color.orange)
                }
                .help("Files refresh automatically. Review changes since the last version you marked reviewed.")
                .popover(isPresented: $showChanges) { ChangesView(reader: reader, dismiss: { showChanges = false }) }
                .fixedSize()
            }
            if let rendered = reader.rendered {
                Text("\(rendered.wordCount.formatted()) words").font(.caption).foregroundStyle(.secondary)
            }
            Button { reader.showFind.toggle() } label: { Image(systemName: "magnifyingglass") }
                .help("Find (⌘F)").accessibilityLabel("Find in document")
            Button { reader.wide.toggle() } label: {
                Image(systemName: "arrow.left.and.right")
                    .foregroundStyle(reader.wide ? Color.accentColor : Color.secondary)
            }
            .help(reader.wide ? "Use comfortable reading width" : "Use full window width")
            .accessibilityLabel(reader.wide ? "Use comfortable reading width" : "Use full window width")
            .accessibilityValue(reader.wide ? "Full width" : "Comfortable width")
            Menu {
                Toggle("Full Width", isOn: $reader.wide)
                Toggle("Load Remote Images", isOn: $reader.loadRemoteImages)
                    .help("For this document only. HTTPS image hosts can see your IP address and that you opened their image. Off each time a document is opened.")
                Button("Zoom In") { reader.changeZoom(by: 0.1) }
                Button("Zoom Out") { reader.changeZoom(by: -0.1) }
                Button("Actual Size") { reader.zoom = 1 }
                if let url = reader.fileURL {
                    Divider()
                    Button("Reload") { reader.reload() }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button("Grant Image Folder…") { reader.allowImageFolder() }
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize().help("Reading options").accessibilityLabel("Reading options")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var findBar: some View {
        HStack {
            TextField("Find in document", text: $reader.searchText)
                .textFieldStyle(.roundedBorder).focused($searchFocused)
                .onSubmit { reader.searchBackwards = false; reader.searchGeneration += 1 }
                .onChange(of: reader.searchText) { reader.searchBackwards = false; reader.searchGeneration += 1 }
            if !reader.searchFound && !reader.searchText.isEmpty {
                Text("No matches").font(.caption).foregroundStyle(.secondary)
            }
            Button { reader.searchBackwards = true; reader.searchGeneration += 1 } label: { Image(systemName: "chevron.up") }
                .accessibilityLabel("Previous match")
            Button { reader.searchBackwards = false; reader.searchGeneration += 1 } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel("Next match")
            Button("Done") { reader.showFind = false; reader.searchText = "" }
                .keyboardShortcut(.escape, modifiers: [])
        }.padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var outline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("OUTLINE").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 8)
                if reader.rendered?.headings.isEmpty == true {
                    Text("No headings").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(reader.rendered?.headings ?? []) { heading in
                    Button {
                        reader.navigate(to: heading.id)
                    } label: {
                        Text(heading.title).font(.callout).foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .padding(.leading, CGFloat(max(0, heading.level - 1)) * 10)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                    }.buttonStyle(.plain)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(width: 220)
    }
}
