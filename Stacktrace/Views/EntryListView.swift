import SwiftUI

/// Lists every entry for one day, with add / edit / delete.
struct EntryListView: View {
    let day: Date

    @EnvironmentObject private var store: DataStore
    @State private var editing: ReportEntry?
    @State private var editingIsNew = false

    private var entries: [ReportEntry] { store.entries(on: day) }

    private var isFuture: Bool { day > Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No entries", systemImage: "square.and.pencil")
                } description: {
                    Text("Add what you worked on this day.")
                } actions: {
                    Button("Add Entry") { addEntry() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(entries) { entry in
                        Group {
                            if entry.isQuick {
                                QuickItemRow(entry: entry) { store.delete(entry) }
                            } else if entry.isCheckin {
                                CheckinRow(entry: entry) { store.delete(entry) }
                            } else {
                                EntryRow(entry: entry)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editingIsNew = false
                                        editing = entry
                                    }
                                    .contextMenu {
                                        Button("Edit") {
                                            editingIsNew = false
                                            editing = entry
                                        }
                                        Button("Delete", role: .destructive) {
                                            store.delete(entry)
                                        }
                                    }
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }

            if !isFuture {
                Divider()
                QuickActions(day: day, onFullEntry: addEntry)
                    .padding(12)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addEntry() } label: {
                    Label("Add Entry", systemImage: "plus")
                }
                .disabled(isFuture)
            }
        }
        .sheet(item: $editing) { entry in
            EntryEditorView(entry: entry, isNew: editingIsNew)
        }
    }

    private func addEntry() {
        guard day <= Calendar.current.startOfDay(for: Date()) else { return }
        editingIsNew = true
        editing = ReportEntry(date: day)
    }

    private func delete(at offsets: IndexSet) {
        let list = entries
        for index in offsets {
            store.delete(list[index])
        }
    }
}

private struct EntryRow: View {
    let entry: ReportEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(.headline)
                    .foregroundStyle(entry.title.isEmpty ? .secondary : .primary)
                Spacer()
            }
            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !entry.tags.isEmpty {
                FlowLayout {
                    ForEach(entry.tags, id: \.self) { TagChip(name: $0) }
                }
            }
            HStack(spacing: 12) {
                if let mood = entry.mood {
                    Label(MoodScale.label(mood), systemImage: MoodScale.symbol(mood))
                        .foregroundStyle(MoodColor.color(for: mood))
                }
                if !entry.wentWell.isEmpty {
                    Label("Went well", systemImage: "hand.thumbsup")
                        .foregroundStyle(.green)
                }
                if !entry.wentBad.isEmpty {
                    Label("To improve", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption2)
        }
        .padding(.vertical, 4)
    }
}
