import Foundation

/// One exported PDF on disk.
struct ExportFile: Identifiable, Equatable {
    let url: URL
    let created: Date
    let size: Int64
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// Manages the single app-owned folder where all report PDFs live, inside the
/// sandbox container's Application Support. Keeping every export in one place
/// means no Save dialog and an easy in-app list.
enum ExportStore {
    static var directory: URL {
        let dir = StorageLocation.current.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A non-colliding URL for `baseName`. Appends " (2)", " (3)", … when a
    /// file with the same name already exists, so re-exporting a similar
    /// report never overwrites an earlier one.
    static func uniqueURL(baseName: String, ext: String = "pdf") -> URL {
        let dir = directory
        var candidate = dir.appendingPathComponent("\(baseName).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(baseName) (\(n)).\(ext)")
            n += 1
        }
        return candidate
    }

    static func list() -> [ExportFile] {
        let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles])) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return ExportFile(
                    url: url,
                    created: values?.creationDate ?? .distantPast,
                    size: Int64(values?.fileSize ?? 0)
                )
            }
            .sorted { $0.created > $1.created }
    }

    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
