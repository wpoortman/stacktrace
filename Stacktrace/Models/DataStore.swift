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
    /// nil = full entry. "win" / "fail" / "note" = lightweight quick item
    /// (just `detail`, plus optional `mood`). "note" is neutral — no win/loss framing.
    var quickKind: String?
    /// Optional emoji icon chosen for a quick "note" (renders in-app and in the PDF).
    var icon: String?
    /// Set for a logged exercise activity (e.g. "Walk"), with `durationMinutes`.
    var exercise: String?
    var durationMinutes: Int?
    /// Manual ordering within a day (set when the user drags to reorder).
    /// nil falls back to creation time.
    var sortOrder: Double?
    /// Set for a meeting reflection sourced from the calendar.
    var eventID: String?
    var happened: Bool?
    /// Optional link to a Project.
    var projectID: UUID?
    var createdAt: Date = Date()

    var isQuick: Bool { quickKind != nil }
    var isExercise: Bool { exercise != nil }
    var isMeeting: Bool { eventID != nil }

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

/// A project entries can be grouped under for project-specific reports.
struct Project: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var details: String

    init(name: String, details: String = "") {
        self.id = UUID()
        self.name = name
        self.details = details
    }
}

/// A holiday / time-off period during which the app stops nudging.
struct HolidayPeriod: Identifiable, Codable, Equatable {
    var id = UUID()
    var start: Date    // start-of-day
    var end: Date      // start-of-day, inclusive

    init(start: Date, end: Date) {
        self.id = UUID()
        let s = Calendar.current.startOfDay(for: start)
        let e = Calendar.current.startOfDay(for: end)
        self.start = s
        self.end = max(s, e)
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
    var holidays: [HolidayPeriod] = []
    var projects: [Project] = []

    init(entries: [ReportEntry], tags: [String],
         routines: [Routine], routineLogs: [RoutineLog],
         dayRatings: [DayRating], holidays: [HolidayPeriod], projects: [Project]) {
        self.entries = entries
        self.tags = tags
        self.routines = routines
        self.routineLogs = routineLogs
        self.dayRatings = dayRatings
        self.holidays = holidays
        self.projects = projects
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([ReportEntry].self, forKey: .entries) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        routines = try c.decodeIfPresent([Routine].self, forKey: .routines) ?? []
        routineLogs = try c.decodeIfPresent([RoutineLog].self, forKey: .routineLogs) ?? []
        dayRatings = try c.decodeIfPresent([DayRating].self, forKey: .dayRatings) ?? []
        holidays = try c.decodeIfPresent([HolidayPeriod].self, forKey: .holidays) ?? []
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
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
    @Published private(set) var holidays: [HolidayPeriod] = []
    @Published private(set) var projects: [Project] = []
    /// Published so the Settings UI updates when the folder changes.
    @Published private(set) var directory: URL = StorageLocation.current

    private var fileURL: URL { directory.appendingPathComponent("data.json") }
    private var backupURL: URL { directory.appendingPathComponent("data.json.bak") }

    private var watcher: FileWatcher?

    init() {
        StorageLocation.activate()
        directory = StorageLocation.current
        migrateLegacyIfNeeded()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
        // Pick up changes written by external tools (the MCP server) live.
        watcher = FileWatcher(url: fileURL) { [weak self] in self?.reloadIfChanged() }
    }

    /// Test-only: use an isolated directory, skipping bookmarks and migration.
    init(directoryOverride dir: URL) {
        StorageLocation.current = dir
        directory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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
                holidays = file.holidays
                projects = file.projects
                return
            }
        }
        entries = []
        tags = []
        routines = []
        routineLogs = []
        dayRatings = []
        holidays = []
        projects = []
    }

