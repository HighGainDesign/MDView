import SwiftUI

struct ChangesView: View {
    let reader: ReaderState
    let dismiss: () -> Void
    private enum ReviewFocus: Hashable { case current, done }
    @FocusState private var reviewFocused: ReviewFocus?
    @AccessibilityFocusState private var accessibleReviewFocused: ReviewFocus?
    @State private var reviewActionIntent: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Changes").font(.headline).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(reader.changes.count) remaining").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
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
                        .monospacedDigit().multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
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
                    Button(action: markCurrentReviewed) {
                        Text("Mark This Reviewed").multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                    }
                        .buttonStyle(.borderedProminent)
                        .focusable().focused($reviewFocused, equals: .current).accessibilityFocused($accessibleReviewFocused, equals: .current)
                        .onKeyPress(.space, phases: .down) { _ in markCurrentReviewed(); return .handled }
                        .help("Clear this highlight and advance to the next change")
                    Button { reviewActionIntent = reader.focusIntentGeneration; reader.markReviewed() } label: {
                        Text("Mark All Reviewed").multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                    }
                        .help("Acknowledge every remaining change in this document")
                }.disabled(reader.isRendering)
                    .frame(maxWidth: .infinity)
            } else {
                Label("All changes reviewed", systemImage: "checkmark.circle")
                    .font(.title3).padding(.vertical, 6)
                Text("New saved changes will appear here automatically. Reviewing changes never modifies the file.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Spacer(); Button("Done", action: dismiss).focusable().focused($reviewFocused, equals: .done).accessibilityFocused($accessibleReviewFocused, equals: .done)
                    .onKeyPress(.space, phases: .down) { _ in dismiss(); return .handled } }
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
            reviewFocused = reader.selectedChange == nil ? .done : .current
            if reader.announcements.isEligible() { accessibleReviewFocused = reader.selectedChange == nil ? .done : .current }
        }
        .task(id: reader.returnFocusGeneration) {
            guard reader.returnFocusGeneration > 0, reader.navigationReturnTarget == .review else { return }
            let intent = reader.focusIntentGeneration
            await Task.yield()
            guard !Task.isCancelled, intent == reader.focusIntentGeneration else { return }
            reviewFocused = reader.selectedChange == nil ? .done : .current
            if reader.announcements.isEligible() { accessibleReviewFocused = reader.selectedChange == nil ? .done : .current }
        }
    }

    private func markCurrentReviewed() {
        guard !reader.isRendering else { return }
        reviewActionIntent = reader.focusIntentGeneration
        reader.markCurrentChangeReviewed()
    }

    private func changeDetail(_ change: DocumentChange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    kindLabel(change).fixedSize()
                    Spacer(minLength: 8)
                    showInDocument(change).fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) { kindLabel(change); showInDocument(change) }
            }
            if !change.beforeAccessibleText.isEmpty {
                Text("Before").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(change.beforeAccessibleText).foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            if !change.afterAccessibleText.isEmpty {
                Text("After").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(change.afterAccessibleText).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            if change.beforeAccessibleText == change.afterAccessibleText {
                Text("Formatting, a link target, an image, or task status changed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func kindLabel(_ change: DocumentChange) -> some View {
        Label(change.kind.localizedTitle, systemImage: change.kind == .removed ? "minus.circle" : (change.kind == .added ? "plus.circle" : "pencil.circle"))
            .font(.callout.weight(.semibold))
            .foregroundStyle(change.kind == .removed ? .red : (change.kind == .added ? .green : .orange))
    }
    @ViewBuilder private func showInDocument(_ change: DocumentChange) -> some View {
        if let target = change.targetID {
            Button { reader.navigate(to: target, returnTo: .review) } label: {
                Text("Show in Document").fixedSize(horizontal: false, vertical: true)
            }
        }
    }

}
