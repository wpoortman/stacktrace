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
                    Button("Change…", action: chooseFolder)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.directory])
                    }
                    Spacer()
                    if StorageLocation.isCustom {
                        Button("Reset to Default") { store.resetStorage() }
                    }
                }
            } header: {
                Text("Storage location")
            } footer: {
                Text("Your entries (data.json), its backup, and exported PDFs live here. When you change the folder, existing files are copied to the new location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose where Stacktrace should store its data and exports."
        if panel.runModal() == .OK, let url = panel.url {
            store.setStorage(to: url)
        }
    }
}
