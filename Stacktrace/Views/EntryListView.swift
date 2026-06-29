import SwiftUI
import AppKit

/// Lists every entry for one day, with add / edit / delete.
struct EntryListView: View {
    let day: Date

    @EnvironmentObject private var store: DataStore
    @State private var editing: ReportEntry?
    @State private var editingIsNew = false
    @State private var exporting = false

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
                            if entry.isMeeting {
                                MeetingRow(entry: entry) { store.delete(entry) }
                            } else if entry.isExercise {
                                ExerciseRow(entry: entry) { store.delete(entry) }
                            } else if entry.isQuick {
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
                    .onMove { store.moveEntries(on: day, from: $0, to: $1) }
                }
            }

            MeetingsReview(day: day)

            if !isFuture {
                Divider()
                QuickActions(day: day, onFullEntry: addEntry)
                    .padding(12)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { exporting = true } label: {
                    Label("Export this day", systemImage: "square.and.arrow.up")
                }
                .disabled(entries.isEmpty)
                Button { addEntry() } label: {
                    Label("Add Entry", systemImage: "plus")
                }
                .disabled(isFuture)
            }
        }
        .sheet(item: $editing) { entry in
            EntryEditorView(entry: entry, isNew: editingIsNew)
        }
        .sheet(isPresented: $exporting) {
            DayExportSheet(day: day)
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

/// Name-only export prompt for a single day's report.
private struct DayExportSheet: View {
    let day: Date
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var generating = false
    @State private var error: String?
    @State private var generator: PDFReportGenerator?

    private var defaultBaseName: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return "Work Report \(f.string(from: day))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export \(DateFormat.dayHeader.string(from: day))")
                .font(.title3.bold())

            TextField(defaultBaseName, text: $name)
                .textFieldStyle(.roundedBorder)
            Text("File name — leave blank to use the default.")
                .font(.caption).foregroundStyle(.secondary)

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button {
                    export()
                } label: {
                    if generating { ProgressView().controlSize(.small) }
                    else { Text("Export PDF") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(generating)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func resolvedBaseName() -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? defaultBaseName : cleaned
    }

    private func export() {
        error = nil
        let url = ExportStore.uniqueURL(baseName: resolvedBaseName())
        let entries = store.entries(on: day)
        let routines = store.routines.filter { $0.includeInReport }
        let ids = Set(routines.map(\.id))
        let logs = store.routineLogs.filter {
            ids.contains($0.routineID) && Calendar.current.isDate($0.day, inSameDayAs: day)
        }
        let ratings = store.dayRatings.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
        let names = Dictionary(store.projects.map { ($0.id, $0.name) }) { a, _ in a }
        let html = ReportHTMLBuilder.html(entries: entries, routines: routines,
                                          routineLogs: logs, dayRatings: ratings,
                                          holidays: store.holidays, projectNames: names,
                                          from: day, to: day)
        generating = true
        let gen = PDFReportGenerator()
        generator = gen
        gen.generate(html: html, to: url) { result in
            generating = false
            generator = nil
            switch result {
            case .success(let url):
                NSWorkspace.shared.activateFileViewerSelecting([url])
                dismiss()
            case .failure(let err):
                error = err.localizedDescription
            }
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
