import Foundation

/// One reported item for a single day. Plain value type, JSON-serialized.
struct ReportEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date                 // normalized to start-of-day
    var title: String = ""
    var detail: String = ""
    var wentWell: String = ""
    var wentBad: String = ""
    var tags: [String] = []
    /// How the work went, 1 (rough) … 5 (great). Optional = not yet rated.
    var mood: Int?
    /// nil = full entry. "win" or "fail" = lightweight quick item (just `detail`).
    var quickKind: String?
    /// Set for a logged exercise activity (e.g. "Walk"), with `durationMinutes`.
    var exercise: String?
    var durationMinutes: Int?
    var createdAt: Date = Date()

    var isQuick: Bool { quickKind != nil }
    var isExercise: Bool { exercise != nil }

    /// A one-tap mood check-in: carries only a mood, no text or tags.
    var isCheckin: Bool {
        quickKind == nil && mood != nil
            && title.isEmpty && detail.isEmpty
            && wentWell.isEmpty && wentBad.isEmpty && tags.isEmpty
    }

    init(date: Date) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.createdAt = Date()
    }

    var isEmpty: Bool {
        title.isEmpty && detail.isEmpty && wentWell.isEmpty
            && wentBad.isEmpty && tags.isEmpty
    }
}

/// An overall 1–10 rating of how a whole day went (not per-entry mood).
struct DayRating: Identifiable, Codable, Equatable {
    var id = UUID()
    var day: Date    // start-of-day
    var score: Int   // 1...10
    var at: Date

    init(day: Date, score: Int) {
        self.id = UUID()
        self.day = Calendar.current.startOfDay(for: day)
        self.score = min(10, max(1, score))
        self.at = Date()
    }
}

/// On-disk shape of the data file. Decoding tolerates older files that lack
/// newer keys so upgrades never wipe data.
private struct StoreFile: Codable {
    var entries: [ReportEntry] = []
    var tags: [String] = []
    var routines: [Routine] = []
    var routineLogs: [RoutineLog] = []
    var dayRatings: [DayRating] = []

    init(entries: [ReportEntry], tags: [String],
         routines: [Routine], routineLogs: [RoutineLog],
         dayRatings: [DayRating]) {
        self.entries = entries
        self.tags = tags
        self.routines = routines
        self.routineLogs = routineLogs
        self.dayRatings = dayRatings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([ReportEntry].self, forKey: .entries) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        routines = try c.decodeIfPresent([Routine].self, forKey: .routines) ?? []
        routineLogs = try c.decodeIfPresent([RoutineLog].self, forKey: .routineLogs) ?? []
        dayRatings = try c.decodeIfPresent([DayRating].self, forKey: .dayRatings) ?? []
    }
}

/// File-backed store. All entries and the tag catalog live in a single JSON
/// file inside the app's own Application Support folder. Every mutation writes
/// atomically and keeps a `.bak` copy of the previous version, so data
/// survives app rebuilds and can only be lost by deleting the files.
@MainActor
final class DataStore: ObservableObject {
    @Published private(set) var entries: [ReportEntry] = []
    @Published private(set) var tags: [String] = []
    @Published private(set) var routines: [Routine] = []
    @Published private(set) var routineLogs: [RoutineLog] = []
    @Published private(set) var dayRatings: [DayRating] = []
    /// Published so the Settings UI updates when the folder changes.
    @Published private(set) var directory: URL = StorageLocation.current

    private var fileURL: URL { directory.appendingPathComponent("data.json") }
    private var backupURL: URL { directory.appendingPathComponent("data.json.bak") }

