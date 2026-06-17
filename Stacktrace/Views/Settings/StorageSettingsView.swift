import SwiftUI
import AppKit

/// Choose where Stacktrace keeps its data and exports. Defaults to the app's
/// Application Support folder; existing files are copied when you switch.
struct StorageSettingsView: View {
    @EnvironmentObject private var store: DataStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder") {
                    Text(store.directory.path)
                        .textSelection(.enabled)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Change…") { chooseFolder() }
                    Button("Use iCloud Drive…", action: chooseICloud)
                    Spacer()
                    if StorageLocation.isCustom {
                        Button("Reset to Default") { store.resetStorage() }
                    }
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.directory])
                }
            } header: {
                Text("Storage location")
            } footer: {
                Text("Your entries (data.json), its backup, and exported PDFs live here. When you change the folder, existing files are copied over. Pick a folder in iCloud Drive to sync across your Macs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder(startingAt: URL? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose where Stacktrace should store its data and exports."
        if let startingAt { panel.directoryURL = startingAt }
        if panel.runModal() == .OK, let url = panel.url {
            store.setStorage(to: url)
        }
    }

    /// Open the folder picker pointed at iCloud Drive so the user can pick or
    /// create a folder there — giving cross-Mac sync (sandbox-safe via bookmark).
    private func chooseICloud() {
        let icloud = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        let start = FileManager.default.fileExists(atPath: icloud.path) ? icloud : nil
        chooseFolder(startingAt: start)
    }
}
