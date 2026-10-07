import SwiftUI

struct ReaderView: View {
    @Bindable var reader: ReaderState
    @FocusState private var searchFocused: Bool
    @AppStorage(ReaderPreferences.appearanceKey, store: ReaderPreferences.defaults) private var documentAppearance = DocumentAppearance.system

    var body: some View {
        VStack(spacing: 0) {
            ReaderToolbar(reader: reader)
            Divider()
            if reader.showFind { findBar; Divider() }
            if reader.isStreamingPreview && !reader.streamPaused && (!reader.streamIsReceiving || reader.streamError != nil) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: reader.streamError == nil ? "info.circle" : "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reader.streamError == nil ? "Waiting for a live stream" : "Live preview unavailable").fontWeight(.medium)
                        Text(reader.streamError ?? "Enable your editor’s Marked streaming preview integration, then start editing. In Drafts, use Settings → General. Marked can stay closed.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }.font(.callout).padding(12).background(.quaternary)
                Divider()
            }
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
            Divider()
            ReaderStatusBar(reader: reader)
        }
        .frame(minWidth: 480, minHeight: 300)
        .preferredColorScheme(documentAppearance == .system ? nil : (documentAppearance == .dark ? .dark : .light))
        .task { reader.documentAppearance = documentAppearance; await reader.watchFile() }
        .onChange(of: documentAppearance) { reader.documentAppearance = documentAppearance; reader.render() }
        .onChange(of: reader.wide) { reader.render() }
        .onChange(of: reader.loadRemoteImages) { reader.render() }
        .onChange(of: reader.showFind) { searchFocused = reader.showFind }
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
