import SwiftUI

/// Choose which weekdays appear in the sidebar "this week" list. Deselect days
/// you never work (e.g. Wednesday); add weekend days if you do.
struct DaysSettingsView: View {
    @AppStorage(WorkdayPreferences.key) private var mask = WorkdayPreferences.defaultMask

    var body: some View {
        Form {
            Section {
                ForEach(Weekday.displayOrder) { day in
                    Toggle(day.name, isOn: binding(for: day))
                }
            } header: {
                Text("Days shown in the week list")
            } footer: {
                Text("Unchecked days are hidden from the sidebar. You can still log on any day via Custom Date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for day: Weekday) -> Binding<Bool> {
        Binding(
            get: { WorkdayPreferences.contains(mask, day) },
            set: { _ in mask = WorkdayPreferences.toggled(mask, day) }
        )
    }
}
