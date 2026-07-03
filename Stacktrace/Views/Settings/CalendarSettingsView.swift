import SwiftUI
import AppKit

/// Connect the macOS Calendar so the day view can prompt you to reflect on
/// meetings. Reads iCloud, Google, and Exchange accounts already in Calendar.
struct CalendarSettingsView: View {
    @ObservedObject private var calendar = CalendarService.shared
    @AppStorage("calendarEnabled") private var enabled = false
    @State private var requesting = false

    /// Connected = the user opted in *and* macOS has granted access.
    private var connected: Bool { enabled && calendar.authorized }

    var body: some View {
        Form {
            Section {
                Toggle("Show meetings to review", isOn: $enabled)
                    .onChange(of: enabled) { _, on in
                        if on, !calendar.authorized { connect() }
                    }

                if connected {
                    HStack {
                        Label("Calendar connected", systemImage: "checkmark.seal")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Disconnect", role: .destructive) { enabled = false }
                    }
                } else {
                    HStack {
                        Button(calendar.authorized ? "Enable" : "Connect calendar", action: connect)
                            .disabled(requesting)
                        if requesting { ProgressView().controlSize(.small) }
                    }
                }
            } header: {
                Text("Calendar")
            } footer: {
                Text("Reads your macOS Calendar (including Google, iCloud, and Exchange accounts added there). The day view then lists that day's meetings so you can record whether they happened and how they went. Granting access once is enough — Disconnect just hides meetings; it keeps the macOS permission so you can re-enable without another prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Manage access in System Settings…", action: openPrivacySettings)
            } footer: {
                Text("Revoke Stacktrace's calendar permission entirely, or re-grant it if macOS blocked access.")
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

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
