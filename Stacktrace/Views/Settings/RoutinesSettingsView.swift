import SwiftUI

/// Manage movement / health routines: add, edit, delete.
struct RoutinesSettingsView: View {
    @EnvironmentObject private var store: DataStore
    @State private var editing: Routine?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keep yourself moving while you work. Routines can remind you and appear in your report.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    editing = Routine(name: "")
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            .padding(16)

            Divider()

            if store.routines.isEmpty {
                ContentUnavailableView("No routines yet", systemImage: "figure.walk",
                    description: Text("Add one like “Stand & stretch” or “Walk”."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.routines) { routine in
                        HStack(spacing: 10) {
                            Image(systemName: "figure.walk.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(routine.name).font(.headline)
                                Text(routine.cadenceLabel)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if routine.remind {
                                Image(systemName: "bell.fill").foregroundStyle(.secondary)
                            }
                            if routine.includeInReport {
                                Image(systemName: "doc.text").foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = routine }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(item: $editing) { routine in
            RoutineEditor(routine: routine)
        }
    }
}

private struct RoutineEditor: View {
    @State var routine: Routine
    @State private var stepHours = 1
    @State private var activeDays: Set<Int> = Set(1...7)
    @State private var startTime = Date()
    @State private var endTime = Date()
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    // Monday-first display order of calendar weekday numbers (1=Sun…7=Sat).
    private let dayOrder = [2, 3, 4, 5, 6, 7, 1]

    private var exists: Bool { store.routines.contains { $0.id == routine.id } }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name (e.g. Stand & stretch)", text: $routine.name)
                }
                Section("Cadence") {
                    Picker("Repeat", selection: $routine.cadence) {
                        Text("Once a day").tag("daily")
                        Text("Every hour").tag("hourly")
                    }
                    .pickerStyle(.segmented)

                    if routine.isHourly {
                        DatePicker("From", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("To", selection: $endTime, displayedComponents: .hourAndMinute)
                        Stepper("Every \(stepHours) hour\(stepHours == 1 ? "" : "s")",
                                value: $stepHours, in: 1...12)
                    } else {
                        DatePicker("At", selection: $startTime, displayedComponents: .hourAndMinute)
                    }
                }
                Section {
                    HStack(spacing: 6) {
                        ForEach(dayOrder, id: \.self) { wd in
                            dayToggle(wd)
                        }
                    }
                } header: {
                    Text("On these days")
                } footer: {
                    Text(activeDays.count == 7 ? "Every day." : "Only the selected days.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Remind me", isOn: $routine.remind)
                    Toggle("Include in PDF report", isOn: $routine.includeInReport)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if exists {
                    Button("Delete", role: .destructive) {
                        store.deleteRoutine(routine); dismiss()
                    }
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(routine.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || activeDays.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 460, height: 540)
        .onAppear {
            stepHours = routine.step
            activeDays = Set(routine.weekdays ?? Array(1...7))
            let cal = Calendar.current
            startTime = cal.date(bySettingHour: routine.startHour, minute: routine.sMin, second: 0, of: Date()) ?? Date()
            endTime = cal.date(bySettingHour: routine.endHour, minute: routine.eMin, second: 0, of: Date()) ?? Date()
        }
    }

    private func dayToggle(_ wd: Int) -> some View {
        let on = activeDays.contains(wd)
        let label = String(Calendar.current.shortWeekdaySymbols[wd - 1].prefix(2))
        return Button {
            if on { activeDays.remove(wd) } else { activeDays.insert(wd) }
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .frame(width: 30, height: 28)
                .background(on ? Color.accentColor : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(on ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let cal = Calendar.current
        let s = cal.dateComponents([.hour, .minute], from: startTime)
        let e = cal.dateComponents([.hour, .minute], from: endTime)
        routine.startHour = s.hour ?? 9
        routine.startMinute = s.minute ?? 0
        routine.endHour = e.hour ?? 17
        routine.endMinute = e.minute ?? 0
        // Ensure end isn't before start (compare total minutes).
        if routine.endHour * 60 + routine.eMin < routine.startHour * 60 + routine.sMin {
            routine.endHour = routine.startHour
            routine.endMinute = routine.startMinute
        }
        routine.hourStep = stepHours <= 1 ? nil : stepHours
        routine.weekdays = activeDays.count == 7 ? nil : activeDays.sorted()
        store.upsertRoutine(routine)
        dismiss()
    }
}
