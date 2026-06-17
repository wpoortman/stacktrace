import SwiftUI
import AppKit

/// Lists every exported PDF from the app's Exports folder, newest first.
/// Open, reveal in Finder, or delete.
struct ExportsView: View {
    @State private var files: [ExportFile] = []
    @State private var selection: ExportFile.ID?

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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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

    private func refresh() {
        files = ExportStore.list()
    }

    private func open(_ file: ExportFile) {
        NSWorkspace.shared.open(file.url)
    }

    private func reveal(_ file: ExportFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    private func delete(_ file: ExportFile) {
        ExportStore.delete(file.url)
        refresh()
    }
}

private struct ExportRow: View {
    let file: ExportFile
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
        .buttonStyle(.bordered)
        .padding(.vertical, 4)
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
