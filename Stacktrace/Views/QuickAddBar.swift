import SwiftUI

private struct Compose: Identifiable {
    let id = UUID()
    let kind: String
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
    private let exercise = Color(red: 0.20, green: 0.62, blue: 0.86)

    var body: some View {
        HStack(spacing: 12) {
            bigButton("Quick win", "party.popper.fill", win) { compose = Compose(kind: "win") }
            bigButton("Setback", "exclamationmark.triangle.fill", bad) { compose = Compose(kind: "fail") }
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

/// Modal to capture a single win / setback line.
private struct QuickComposeSheet: View {
    let kind: String
    let day: Date

    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var isWin: Bool { kind == "win" }
    private var tint: Color { MoodColor.color(for: isWin ? 5 : 2) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: isWin ? "party.popper.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(tint, in: RoundedRectangle(cornerRadius: 10))
                Text(isWin ? "Add a win" : "Add a setback")
                    .font(.title3.bold())
            }

            TextField(isWin ? "A small win…" : "A setback…", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .focused($focused)
                .onSubmit(commit)

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
        .onAppear { focused = true }
    }

    private func commit() {
        store.addQuick(text, kind: kind, on: day)
        dismiss()
    }
}

/// Simple wizard to log an exercise: pick one and set how long.
private struct ExerciseWizard: View {
    let day: Date
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    static let options = ["Walk", "Stretch", "Push-ups", "Squats", "Yoga",
                          "Cycling", "Run", "Stairs", "Other"]
    private let tint = Color(red: 0.20, green: 0.62, blue: 0.86)

    @State private var choice = "Walk"
    @State private var custom = ""
    @State private var minutes = 20

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

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    store.addExercise(name, minutes: minutes, on: day)
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

/// Shared compact row for a quick win / setback item.
struct QuickItemRow: View {
    let entry: ReportEntry
    var onDelete: () -> Void = {}
    @State private var hovering = false

    private var isWin: Bool { entry.quickKind == "win" }

    private var tint: Color { isWin ? MoodColor.color(for: 5) : MoodColor.color(for: 2) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isWin ? "party.popper.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(tint, in: RoundedRectangle(cornerRadius: 9))

            Text(entry.detail)
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
