import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Lists every exported PDF from the app's Exports folder, newest first.
/// Open, reveal in Finder, or delete.
struct ExportsView: View {
    @State private var files: [ExportFile] = []
    @State private var selection: ExportFile.ID?
    @State private var selectingExports = false
    @State private var selectedExports: Set<ExportFile.ID> = []
    @State private var zipError: String?

    var body: some View {
        Group {
            if files.isEmpty {
                ContentUnavailableView {
                    Label("No exports yet", systemImage: "tray")
                } description: {
                    Text("Generate a report and it will appear here.")
                }
            } else {
                List(selection: $selection) {
                    ForEach(files) { file in
                        ExportRow(
                            file: file,
                            selecting: selectingExports,
                            selected: selectedExports.contains(file.id),
                            onToggleSelected: { toggleSelected(file) },
                            onOpen: { open(file) },
                            onReveal: { reveal(file) },
                            onDelete: { delete(file) }
                        )
                        .tag(file.id)
                        .contextMenu {
                            Button("Open") { open(file) }
                            Button("Reveal in Finder") { reveal(file) }
                            Divider()
                            Button("Delete", role: .destructive) { delete(file) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Exports")
        .alert("Couldn't Create Zip", isPresented: Binding(
            get: { zipError != nil },
            set: { if !$0 { zipError = nil } }
        )) {
            Button("OK") { zipError = nil }
        } message: {
            Text(zipError ?? "")
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if selectingExports {
                    Button {
                        toggleSelectAll()
                    } label: {
                        Label(allExportsSelected ? "Clear Selection" : "Select All",
                              systemImage: allExportsSelected ? "checklist.unchecked" : "checklist.checked")
                    }
                }
                Button {
                    if selectingExports { zipSelectedExports() }
                    else { beginSelecting() }
                } label: {
                    Label(selectingExports ? "Download Zip" : "Select Exports",
                          systemImage: selectingExports ? "archivebox" : "checklist")
                }
                .disabled(selectingExports && selectedExports.isEmpty)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([ExportStore.directory])
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                Button { refresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private var allExportsSelected: Bool {
        !files.isEmpty && selectedExports.count == files.count
    }

    private func refresh() {
        files = ExportStore.list()
        selectedExports.formIntersection(Set(files.map(\.id)))
        if files.isEmpty {
            selectingExports = false
        }
    }

    private func beginSelecting() {
        selectingExports = true
        selectedExports.removeAll()
    }

    private func toggleSelected(_ file: ExportFile) {
        if selectedExports.contains(file.id) {
            selectedExports.remove(file.id)
        } else {
            selectedExports.insert(file.id)
        }
    }

    private func toggleSelectAll() {
        if allExportsSelected {
            selectedExports.removeAll()
        } else {
            selectedExports = Set(files.map(\.id))
        }
    }

    private func open(_ file: ExportFile) {
        NSWorkspace.shared.open(file.url)
    }

    private func reveal(_ file: ExportFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    private func delete(_ file: ExportFile) {
        ExportStore.delete(file.url)
        selectedExports.remove(file.id)
        refresh()
    }

    private func zipSelectedExports() {
        let selectedFiles = files.filter { selectedExports.contains($0.id) }
        guard !selectedFiles.isEmpty else { return }

        let panel = NSSavePanel()
        panel.title = "Save Selected Exports"
        panel.nameFieldStringValue = defaultZipName()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try ExportStore.zip(files: selectedFiles, to: url)
                selectingExports = false
                selectedExports.removeAll()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                zipError = error.localizedDescription
            }
        }
    }

    private func defaultZipName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return "Stacktrace Exports \(formatter.string(from: Date())).zip"
    }
}

private struct ExportRow: View {
    let file: ExportFile
    let selecting: Bool
    let selected: Bool
    let onToggleSelected: () -> Void
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            if selecting {
                Button(action: onToggleSelected) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(selected ? "Deselect" : "Select")
            }
            Image(systemName: "doc.richtext")
                .font(.title3)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.headline)
                Text("\(Self.dateFormatter.string(from: file.created)) · \(byteString(file.size))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selecting {
                Text(selected ? "Selected" : "Not selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Open", action: onOpen)
                    .buttonStyle(.borderedProminent)
                ShareLink(item: file.url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Share")
                Button {
                    onReveal()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Reveal in Finder")
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete")
            }
        }
        .buttonStyle(.bordered)
        .contentShape(Rectangle())
        .onTapGesture {
            if selecting { onToggleSelected() }
        }
        .padding(.vertical, 4)
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
