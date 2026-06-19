import SwiftUI

/// Debug-only developer options. Shown in the Settings sidebar only for local
/// (DEBUG) builds — never in release / App Store builds.
struct DeveloperSettingsView: View {
    @AppStorage(AppConfig.devURLKey) private var devURL = ""

    var body: some View {
        Form {
            Section {
                TextField("Team API base URL", text: $devURL)
                    .textFieldStyle(.roundedBorder)
                LabeledContent("Resolves to", value: AppConfig.teamBaseURL?.absoluteString ?? "Demo (offline)")
            } header: {
                Text("Team API")
            } footer: {
                Text("Point the app at a local or staging backend (e.g. http://127.0.0.1:8000). Blank uses the production URL, or the offline demo if none is set. This pane only exists in debug builds.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
