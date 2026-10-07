import SwiftUI

/// Actions live here; passive information belongs in ReaderStatusBar.
struct ReaderToolbar: View {
    @Bindable var reader: ReaderState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            controls(compact: false)
            controls(compact: true)
        }
        .buttonStyle(.bordered)
        .menuStyle(.borderedButton)
        .controlSize(.regular)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    private func controls(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button { reader.showOutline.toggle() } label: {
                Image(systemName: "sidebar.left").frame(width: 18, height: 20)
            }
            .fixedSize()
            .tint(reader.showOutline ? .accentColor : .secondary)
            .help("Toggle outline (⌥⌘O)")
            .accessibilityLabel("Outline sidebar")
            .accessibilityValue(reader.showOutline ? "Shown" : "Hidden")

            Menu {
                ForEach(reader.rendered?.headings ?? []) { heading in
                    Button(String(repeating: "  ", count: max(0, heading.level - 1)) + heading.title) {
                        reader.navigate(to: heading.id)
                    }
                }
            } label: {
                if compact {
                    Image(systemName: "list.bullet.indent").frame(width: 18, height: 20)
                } else {
                    Label("Outline", systemImage: "list.bullet.indent")
                }
            }
            .accessibilityLabel("Jump to heading")
            .disabled(reader.rendered?.headings.isEmpty ?? true)
            .help("Jump to a heading")
            .fixedSize()

            Spacer(minLength: 8)

            if reader.isStreamingPreview {
                Button { reader.streamPaused.toggle() } label: {
                    Label(reader.streamPaused ? "Resume" : "Pause",
                          systemImage: reader.streamPaused ? "play.fill" : "pause.fill")
                }
                .help(reader.streamPaused
                      ? "Resume following the editor and show its latest text"
                      : "Hold this preview while you edit or switch documents")
                .accessibilityLabel(reader.streamPaused ? "Resume live preview" : "Pause live preview")
                .fixedSize()
                toolSeparator
            } else if reader.fileURL != nil {
                Button { reader.showChanges.toggle() } label: {
                    HStack(spacing: 6) {
                        if !compact { Image(systemName: "text.badge.checkmark") }
                        Text(compact ? "Changes" : "Review Changes")
                        if reader.changes.count > 0 {
                            Text(reader.changes.count > 99 ? "99+" : reader.changes.count.formatted())
                                .font(.caption.weight(.semibold)).monospacedDigit()
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
                .help("Review saved changes (⇧⌘R)")
                .accessibilityLabel("Review changes")
                .accessibilityValue("\(reader.changes.count) unreviewed changes")
                .popover(isPresented: $reader.showChanges) {
                    ChangesView(reader: reader, dismiss: { reader.showChanges = false })
                }
                .fixedSize()
                toolSeparator
            }

            Button { reader.showFind.toggle() } label: {
                Image(systemName: "magnifyingglass").frame(width: 18, height: 20)
            }
            .fixedSize()
            .tint(reader.showFind ? .accentColor : .secondary)
            .help("Find in document (⌘F)")
            .accessibilityLabel("Find in document")
            .accessibilityValue(reader.showFind ? "Shown" : "Hidden")

            Button { reader.wide.toggle() } label: {
                Image(systemName: "arrow.left.and.right").frame(width: 18, height: 20)
            }
            .fixedSize()
            .tint(reader.wide ? .accentColor : .secondary)
            .help(reader.wide ? "Use comfortable reading width" : "Use full window width")
            .accessibilityLabel("Reading width")
            .accessibilityValue(reader.wide ? "Full width" : "Comfortable width")

            Menu {
                Toggle("Full Width", isOn: $reader.wide)
                Toggle("Load Remote Images", isOn: $reader.loadRemoteImages)
                    .help("For this document only. HTTPS image hosts can see your IP address and that you opened their image. Off each time a document is opened.")
                Divider()
                Button("Zoom In") { reader.changeZoom(by: 0.1) }
                Button("Zoom Out") { reader.changeZoom(by: -0.1) }
                Button("Actual Size") { reader.zoom = 1 }
                if let url = reader.fileURL {
                    Divider()
                    Button("Reload") { reader.reload() }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button("Grant Image Folder…") { reader.allowImageFolder() }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 18, height: 20) }
            .help("Reading options").accessibilityLabel("Reading options")
            .fixedSize()
        }
    }

    private var toolSeparator: some View {
        Divider().frame(height: 18).padding(.horizontal, 2).accessibilityHidden(true)
    }
}

struct ReaderStatusBar: View {
    var reader: ReaderState

    var body: some View {
        HStack(spacing: 12) {
            if reader.isStreamingPreview {
                Label(streamStatus, systemImage: streamSymbol)
                    .help(reader.streamPaused
                          ? "This preview is held. Resume to show the latest streamed text."
                          : "Follows the editor publishing to the Marked-compatible channel. Source names are supplied by the editor.")
            } else if reader.fileURL != nil {
                Label(reader.errorMessage == nil ? "Automatic updates" : "Refresh failed",
                      systemImage: reader.errorMessage == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle")
                    .help("Saved file changes appear automatically. Use Review Changes to compare with the last version you marked reviewed.")
            } else {
                Text("Snapshot preview").help("This preview does not receive live updates.")
            }
            Spacer(minLength: 8)
            if let rendered = reader.rendered {
                Text("\(rendered.wordCount.formatted()) words").monospacedDigit().fixedSize()
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(.bar)
    }

    private var streamStatus: String {
        let source = reader.streamSourceName ?? "Live stream"
        if reader.streamPaused { return "\(source) · Paused" }
        if reader.streamError != nil { return "Live preview unavailable" }
        return reader.streamIsReceiving ? "\(source) · Live" : "Waiting for a live stream"
    }

    private var streamSymbol: String {
        if reader.streamPaused { return "pause.circle" }
        return reader.streamError == nil ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle"
    }
}
