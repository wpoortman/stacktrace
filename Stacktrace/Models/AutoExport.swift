import Foundation

/// Scheduled automatic PDF export. Runs on launch and writes the previous
/// period's report into the Exports folder when one is due.
@MainActor
enum AutoExport {
    static let enabledKey = "autoExportEnabled"
    static let frequencyKey = "autoExportFrequency"   // "weekly" | "monthly"
    static let weekdayKey = "autoExportWeekday"       // 1=Sun…7=Sat (weekly)
    static let hourKey = "autoExportHour"
    static let lastKey = "autoExportLast"             // TimeInterval since reference

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var frequency: String { UserDefaults.standard.string(forKey: frequencyKey) ?? "weekly" }
    static var weekday: Int { (UserDefaults.standard.object(forKey: weekdayKey) as? Int) ?? 2 }
    static var hour: Int { (UserDefaults.standard.object(forKey: hourKey) as? Int) ?? 18 }

    /// Generate the previous period's report if the scheduled time has passed
    /// since the last run.
    static func runIfDue(store: DataStore, now: Date = Date()) {
        guard isEnabled else { return }
        guard let scheduled = lastScheduledOccurrence(before: now) else { return }
        let last = UserDefaults.standard.double(forKey: lastKey)
        guard scheduled.timeIntervalSinceReferenceDate > last else { return }

        let (start, end, label) = period(endingAt: scheduled)
        guard !store.entries(from: start, to: end).isEmpty else {
            // Nothing to report; still mark as handled so we don't retry today.
            UserDefaults.standard.set(scheduled.timeIntervalSinceReferenceDate, forKey: lastKey)
            return
        }
        ReportExporter.export(store: store, from: start, to: end, baseName: label) { _ in }
        UserDefaults.standard.set(scheduled.timeIntervalSinceReferenceDate, forKey: lastKey)
    }

    /// The most recent moment the schedule should have fired, at/just before now.
    private static func lastScheduledOccurrence(before now: Date) -> Date? {
        let cal = Calendar.current
        if frequency == "monthly" {
            // 1st of month at hour.
            var comps = cal.dateComponents([.year, .month], from: now)
            comps.day = 1; comps.hour = hour; comps.minute = 0
            guard let thisMonth = cal.date(from: comps) else { return nil }
            if thisMonth <= now { return thisMonth }
            return cal.date(byAdding: .month, value: -1, to: thisMonth)
        } else {
            // Most recent matching weekday at hour.
            var comps = DateComponents(); comps.weekday = weekday; comps.hour = hour; comps.minute = 0
            return cal.nextDate(after: now, matching: comps,
                                matchingPolicy: .nextTime, direction: .backward)
        }
    }

    private static func period(endingAt scheduled: Date) -> (Date, Date, String) {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        if frequency == "monthly" {
            // Previous whole month.
            let firstThis = cal.date(from: cal.dateComponents([.year, .month], from: scheduled)) ?? scheduled
            let start = cal.date(byAdding: .month, value: -1, to: firstThis) ?? firstThis
            let end = cal.date(byAdding: .day, value: -1, to: firstThis) ?? firstThis
            return (start, end, "Work Report \(f.string(from: start)) to \(f.string(from: end)) (auto)")
        } else {
            // Previous 7 days up to the scheduled day.
            let end = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: scheduled)) ?? scheduled
            let start = cal.date(byAdding: .day, value: -6, to: end) ?? end
            return (start, end, "Work Report \(f.string(from: start)) to \(f.string(from: end)) (auto)")
        }
    }
}