    init() {
        StorageLocation.activate()
        directory = StorageLocation.current
        migrateLegacyIfNeeded()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    /// One-time move of the old "Report" folder to the default "Stacktrace"
    /// folder, only when using the default location.
    private func migrateLegacyIfNeeded() {
        guard directory == StorageLocation.defaultBase else { return }
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let legacy = base.appendingPathComponent("Report", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path), fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: directory)
        }
    }

    // MARK: - Storage location

    /// Switch to a user-chosen folder (security-scoped, already accessible).
    func setStorage(to url: URL) {
        try? StorageLocation.saveBookmark(for: url)
        relocate(to: url)
    }

    /// Revert to the default Application Support folder.
    func resetStorage() {
        StorageLocation.clearBookmark()
        relocate(to: StorageLocation.defaultBase)
    }

    /// Copy existing data + exports into `newBase`, then read from there.
    private func relocate(to newBase: URL) {
        let fm = FileManager.default
        let old = directory
        try? fm.createDirectory(at: newBase, withIntermediateDirectories: true)

        if old.standardizedFileURL != newBase.standardizedFileURL {
            for name in ["data.json", "data.json.bak"] {
                let src = old.appendingPathComponent(name)
                let dst = newBase.appendingPathComponent(name)
                if fm.fileExists(atPath: src.path) {
                    try? fm.removeItem(at: dst)
                    try? fm.copyItem(at: src, to: dst)
                }
            }
            let srcEx = old.appendingPathComponent("Exports")
            let dstEx = newBase.appendingPathComponent("Exports")
            if fm.fileExists(atPath: srcEx.path),
               let items = try? fm.contentsOfDirectory(at: srcEx, includingPropertiesForKeys: nil) {
                try? fm.createDirectory(at: dstEx, withIntermediateDirectories: true)
                for item in items {
                    let dst = dstEx.appendingPathComponent(item.lastPathComponent)
                    try? fm.removeItem(at: dst)
                    try? fm.copyItem(at: item, to: dst)
                }
            }
        }

        StorageLocation.current = newBase
        directory = newBase
        load()
    }

    // MARK: - Loading / saving

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Try the main file, then fall back to the backup if it's corrupt.
        for url in [fileURL, backupURL] {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let file = try? decoder.decode(StoreFile.self, from: data) {
                entries = file.entries
                tags = file.tags
                routines = file.routines
                routineLogs = file.routineLogs
                dayRatings = file.dayRatings
                return
            }
        }
        entries = []
        tags = []
        routines = []
        routineLogs = []
        dayRatings = []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let file = StoreFile(entries: entries, tags: tags,
                             routines: routines, routineLogs: routineLogs,
                             dayRatings: dayRatings)
        guard let data = try? encoder.encode(file) else { return }

        // Roll the current file to .bak before overwriting.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Entry queries

    func entries(on day: Date) -> [ReportEntry] {
        let start = Calendar.current.startOfDay(for: day)
        return entries
            .filter { Calendar.current.isDate($0.date, inSameDayAs: start) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func entries(from start: Date, to end: Date) -> [ReportEntry] {
        let lo = Calendar.current.startOfDay(for: start)
        let hi = Calendar.current.startOfDay(for: end)
        return entries
            .filter { $0.date >= lo && $0.date <= hi }
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }

    var daysWithEntries: Set<Date> {
        Set(entries.map { $0.date })
    }

    // MARK: - Entry mutations

    func upsert(_ entry: ReportEntry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[i] = entry
        } else {
            entries.append(entry)
        }
        save()
    }

    func delete(_ entry: ReportEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// Quick win / setback item — just a line of text, no full form. Wins read
    /// positive (green), setbacks negative (orange) in the graph.
    func addQuick(_ text: String, kind: String, on day: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var e = ReportEntry(date: day)
        e.quickKind = kind
        e.detail = trimmed
        e.mood = (kind == "win") ? 5 : 2
        upsert(e)
    }

    /// One-tap daily check-in: an entry carrying only a mood rating.
    func addCheckin(mood: Int, on day: Date = Date()) {
        var e = ReportEntry(date: day)
        e.mood = mood
        upsert(e)
    }

    /// Log an exercise activity (name + minutes).
    func addExercise(_ name: String, minutes: Int, on day: Date = Date()) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var e = ReportEntry(date: day)
        e.exercise = trimmed
        e.durationMinutes = max(1, minutes)
        upsert(e)
    }

    /// Total logged exercise minutes in a date range.
    func activeMinutes(from start: Date, to end: Date) -> Int {
        entries(from: start, to: end).compactMap { $0.durationMinutes }.reduce(0, +)
    }

    func hasEntries(on day: Date) -> Bool {
        let start = Calendar.current.startOfDay(for: day)
        return entries.contains { Calendar.current.isDate($0.date, inSameDayAs: start) }
    }

    // MARK: - Tag catalog

    /// Add to the catalog if not present (case-insensitive). Returns canonical name.
    @discardableResult
    func addTag(_ rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if let match = tags.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        tags.append(name)
        tags.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        save()
        return name
    }

    func renameTag(_ old: String, to rawNew: String) {
        let new = rawNew.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != old, let i = tags.firstIndex(of: old) else { return }
        tags[i] = new
        tags.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        for j in entries.indices where entries[j].tags.contains(old) {
            entries[j].tags = entries[j].tags.map { $0 == old ? new : $0 }
        }
        save()
    }

    func deleteTag(_ name: String) {
        tags.removeAll { $0 == name }
        for j in entries.indices where entries[j].tags.contains(name) {
            entries[j].tags.removeAll { $0 == name }
        }
        save()
    }

    // MARK: - Routines

    func upsertRoutine(_ routine: Routine) {
        if let i = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[i] = routine
        } else {
            routines.append(routine)
        }
        save()
        NotificationManager.refreshRoutines(routines)
    }

    func deleteRoutine(_ routine: Routine) {
        routines.removeAll { $0.id == routine.id }
        routineLogs.removeAll { $0.routineID == routine.id }
        save()
        NotificationManager.refreshRoutines(routines)
    }

    /// Times a routine was completed on a given day.
    func completions(_ routine: Routine, on day: Date) -> Int {
        let start = Calendar.current.startOfDay(for: day)
        return routineLogs.filter {
            $0.routineID == routine.id && Calendar.current.isDate($0.day, inSameDayAs: start)
        }.count
    }

    func isDone(_ routine: Routine, on day: Date) -> Bool {
        completions(routine, on: day) >= routine.dailyTarget
    }

    func logCompletion(_ routine: Routine, on day: Date = Date()) {
        routineLogs.append(RoutineLog(routineID: routine.id, day: day))
        save()
    }

    /// Remove the most recent completion for a routine on a day (undo).
    func undoCompletion(_ routine: Routine, on day: Date = Date()) {
        let start = Calendar.current.startOfDay(for: day)
        if let idx = routineLogs.lastIndex(where: {
            $0.routineID == routine.id && Calendar.current.isDate($0.day, inSameDayAs: start)
        }) {
            routineLogs.remove(at: idx)
            save()
        }
    }

    // MARK: - Day rating (overall 1–10)

    func dayRating(for day: Date) -> Int? {
        let start = Calendar.current.startOfDay(for: day)
        return dayRatings.first { Calendar.current.isDate($0.day, inSameDayAs: start) }?.score
    }

    func setDayRating(_ score: Int, for day: Date) {
        let start = Calendar.current.startOfDay(for: day)
        dayRatings.removeAll { Calendar.current.isDate($0.day, inSameDayAs: start) }
        dayRatings.append(DayRating(day: start, score: score))
        save()
    }

    var averageDayRating: Double? {
        guard !dayRatings.isEmpty else { return nil }
        return Double(dayRatings.map(\.score).reduce(0, +)) / Double(dayRatings.count)
    }

    /// The day the app should prompt to rate: the oldest recent logged day
    /// missing a rating, or today once the end-of-day hour has passed.
    func dayNeedingRating(asOf now: Date = Date(), endOfDayHour: Int = 18) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        // Catch up on the last 3 days you logged but didn't rate (oldest first).
        for offset in stride(from: 3, through: 1, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            if hasEntries(on: day), dayRating(for: day) == nil { return day }
        }
        // Today, once it's wrapping up.
        let hour = cal.component(.hour, from: now)
        if hour >= endOfDayHour, hasEntries(on: today), dayRating(for: today) == nil {
            return today
        }
        return nil
    }

    // MARK: - Dashboard stats

    struct DayStat: Equatable {
        let count: Int
        let avgMood: Double?   // nil = logged but unrated
    }

    /// Per-day aggregate keyed by start-of-day.
    func dayStats() -> [Date: DayStat] {
        var byDay: [Date: [ReportEntry]] = [:]
        for e in entries { byDay[e.date, default: []].append(e) }
        var out: [Date: DayStat] = [:]
        for (day, list) in byDay {
            let moods = list.compactMap { $0.mood }
            let avg = moods.isEmpty ? nil : Double(moods.reduce(0, +)) / Double(moods.count)
            out[day] = DayStat(count: list.count, avgMood: avg)
        }
        return out
    }

    var totalEntries: Int { entries.count }

    var averageMood: Double? {
        let m = entries.compactMap { $0.mood }
        return m.isEmpty ? nil : Double(m.reduce(0, +)) / Double(m.count)
    }

    func entriesCount(from start: Date, to end: Date) -> Int {
        entries(from: start, to: end).count
    }

    /// Consecutive days with at least one entry, counting back from today
    /// (or yesterday if today is still empty).
    func currentStreak(asOf today: Date = Date()) -> Int {
        let cal = Calendar.current
        let days = Set(entries.map { $0.date })
        var day = cal.startOfDay(for: today)
        if !days.contains(day) {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    func longestStreak() -> Int {
        let cal = Calendar.current
        let unique = Array(Set(entries.map { $0.date })).sorted()
        guard !unique.isEmpty else { return 0 }
        var best = 1, cur = 1
        for i in 1..<unique.count {
            if cal.date(byAdding: .day, value: 1, to: unique[i - 1]) == unique[i] {
                cur += 1; best = max(best, cur)
            } else {
                cur = 1
            }
        }
        return best
    }
}
