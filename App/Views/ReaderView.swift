import SwiftUI

struct ReaderView: View {
    @Bindable var reader: ReaderState
    @FocusState private var focusedOutlineHeading: String?
    @AccessibilityFocusState private var accessibleOutlineHeading: String?
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
            if reader.fileUpdatesPaused {
                HStack(spacing: 10) {
                    Image(systemName: "pause.circle")
                    Text(reader.hasPendingFileUpdate ? "Updates paused. A newer version is waiting." : "File updates paused.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Resume Updates") { reader.setFileUpdatesPaused(false) }
                }.font(.callout).padding(12).background(.quaternary)
                Divider()
            }
            if reader.checklistMode {
                HStack(spacing: 10) {
                    Image(systemName: "checklist")
                    Text(reader.checklistError ?? (reader.hasPendingFileUpdate ? "Resume updates before saving more checkmarks." : (reader.rendered?.tasks.isEmpty == true ? "This checklist cannot be mapped safely. Checkboxes remain disabled." : "Checkmarks save to this file.")))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Undo") { reader.undoChecklist() }.disabled(!reader.canUndoChecklist)
                    Button("Stop Saving Checkmarks") { reader.checklistMode = false }
                        .fixedSize()
                        .disabled(reader.checklistSaving)
                        .help("Keeps the checkmarks already saved. Clicking a checkbox again asks before saving further changes.")
                }.font(.callout).padding(12).background(.quaternary)
                Divider()
            }
            if let message = reader.localImageError {
                HStack {
                    Image(systemName: "photo")
                    Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Retry") { reader.reload() }
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
            GeometryReader { geometry in
                let beside = geometry.size.width >= 840 + (reader.showOutline ? 220 : 0)
                // Keep the document at the same structural path in both layouts.
                // Opening or relocating review must not recreate its WKWebView.
                VSplitView {
                    HSplitView {
                        documentPane.frame(minWidth: beside && reader.showChanges ? 360 : 0,
                                           minHeight: reader.showChanges ? 180 : 0)
                        if reader.showChanges && beside {
                            reviewPanel.frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
                        }
                    }
                    if reader.showChanges && !beside {
                        reviewPanel.frame(minHeight: 240, idealHeight: 280, maxHeight: 360)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(ReaderWindowMinimumSize(minimumHeight: reader.showChanges ? (beside ? 420 : 620) : 300))
            }
            Divider()
            ReaderStatusBar(reader: reader)
        }
        .alert("Save checkmarks to this file?", isPresented: $reader.showChecklistConfirmation, presenting: reader.pendingChecklistConfirmation) { _ in
            Button("Save Checkmarks") { reader.confirmChecklistSaving() }
            Button("Cancel", role: .cancel) { reader.cancelChecklistConfirmation() }
        } message: { pending in
            Text("Checkmarks in “\(pending.fileURL.lastPathComponent)” save automatically. Other text stays unchanged, and you can undo each change.")
        }
        .background(ReaderWindowContext(reader: reader).frame(width: 0, height: 0).accessibilityHidden(true))
        .frame(minWidth: 480, minHeight: 300)
        .preferredColorScheme(documentAppearance == .system ? nil : (documentAppearance == .dark ? .dark : .light))
        .task { reader.documentAppearance = documentAppearance; await reader.watchFile() }
        .onChange(of: documentAppearance) { reader.documentAppearance = documentAppearance; reader.render() }
        .onChange(of: reader.wide) { reader.render() }
        .onChange(of: reader.loadRemoteImages) { reader.render() }
        .task(id: reader.returnFocusGeneration) {
            guard reader.returnFocusGeneration > 0, case .outline(let id) = reader.navigationReturnTarget else { return }
            let intent = reader.focusIntentGeneration
            await Task.yield()
            guard !Task.isCancelled, intent == reader.focusIntentGeneration else { return }
            focusedOutlineHeading = id
            if reader.announcements.isEligible() { accessibleOutlineHeading = id }
        }
        .onChange(of: reader.showChanges) {
            if reader.showChanges, let target = reader.selectedChange?.targetID { reader.navigate(to: target, focus: false) }
        }
    }

    private var documentPane: some View {
        HStack(spacing: 0) {
            if reader.showOutline { outline; Divider() }
            if let rendered = reader.rendered {
                MarkdownWebView(reader: reader, html: rendered.html, checklistEnabled: reader.checklistMode, checklistSaving: reader.checklistSaving, checklistRendering: reader.isRendering, checklistPromptPresented: reader.showChecklistConfirmation)
            } else {
                ProgressView("Rendering Markdown…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var reviewPanel: some View {
        ChangesView(reader: reader, dismiss: { reader.showChanges = false })
            .background(.bar)
    }

    private var findBar: some View {
        HStack {
            ReaderFindField(text: $reader.searchText, focusGeneration: reader.findFocusGeneration,
                            submit: { reader.searchBackwards = false; reader.searchGeneration += 1 },
                            cancel: { reader.showFind = false; reader.searchText = "" })
                .frame(minHeight: 22)
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
                    .accessibilityAddTraits(.isHeader)
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
                        .accessibilityValue("Heading level \(heading.level)")
                        .accessibilityIdentifier("outline-heading-" + heading.id)
                        .focused($focusedOutlineHeading, equals: heading.id)
                        .accessibilityFocused($accessibleOutlineHeading, equals: heading.id)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(width: 220)
    }
}
