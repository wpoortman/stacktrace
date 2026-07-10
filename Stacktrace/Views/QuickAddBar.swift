import SwiftUI

private struct Compose: Identifiable {
    let id = UUID()
    let kind: String
}

/// Emoji icons a quick note can be tagged with. Emoji render identically in the
/// app, the PDF (HTML) and copied Markdown, so no symbol mapping is needed.
enum NoteIcon {
    static let `default` = "📝"
    static let options = ["📝", "💻", "🐛", "🔧", "🚀", "📞", "📧", "📄",
                          "🎨", "🔍", "💡", "📊", "🤝", "✅", "⏳", "☕️"]
}

/// Three big actions: log a quick win, a setback, or open the full entry form.
/// Win / setback open a small modal to capture the one-liner.
struct QuickActions: View {
    let day: Date
    var onFullEntry: () -> Void

    @State private var compose: Compose?
    @State private var showExercise = false

    private let win = MoodColor.color(for: 5)
    private let bad = MoodColor.color(for: 2)
    private let note = Color(red: 0.36, green: 0.42, blue: 0.55)
    private let exercise = Color(red: 0.20, green: 0.62, blue: 0.86)

    var body: some View {
        HStack(spacing: 12) {
            bigButton("Quick win", "party.popper.fill", win) { compose = Compose(kind: "win") }
            bigButton("Setback", "exclamationmark.triangle.fill", bad) { compose = Compose(kind: "fail") }
            bigButton("Quick log", "note.text", note) { compose = Compose(kind: "note") }
            bigButton("Exercise", "figure.run", exercise) { showExercise = true }
            bigButton("Full entry", "square.and.pencil", .accentColor, action: onFullEntry)
        }
        .sheet(item: $compose) { c in
            QuickComposeSheet(kind: c.kind, day: day)
        }
        .sheet(isPresented: $showExercise) {
            ExerciseWizard(day: day)
        }
    }

