import SwiftUI

/// App-level preferences.
struct GeneralSettingsView: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, want in
                        failed = !LoginItem.set(want)
                        launchAtLogin = LoginItem.isEnabled
                    }
                if failed {
                    Text("Couldn't update the login item. Unsigned development builds may not support this.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("General")
            } footer: {
                Text("Open Stacktrace automatically when you log in to your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }
}
