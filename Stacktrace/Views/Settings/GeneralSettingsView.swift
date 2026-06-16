import SwiftUI
import AppKit

/// App-level preferences.
struct GeneralSettingsView: View {
    @EnvironmentObject private var store: DataStore
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var failed = false
    @State private var backupNote: String?

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

            Section {
                Button("Back Up…", action: backUp)
                Button("Restore…", action: restore)
                if let backupNote {
                    Text(backupNote).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Back up everything — entries, routines, ratings, settings, and exported PDFs — into one file. Restore it on another Mac to pick up where you left off. (Your OpenAI key stays in the Keychain and isn't included; re-enter it after restoring.)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    private func backUp() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Stacktrace Backup \(f.string(from: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.makeBackup().write(to: url, options: .atomic)
            backupNote = "Backed up to \(url.lastPathComponent)."
        } catch {
            backupNote = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func restore() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.json]
        open.allowsMultipleSelection = false
        guard open.runModal() == .OK, let url = open.url else { return }

        let alert = NSAlert()
        alert.messageText = "Replace current data?"
        alert.informativeText = "Restoring overwrites your current entries, settings, and exports with the contents of this backup."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let data = try Data(contentsOf: url)
            try store.restore(from: data)
            backupNote = "Restored from \(url.lastPathComponent)."
        } catch {
            backupNote = "Restore failed: \(error.localizedDescription)"
        }
    }
}
