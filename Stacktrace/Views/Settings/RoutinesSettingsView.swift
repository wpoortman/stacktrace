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
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

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
                        Stepper("From \(routine.startHour):00", value: $routine.startHour, in: 0...23)
                        Stepper("To \(routine.endHour):00", value: $routine.endHour, in: 0...23)
                    } else {
                        Stepper("At \(routine.startHour):00", value: $routine.startHour, in: 0...23)
                    }
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
                Button("Save") {
                    if routine.endHour < routine.startHour { routine.endHour = routine.startHour }
                    store.upsertRoutine(routine)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(routine.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 420, height: 460)
    }
}
