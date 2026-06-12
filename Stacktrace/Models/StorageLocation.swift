import Foundation

/// Resolves the base folder where Stacktrace keeps `data.json`, its backup, and
/// the `Exports/` directory. Defaults to the app's Application Support folder;
/// the user can pick a custom folder in Settings, persisted as a
/// security-scoped bookmark so access survives relaunch (sandbox-safe).
enum StorageLocation {
    private static let bookmarkKey = "storageFolderBookmark"

    /// Default: ~/Library/Application Support/Stacktrace
    static var defaultBase: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Stacktrace", isDirectory: true)
    }

    /// The active base directory. Set once at launch via `activate()`.
    static var current: URL = defaultBase

    static var isCustom: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Resolve any saved custom folder and begin security-scoped access.
    /// Call once, before any file access.
    static func activate() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            current = defaultBase
            return
        }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale) {
            _ = url.startAccessingSecurityScopedResource()
            current = url
            if stale { try? saveBookmark(for: url) }
        } else {
            // Bookmark no longer resolvable — fall back, keep data safe.
            current = defaultBase
        }
    }

    static func saveBookmark(for url: URL) throws {
        let data = try url.bookmarkData(options: [.withSecurityScope],
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    static func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }
}
