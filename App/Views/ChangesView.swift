import SwiftUI

struct ChangesView: View {
    let reader: ReaderState
    let dismiss: () -> Void
    @FocusState private var reviewFocused: Bool
    @AccessibilityFocusState private var accessibleReviewFocused: Bool
    @State private var reviewActionIntent: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Review Changes").font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(reader.changes.count) remaining").foregroundStyle(.secondary)
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Close review")
                    .help("Close review (Esc)")
                    .keyboardShortcut(reader.showFind ? nil : KeyboardShortcut(.escape, modifiers: []))
            }
            if let change = reader.selectedChange {
                HStack {
                    Button { reader.jumpToChange(backwards: true) } label: {
                        Image(systemName: "chevron.left")
                    }.accessibilityLabel("Previous change").help("Previous change")
                    Text("Change \(max(0, reader.currentChangeIndex) + 1) of \(reader.changes.count)")
                        .monospacedDigit().frame(maxWidth: .infinity)
                    Button { reader.jumpToChange() } label: {
                        Image(systemName: "chevron.right")
                    }.accessibilityLabel("Next change").help("Next change")
                }.disabled(reader.isRendering || reader.changes.count < 2)
                if reader.changes.usesSectionComparison {
                    Text("Large document: changes compared by section position.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ScrollView {
                    changeDetail(change)
                }.frame(maxHeight: .infinity)
                Divider()
                VStack(spacing: 8) {
                    Button("Mark This Reviewed") { reviewActionIntent = reader.focusIntentGeneration; reader.markCurrentChangeReviewed() }
                        .buttonStyle(.borderedProminent)
                        .focused($reviewFocused).accessibilityFocused($accessibleReviewFocused)
                        .help("Clear this highlight and advance to the next change")
                    Button("Mark All Reviewed") { reviewActionIntent = reader.focusIntentGeneration; reader.markReviewed() }
                        .help("Acknowledge every remaining change in this document")
                }.disabled(reader.isRendering)
                    .frame(maxWidth: .infinity)
            } else {
                Label("All changes reviewed", systemImage: "checkmark.circle")
                    .font(.title3).padding(.vertical, 6)
                Text("New saved changes will appear here automatically. Reviewing changes never modifies the file.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Spacer(); Button("Done", action: dismiss).focused($reviewFocused).accessibilityFocused($accessibleReviewFocused) }
            }
            if let refreshed = reader.lastRefreshed {
                Text("Last refreshed \(refreshed.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.callout).padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-panel")
        .onChange(of: reader.isRendering) {
            guard !reader.isRendering, let intent = reviewActionIntent else { return }
            reviewActionIntent = nil
            guard intent == reader.focusIntentGeneration else { return }
            reviewFocused = true
            if reader.announcements.isEligible() { accessibleReviewFocused = true }
        }
        .task(id: reader.returnFocusGeneration) {
            guard reader.returnFocusGeneration > 0, reader.navigationReturnTarget == .review else { return }
            let intent = reader.focusIntentGeneration
            await Task.yield()
            guard !Task.isCancelled, intent == reader.focusIntentGeneration else { return }
            reviewFocused = true
            if reader.announcements.isEligible() { accessibleReviewFocused = true }
        }
    }

    private func changeDetail(_ change: DocumentChange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(change.kind.rawValue, systemImage: change.kind == .removed ? "minus.circle" : (change.kind == .added ? "plus.circle" : "pencil.circle"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(change.kind == .removed ? .red : (change.kind == .added ? .green : .orange))
                Spacer()
                if let target = change.targetID {
                    Button("Show in Document") { reader.navigate(to: target, returnTo: .review) }
                }
            }
            if !change.beforeAccessibleText.isEmpty {
                Text("Before").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(excerpt(change.beforeAccessibleText)).foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            if !change.afterAccessibleText.isEmpty {
                Text("After").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(excerpt(change.afterAccessibleText)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            if change.beforeAccessibleText == change.afterAccessibleText {
                Text("Formatting, a link target, an image, or task status changed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func excerpt(_ text: String) -> String {
        text.count > 1_200 ? String(text.prefix(1_200)) + "…" : text
    }
}
