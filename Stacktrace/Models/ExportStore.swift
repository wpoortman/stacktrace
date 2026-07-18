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

    static func zip(files: [ExportFile], to destination: URL) throws {
        try zip(urls: files.map(\.url), to: destination)
    }

    static func zip(urls: [URL], to destination: URL) throws {
        let archive = try ZipArchive(urls: urls)
        try archive.data.write(to: destination, options: .atomic)
    }
}

private struct ZipArchive {
    var data = Data()

    private struct CentralDirectoryEntry {
        var name: String
        var crc: UInt32
        var size: UInt32
        var localHeaderOffset: UInt32
        var modTime: UInt16
        var modDate: UInt16
    }

    init(urls: [URL]) throws {
        var entries: [CentralDirectoryEntry] = []

        for url in urls {
            let fileData = try Data(contentsOf: url)
            let name = url.lastPathComponent
            let nameData = Data(name.utf8)
            let crc = Self.crc32(fileData)
            let size = UInt32(fileData.count)
            let offset = UInt32(data.count)
            let stamp = Self.dosTimestamp(for: url)

            data.appendUInt32LE(0x04034b50)
            data.appendUInt16LE(20)
            data.appendUInt16LE(0x0800)
            data.appendUInt16LE(0)
            data.appendUInt16LE(stamp.time)
            data.appendUInt16LE(stamp.date)
            data.appendUInt32LE(crc)
            data.appendUInt32LE(size)
            data.appendUInt32LE(size)
            data.appendUInt16LE(UInt16(nameData.count))
            data.appendUInt16LE(0)
            data.append(nameData)
            data.append(fileData)

            entries.append(CentralDirectoryEntry(name: name, crc: crc, size: size,
                                                 localHeaderOffset: offset,
                                                 modTime: stamp.time, modDate: stamp.date))
        }

        let centralStart = UInt32(data.count)
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            data.appendUInt32LE(0x02014b50)
            data.appendUInt16LE(20)
            data.appendUInt16LE(20)
            data.appendUInt16LE(0x0800)
            data.appendUInt16LE(0)
            data.appendUInt16LE(entry.modTime)
            data.appendUInt16LE(entry.modDate)
            data.appendUInt32LE(entry.crc)
            data.appendUInt32LE(entry.size)
            data.appendUInt32LE(entry.size)
            data.appendUInt16LE(UInt16(nameData.count))
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt32LE(0)
            data.appendUInt32LE(entry.localHeaderOffset)
            data.append(nameData)
        }

        let centralSize = UInt32(data.count) - centralStart
        data.appendUInt32LE(0x06054b50)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(UInt16(entries.count))
        data.appendUInt16LE(UInt16(entries.count))
        data.appendUInt32LE(centralSize)
        data.appendUInt32LE(centralStart)
        data.appendUInt16LE(0)
    }

    private static func dosTimestamp(for url: URL) -> (time: UInt16, date: UInt16) {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let date = values?.contentModificationDate ?? Date()
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, min(2107, components.year ?? 1980))
        let month = max(1, min(12, components.month ?? 1))
        let day = max(1, min(31, components.day ?? 1))
        let hour = max(0, min(23, components.hour ?? 0))
        let minute = max(0, min(59, components.minute ?? 0))
        let second = max(0, min(59, components.second ?? 0))
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = 0 &- (crc & 1)
                crc = (crc >> 1) ^ (0xedb88320 & mask)
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