    /// Re-read the file if its contents differ from what's in memory (used by
    /// the file watcher when an external tool writes the store).
    private func reloadIfChanged() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? decoder.decode(StoreFile.self, from: data) else { return }
        guard file.entries != entries || file.tags != tags || file.routines != routines
            || file.routineLogs != routineLogs || file.dayRatings != dayRatings
            || file.holidays != holidays else { return }
        entries = file.entries
        tags = file.tags
        routines = file.routines
        routineLogs = file.routineLogs
        dayRatings = file.dayRatings
        holidays = file.holidays
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let file = StoreFile(entries: entries, tags: tags,
                             routines: routines, routineLogs: routineLogs,
                             dayRatings: dayRatings, holidays: holidays, projects: projects)
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
            .sorted { orderKey($0) < orderKey($1) }
    }

    private func orderKey(_ e: ReportEntry) -> Double {
        e.sortOrder ?? e.createdAt.timeIntervalSinceReferenceDate
    }

    /// Reorder the entries of a day after a drag, persisting the new order.
    func moveEntries(on day: Date, from source: IndexSet, to destination: Int) {
        var dayEntries = entries(on: day)
        dayEntries.move(fromOffsets: source, toOffset: destination)
        for (i, e) in dayEntries.enumerated() {
            if let idx = entries.firstIndex(where: { $0.id == e.id }) {
                entries[idx].sortOrder = Double(i)
            }
        }
        save()
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

    /// Quick win / setback / note item — just a line of text, no full form.
    /// Wins read positive (green), setbacks negative (orange) in the graph.
    /// A "note" is neutral: it carries `mood` only if the user set one.
    func addQuick(_ text: String, kind: String, mood: Int? = nil, icon: String? = nil,
                  on day: Date = Date(), projectID: UUID? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var e = ReportEntry(date: day)
        e.quickKind = kind
        e.detail = trimmed
        switch kind {
        case "win": e.mood = mood ?? 5
        case "fail": e.mood = mood ?? 2
        default:
            e.mood = mood   // "note" — neutral; only what the user chose
            e.icon = icon
        }
        e.projectID = projectID
        upsert(e)
    }

    /// One-tap daily check-in: an entry carrying only a mood rating.
    func addCheckin(mood: Int, on day: Date = Date()) {
        var e = ReportEntry(date: day)
        e.mood = mood
        upsert(e)
    }

    /// Log an exercise activity (name + minutes).
    func addExercise(_ name: String, minutes: Int, mood: Int? = nil,
                     on day: Date = Date(), projectID: UUID? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var e = ReportEntry(date: day)
        e.exercise = trimmed
        e.durationMinutes = max(1, minutes)
        e.mood = mood
        e.projectID = projectID
        upsert(e)
    }

    /// Total logged exercise minutes in a date range.
    func activeMinutes(from start: Date, to end: Date) -> Int {
        entries(from: start, to: end).compactMap { $0.durationMinutes }.reduce(0, +)
    }

    /// Log a meeting reflection sourced from the calendar.
    func addMeeting(eventID: String, title: String, happened: Bool,
                    wentWell: String, wentBad: String, mood: Int?, on day: Date) {
        var e = ReportEntry(date: day)
        e.eventID = eventID
        e.title = title
        e.happened = happened
        e.wentWell = wentWell
        e.wentBad = wentBad
        e.mood = mood
        upsert(e)
    }

    /// Calendar event IDs already reflected on for a day (to avoid re-prompting).
    func loggedMeetingIDs(on day: Date) -> Set<String> {
        Set(entries(on: day).compactMap { $0.eventID })
    }

    // MARK: - Backup / restore

    private struct BackupFile: Codable { var name: String; var base64: String }
    private struct BackupBundle: Codable {
        var version = 1
        var data: String              // data.json contents
        var settingsPlist: String     // base64 plist of app preferences
        var exports: [BackupFile]
    }

    private static let backupSettingsKeys = [
        "reminderEnabled", "reminderHour", "reminderMinute", "endOfDayHour",
        "calendarEnabled", "selectedWeekdays", "aiProvider", "openAIModel",
        "openAIKeyPresent", "anthropicAIKeyPresent", "googleAIKeyPresent",
        "lastCelebratedStreak",
    ]

    private func encodedStoreData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let file = StoreFile(entries: entries, tags: tags, routines: routines,
                             routineLogs: routineLogs, dayRatings: dayRatings,
                             holidays: holidays, projects: projects)
        return (try? encoder.encode(file)) ?? Data()
    }

    /// Build a single backup file containing entries, settings, and exports.
    func makeBackup() throws -> Data {
        let dataStr = String(data: encodedStoreData(), encoding: .utf8) ?? "{}"

        var settings: [String: Any] = [:]
        for key in Self.backupSettingsKeys {
            if let v = UserDefaults.standard.object(forKey: key) { settings[key] = v }
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)

        let exports = ExportStore.list().map { file -> BackupFile in
            let bytes = (try? Data(contentsOf: file.url)) ?? Data()
            return BackupFile(name: file.url.lastPathComponent, base64: bytes.base64EncodedString())
        }

        let bundle = BackupBundle(data: dataStr,
                                  settingsPlist: plist.base64EncodedString(),
                                  exports: exports)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        return try encoder.encode(bundle)
    }

    /// Replace current entries, settings, and exports from a backup file.
    func restore(from data: Data) throws {
        let bundle = try JSONDecoder().decode(BackupBundle.self, from: data)

        if let d = bundle.data.data(using: .utf8) {
            try d.write(to: fileURL, options: .atomic)
        }
        if let sd = Data(base64Encoded: bundle.settingsPlist),
           let dict = try PropertyListSerialization.propertyList(from: sd, options: [], format: nil) as? [String: Any] {
            for (k, v) in dict { UserDefaults.standard.set(v, forKey: k) }
        }
        let dir = ExportStore.directory
        for file in bundle.exports {
            if let bytes = Data(base64Encoded: file.base64) {
                try? bytes.write(to: dir.appendingPathComponent(file.name))
            }
        }
        load()
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
        guard !new.isEmpty, new != old else { return }
        if let i = tags.firstIndex(of: old) {
            tags[i] = new
            tags.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
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
        // Reminder timers are rebuilt by the UI observing `routines`.
    }

    func deleteRoutine(_ routine: Routine) {
        routines.removeAll { $0.id == routine.id }
        routineLogs.removeAll { $0.routineID == routine.id }
        save()
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

    // MARK: - Holidays

    func addHoliday(start: Date, end: Date) {
        holidays.append(HolidayPeriod(start: start, end: end))
        holidays.sort { $0.start < $1.start }
        save()
    }

    func deleteHoliday(_ holiday: HolidayPeriod) {
        holidays.removeAll { $0.id == holiday.id }
        save()
    }

    func isOnHoliday(_ date: Date = Date()) -> Bool {
        currentHoliday(on: date) != nil
    }

    func currentHoliday(on date: Date = Date()) -> HolidayPeriod? {
        let d = Calendar.current.startOfDay(for: date)
        return holidays.first { $0.start <= d && d <= $0.end }
    }

    // MARK: - Projects

    func upsertProject(_ project: Project) {
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i] = project
        } else {
            projects.append(project)
        }
        save()
    }

    func deleteProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        for j in entries.indices where entries[j].projectID == project.id {
            entries[j].projectID = nil
        }
        save()
    }

    func projectName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return projects.first { $0.id == id }?.name
    }

    func entries(forProject id: UUID, from start: Date, to end: Date) -> [ReportEntry] {
        entries(from: start, to: end).filter { $0.projectID == id }
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
