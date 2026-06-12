import SwiftUI

/// Daily reminder preferences. Toggling or changing the time reschedules the
/// local notification.
struct RemindersSettingsView: View {
    @AppStorage(NotificationManager.enabledKey) private var enabled = false
    @AppStorage(NotificationManager.hourKey) private var hour = 17
    @AppStorage(NotificationManager.minuteKey) private var minute = 0

    /// Bridges the hour/minute defaults to a single Date for the picker.
    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents(); c.hour = hour; c.minute = minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newValue in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                hour = c.hour ?? 17
                minute = c.minute ?? 0
                NotificationManager.refresh()
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Daily reminder", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in NotificationManager.refresh() }
                if enabled {
                    DatePicker("Remind me at", selection: timeBinding,
                               displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("A gentle nudge each day to log what you did. macOS will ask for notification permission the first time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
