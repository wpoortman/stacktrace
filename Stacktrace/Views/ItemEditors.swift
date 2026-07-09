import SwiftUI

/// Compact editors for the non-"full-entry" item types shown in the day list:
/// quick win/setback/note, exercise, check-in, and meeting reflections. Each
/// works on a local copy and commits with `store.upsert` on Save.

/// Edit a quick win / setback / note. Win & setback keep their fixed mood; a
/// note can also change its "how it went" mood and icon.
struct QuickItemEditSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var entry: ReportEntry
    @State private var text: String
    @State private var mood: Int?
    @State private var icon: String
    @State private var project: UUID?

    init(entry: ReportEntry) {
        _entry = State(initialValue: entry)
        _text = State(initialValue: entry.detail)
        _mood = State(initialValue: entry.mood)
        _icon = State(initialValue: entry.icon ?? NoteIcon.default)
        _project = State(initialValue: entry.projectID)
    }

    private var isNote: Bool { entry.quickKind == "note" }

    private var heading: String {
        switch entry.quickKind {
        case "win": return "Edit win"
        case "fail": return "Edit setback"
        default: return "Edit quick log"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(heading).font(.title3.bold())

            TextField("Text", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            if isNote {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Icon").font(.caption).foregroundStyle(.secondary)
                    IconPicker(selection: $icon)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("How it went (optional)").font(.caption).foregroundStyle(.secondary)
                    MoodPicker(mood: $mood)
                }
            }

            if !store.projects.isEmpty {
                Picker("Project", selection: $project) {
                    Text("None").tag(UUID?.none)
                    ForEach(store.projects) { p in Text(p.name).tag(UUID?.some(p.id)) }
                }
            }

            EditorButtons(entry: entry,
                          canSave: !text.trimmingCharacters(in: .whitespaces).isEmpty,
                          onSave: save)
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        entry.detail = text.trimmingCharacters(in: .whitespaces)
        if isNote {
            entry.mood = mood
            entry.icon = icon
        }
        entry.projectID = project
        store.upsert(entry)
        dismiss()
    }
}

/// Edit a logged exercise: its name and duration.
struct ExerciseEditSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var entry: ReportEntry
    @State private var name: String
    @State private var minutes: Int

    init(entry: ReportEntry) {
        _entry = State(initialValue: entry)
        _name = State(initialValue: entry.exercise ?? "")
        _minutes = State(initialValue: entry.durationMinutes ?? 20)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit exercise").font(.title3.bold())

            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            Stepper(value: $minutes, in: 1...240, step: 5) {
                Text("Duration: \(minutes) min")
            }

            EditorButtons(entry: entry,
                          canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                          onSave: save)
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        entry.exercise = name.trimmingCharacters(in: .whitespaces)
        entry.durationMinutes = minutes
        store.upsert(entry)
        dismiss()
    }
}

/// Edit a one-tap mood check-in.
struct CheckinEditSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var entry: ReportEntry
    @State private var mood: Int?

    init(entry: ReportEntry) {
        _entry = State(initialValue: entry)
        _mood = State(initialValue: entry.mood)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit check-in").font(.title3.bold())
            MoodPicker(mood: $mood)
            EditorButtons(entry: entry, canSave: mood != nil, onSave: save)
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        entry.mood = mood
        store.upsert(entry)
        dismiss()
    }
}

/// Edit a meeting reflection: whether it happened, mood, and notes.
struct MeetingEditSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var entry: ReportEntry
    @State private var title: String
    @State private var happened: Bool
    @State private var mood: Int?
    @State private var wentWell: String
    @State private var wentBad: String

    init(entry: ReportEntry) {
        _entry = State(initialValue: entry)
        _title = State(initialValue: entry.title)
        _happened = State(initialValue: entry.happened ?? true)
        _mood = State(initialValue: entry.mood)
        _wentWell = State(initialValue: entry.wentWell)
        _wentBad = State(initialValue: entry.wentBad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit meeting").font(.title3.bold())

            TextField("Meeting", text: $title).textFieldStyle(.roundedBorder)
            Toggle("It happened", isOn: $happened)

            if happened {
                MoodPicker(mood: $mood)
                field("What went well", text: $wentWell)
                field("What didn't / to improve", text: $wentBad)
            }

            EditorButtons(entry: entry, canSave: true, onSave: save)
        }
        .padding(20)
        .frame(width: 440)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            SpellCheckTextEditor(text: text)
                .frame(height: 56)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        }
    }

    private func save() {
        entry.title = title.trimmingCharacters(in: .whitespaces)
        entry.happened = happened
        entry.mood = happened ? mood : nil
        entry.wentWell = happened ? wentWell : ""
        entry.wentBad = happened ? wentBad : ""
        store.upsert(entry)
        dismiss()
    }
}

/// Shared Cancel / Delete / Save footer for the compact editors.
private struct EditorButtons: View {
    let entry: ReportEntry
    let canSave: Bool
    let onSave: () -> Void

    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button("Delete", role: .destructive) {
                store.delete(entry); dismiss()
            }
            .foregroundStyle(.red)
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Save", action: onSave)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
        }
    }
}
