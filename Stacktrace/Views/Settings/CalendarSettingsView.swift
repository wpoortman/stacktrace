import SwiftUI

/// Connect the macOS Calendar so the day view can prompt you to reflect on
/// meetings. Reads iCloud, Google, and Exchange accounts already in Calendar.
struct CalendarSettingsView: View {
    @ObservedObject private var calendar = CalendarService.shared
    @AppStorage("calendarEnabled") private var enabled = false
    @State private var requesting = false

    var body: some View {
        Form {
            Section {
                Toggle("Show meetings to review", isOn: $enabled)
                    .onChange(of: enabled) { _, on in
                        if on, !calendar.authorized { connect() }
                    }

                HStack {
                    if calendar.authorized {
                        Label("Calendar connected", systemImage: "checkmark.seal")
                            .foregroundStyle(.green)
                    } else {
                        Button("Connect calendar", action: connect)
                            .disabled(requesting)
                        if requesting { ProgressView().controlSize(.small) }
                    }
                }
            } header: {
                Text("Calendar")
            } footer: {
                Text("Reads your macOS Calendar (including Google, iCloud, and Exchange accounts added there). The day view then lists that day's meetings so you can record whether they happened and how they went. If access is blocked, enable Calendars for Stacktrace in System Settings → Privacy & Security.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { calendar.refreshAuthState() }
    }

    private func connect() {
        requesting = true
        Task {
            let granted = await calendar.requestAccess()
            requesting = false
            if granted { enabled = true }
        }
    }
}
