import SwiftUI

struct ChangesView: View {
    let reader: ReaderState
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Changes since last review").font(.headline)
                Spacer()
                Text("\(reader.changes.count)").foregroundStyle(.secondary)
            }
            if reader.changes.entries.isEmpty {
                Text("Saved changes appear here automatically. Highlights stay until you mark the current version reviewed.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                if reader.changes.usesSectionComparison {
                    Text("Large document: changes compared by section position.").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(reader.changes.entries) { change in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(change.kind.rawValue).font(.caption.weight(.semibold))
                                        .foregroundStyle(change.kind == .removed ? .red : (change.kind == .added ? .green : .orange))
                                    Spacer()
                                    if let target = change.targetID {
                                        Button("Show") { reader.navigate(to: target); dismiss() }
                                    }
                                }
                                if !change.before.isEmpty {
                                    Text("Before").font(.caption).foregroundStyle(.secondary)
                                    Text(excerpt(change.before)).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                if !change.after.isEmpty {
                                    Text(change.kind == .added ? "Added text" : "Now").font(.caption).foregroundStyle(.secondary)
                                    Text(excerpt(change.after)).textSelection(.enabled)
                                }
                                if change.before == change.after {
                                    Text("Formatting, a link target, an image, or task status changed.").font(.caption).foregroundStyle(.secondary)
                                }
                                Divider()
                            }
                        }
                    }
                }.frame(maxHeight: 380)
                HStack {
                    Button("Previous") { reader.jumpToChange(backwards: true); dismiss() }
                        .disabled(reader.changes.navigable.isEmpty)
                    Button("Next") { reader.jumpToChange(); dismiss() }
                        .disabled(reader.changes.navigable.isEmpty)
                    Spacer()
                    Button("Mark Reviewed") { reader.markReviewed(); dismiss() }.buttonStyle(.bordered).fontWeight(.semibold)
                }
            }
            if let refreshed = reader.lastRefreshed {
                Text("Last refreshed \(refreshed.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.callout).padding(18).frame(width: 440)
    }

    private func excerpt(_ text: String) -> String {
        text.count > 1_200 ? String(text.prefix(1_200)) + "…" : text
    }
}