    private func bigButton(_ title: String, _ symbol: String, _ tint: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// Modal to capture a single win / setback / note line.
private struct QuickComposeSheet: View {
    let kind: String
    let day: Date

    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var mood: Int?
    @State private var icon = NoteIcon.default
    @State private var project: UUID?
    @State private var enhancing = false
    @State private var enhanceError: String?
    @FocusState private var focused: Bool

    private var isWin: Bool { kind == "win" }
    private var isNote: Bool { kind == "note" }

    private var tint: Color {
        switch kind {
        case "win": return MoodColor.color(for: 5)
        case "fail": return MoodColor.color(for: 2)
        default: return Color(red: 0.36, green: 0.42, blue: 0.55)
        }
    }

    private var symbol: String {
        switch kind {
        case "win": return "party.popper.fill"
        case "fail": return "exclamationmark.triangle.fill"
        default: return "note.text"
        }
    }

    private var heading: String {
        switch kind {
        case "win": return "Add a win"
        case "fail": return "Add a setback"
        default: return "Quick log"
        }
    }

    private var placeholder: String {
        switch kind {
        case "win": return "A small win…"
        case "fail": return "A setback…"
        default: return "What did you do?"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(tint, in: RoundedRectangle(cornerRadius: 10))
                Text(heading)
                    .font(.title3.bold())
            }

            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .focused($focused)
                .onSubmit(commit)

            EnhanceButton(enhancing: enhancing, error: enhanceError,
                          canRun: !text.trimmingCharacters(in: .whitespaces).isEmpty,
                          action: enhance)

            if isNote {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Icon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    IconPicker(selection: $icon)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(isNote ? "How it went (optional)" : "Mood — feeds the mood graph")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MoodPicker(mood: $mood)
            }

            if !store.projects.isEmpty {
                Picker("Project", selection: $project) {
                    Text("None").tag(UUID?.none)
                    ForEach(store.projects) { p in Text(p.name).tag(UUID?.some(p.id)) }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            focused = true
            if mood == nil { mood = kind == "win" ? 5 : (kind == "fail" ? 2 : nil) }
        }
    }

    private func commit() {
        store.addQuick(text, kind: kind, mood: mood,
                       icon: isNote ? icon : nil, on: day, projectID: project)
        dismiss()
    }

    private func enhance() {
        enhanceError = nil
        enhancing = true
        let snapshot = EntryText(title: "", detail: text, wentWell: "", wentBad: "")
        Task {
            do {
                let result = try await EnhancementService.enhance(snapshot)
                text = result.detail
            } catch {
                enhanceError = error.localizedDescription
            }
            enhancing = false
        }
    }
}

/// A wrapping grid of emoji to tag a quick note with.
struct IconPicker: View {
    @Binding var selection: String

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(NoteIcon.options, id: \.self) { emoji in
                let picked = selection == emoji
                Button {
                    selection = emoji
                } label: {
                    Text(emoji)
                        .font(.title3)
                        .frame(width: 40, height: 36)
                        .background(
                            picked ? Color.accentColor.opacity(0.20)
                                   : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(picked ? Color.accentColor : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Simple wizard to log an exercise: pick one and set how long.
struct ExerciseWizard: View {
    let day: Date
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    static let options = ["Walk", "Stretch", "Push-ups", "Squats", "Yoga",
                          "Cycling", "Run", "Stairs", "Other"]
    private let tint = Color(red: 0.20, green: 0.62, blue: 0.86)

    @State private var choice = "Walk"
    @State private var custom = ""
    @State private var minutes = 20
    @State private var mood: Int?

    private var name: String { choice == "Other" ? custom : choice }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(tint, in: RoundedRectangle(cornerRadius: 10))
                Text("Log exercise").font(.title3.bold())
            }

            Picker("Exercise", selection: $choice) {
                ForEach(Self.options, id: \.self) { Text($0).tag($0) }
            }
            if choice == "Other" {
                TextField("Name", text: $custom).textFieldStyle(.roundedBorder)
            }

            Stepper(value: $minutes, in: 1...240, step: 5) {
                Text("Duration: \(minutes) min")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Mood — feeds the mood graph (optional)")
                    .font(.caption).foregroundStyle(.secondary)
                MoodPicker(mood: $mood)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    store.addExercise(name, minutes: minutes, mood: mood, on: day)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

/// Compact row for a logged exercise activity.
struct ExerciseRow: View {
    let entry: ReportEntry
    var onDelete: () -> Void = {}
    @State private var hovering = false

    private let tint = Color(red: 0.20, green: 0.62, blue: 0.86)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(tint, in: RoundedRectangle(cornerRadius: 9))
            Text(entry.exercise ?? "Exercise")
                .font(.body)
            if let m = entry.durationMinutes {
                Text("· \(m) min").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0.4)
            .help("Remove")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Compact row for a one-tap mood check-in.
struct CheckinRow: View {
    let entry: ReportEntry
    var onDelete: () -> Void = {}
    @State private var hovering = false

    private var mood: Int { entry.mood ?? 3 }
    private var tint: Color { MoodColor.color(for: mood) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: MoodScale.symbol(mood))
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(tint, in: RoundedRectangle(cornerRadius: 9))
            Text("Felt \(MoodScale.label(mood).lowercased())")
                .font(.body)
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0.4)
            .help("Remove")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Shared compact row for a quick win / setback / note item.
struct QuickItemRow: View {
    let entry: ReportEntry
    var onDelete: () -> Void = {}
    @EnvironmentObject private var store: DataStore
    @State private var hovering = false

    private var isNote: Bool { entry.quickKind == "note" }

    private var symbol: String {
        switch entry.quickKind {
        case "win": return "party.popper.fill"
        case "fail": return "exclamationmark.triangle.fill"
        default: return "note.text"
        }
    }

    private var tint: Color {
        switch entry.quickKind {
        case "win": return MoodColor.color(for: entry.mood ?? 5)
        case "fail": return MoodColor.color(for: entry.mood ?? 2)
        default:
            // A note is neutral — tint by its mood if one was set, else gray.
            if let m = entry.mood { return MoodColor.color(for: m) }
            return Color(red: 0.36, green: 0.42, blue: 0.55)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isNote {
                    Text(entry.icon ?? NoteIcon.default).font(.title3)
                } else {
                    Image(systemName: symbol).font(.title2).foregroundStyle(.white)
                }
            }
            .frame(width: 38, height: 38)
            .background(tint.opacity(isNote ? 0.16 : 1), in: RoundedRectangle(cornerRadius: 9))

            Text(entry.detail)
                .font(.body)
            if isNote, let m = entry.mood {
                Text("· \(MoodScale.label(m).lowercased())")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let project = store.projectName(entry.projectID) {
                ProjectChip(name: project)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0.4)
            .help("Remove")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
