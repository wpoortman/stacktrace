import SwiftUI

/// Results across all days, matching a title query and/or selected tag
/// filters. Tapping a result jumps to that day.
struct SearchView: View {
    let query: String
    @Binding var tagFilter: Set<String>
    let onSelect: (Date) -> Void

    @EnvironmentObject private var store: DataStore

    private var results: [ReportEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.entries
            .filter { entry in
                let titleOK = q.isEmpty
                    || entry.title.lowercased().contains(q)
                    || entry.tags.contains { $0.lowercased().contains(q) }
                let tagsOK = tagFilter.isEmpty || tagFilter.isSubset(of: Set(entry.tags))
                return titleOK && tagsOK
            }
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !store.tags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FILTER BY TAG")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowLayout {
                        ForEach(store.tags, id: \.self) { tag in
                            TagChip(name: tag, filled: tagFilter.contains(tag)) {
                                if tagFilter.contains(tag) { tagFilter.remove(tag) }
                                else { tagFilter.insert(tag) }
                            }
                        }
                    }
                }
                .padding()
                Divider()
            }

            if results.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass",
                                       description: Text("Try a different title or tag."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(results) { entry in
                        Button {
                            onSelect(entry.date)
                        } label: {
                            SearchResultRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Search")
    }
}

private struct SearchResultRow: View {
    let entry: ReportEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(.headline)
                Spacer()
                Text(DateFormat.short.string(from: entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !entry.tags.isEmpty {
                FlowLayout {
                    ForEach(entry.tags, id: \.self) { TagChip(name: $0) }
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
