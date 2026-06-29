import Foundation

/// Builds a Markdown version of a report — for pasting into Slack, standups,
/// or email. Mirrors the PDF layout.
enum ReportMarkdownBuilder {
    static func markdown(entries: [ReportEntry],
                         routines: [Routine] = [],
                         routineLogs: [RoutineLog] = [],
                         dayRatings: [DayRating] = [],
                         holidays: [HolidayPeriod] = [],
                         projectNames: [UUID: String] = [:],
                         from start: Date, to end: Date) -> String {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: entries) { cal.startOfDay(for: $0.date) }
        let logsByDay = Dictionary(grouping: routineLogs) { cal.startOfDay(for: $0.day) }
        let routineName = Dictionary(routines.map { ($0.id, $0.name) }) { a, _ in a }
        let ratingByDay = Dictionary(dayRatings.map { (cal.startOfDay(for: $0.day), $0.score) }) { a, _ in a }
        let holidayDays = ReportHTMLBuilder.holidayDays(holidays, from: start, to: end, cal: cal)
        let days = Set(grouped.keys).union(logsByDay.keys).union(holidayDays).sorted()

        let range = "\(DateFormat.short.string(from: start)) – \(DateFormat.short.string(from: end))"
        var out = "# Work Report\n\(range) · \(entries.count) \(entries.count == 1 ? "entry" : "entries")\n"

        if days.isEmpty {
            out += "\n_No entries logged for this period._\n"
            return out
        }

        let moodEmoji = ["🌧️", "☁️", "⛅️", "☀️", "✨"]
        for day in days {
            out += "\n## \(DateFormat.dayHeader.string(from: day))\n"
            if holidayDays.contains(day) {
                out += "_🏖️ On holiday — time off_\n"
            }
            if let score = ratingByDay[day] {
                out += "_Overall day score: \(score)/10_\n"
            }
            for entry in (grouped[day] ?? []).sorted(by: { $0.createdAt < $1.createdAt }) {
                let proj = entry.projectID.flatMap { projectNames[$0] }.map { " · \($0)" } ?? ""
                if entry.isExercise {
                    let mins = entry.durationMinutes.map { " — \($0) min" } ?? ""
                    out += "- 🏃 \(entry.exercise ?? "Exercise")\(mins)\(proj)\n"
                } else if entry.quickKind == "win" {
                    out += "- 🎉 \(entry.detail)\(proj)\n"
                } else if entry.quickKind == "fail" {
                    out += "- 🔸 \(entry.detail)\(proj)\n"
                } else if entry.isCheckin, let m = entry.mood {
                    let i = max(1, min(5, m)) - 1
                    out += "- \(moodEmoji[i]) Felt \(["rough", "tough", "okay", "good", "great"][i])\(proj)\n"
                } else if entry.isMeeting {
                    let tag = (entry.happened ?? true) ? "" : " (didn't happen)"
                    out += "\n### 📅 \(entry.title.isEmpty ? "Meeting" : entry.title)\(tag)\(proj)\n"
                    out += reflection(entry)
                } else {
                    out += "\n### \(entry.title.isEmpty ? "Untitled" : entry.title)\(proj)\n"
                    if !entry.tags.isEmpty { out += "Tags: \(entry.tags.joined(separator: ", "))\n" }
                    if let m = entry.mood {
                        out += "How it went: \(["Rough", "Tough", "Okay", "Good", "Great"][max(1, min(5, m)) - 1]) (\(m)/5)\n"
                    }
                    if !entry.detail.isEmpty { out += "\(entry.detail)\n" }
                    out += reflection(entry)
                }
            }
            if let dayLogs = logsByDay[day], !dayLogs.isEmpty {
                var counts: [UUID: Int] = [:]
                for l in dayLogs { counts[l.routineID, default: 0] += 1 }
                let parts = routines.compactMap { r -> String? in
                    guard let n = counts[r.id], n > 0 else { return nil }
                    let name = routineName[r.id] ?? "Routine"
                    return n == 1 ? "\(name) ✓" : "\(name) ×\(n)"
                }
                if !parts.isEmpty { out += "- 🏃 Movement: \(parts.joined(separator: " · "))\n" }
            }
        }
        return out
    }

    private static func reflection(_ entry: ReportEntry) -> String {
        var s = ""
        if !entry.wentWell.isEmpty { s += "- 🔹 What went well: \(entry.wentWell)\n" }
        if !entry.wentBad.isEmpty { s += "- 🔸 What went bad / to improve: \(entry.wentBad)\n" }
        return s
    }
}
