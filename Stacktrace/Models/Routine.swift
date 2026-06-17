import Foundation

/// A small movement / health routine the user wants to keep up — e.g. "Stand
/// & stretch", "Walk", "20 push-ups". Either once a day or every hour within a
/// time window.
struct Routine: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var cadence: String = "daily"   // "daily" | "hourly"
    var startHour: Int = 9          // window start (and the daily reminder time)
    var endHour: Int = 17           // window end (hourly only)
    var startMinute: Int?           // nil = :00
    var endMinute: Int?
    /// Hourly interval — every N hours within the window. nil/0 = every hour.
    var hourStep: Int?
    /// Calendar weekdays (1=Sun … 7=Sat) the routine runs on. nil = every day.
    var weekdays: [Int]?
    var remind: Bool = true
    var includeInReport: Bool = true
    var createdAt = Date()

    var isHourly: Bool { cadence == "hourly" }
    var step: Int { max(1, hourStep ?? 1) }
    var sMin: Int { startMinute ?? 0 }
    var eMin: Int { endMinute ?? 0 }

    struct Slot: Equatable { let hour: Int; let minute: Int }

    /// Times the routine fires within its window (minute = the start minute).
    var slots: [Slot] {
        guard isHourly else { return [Slot(hour: startHour, minute: sMin)] }
        let endTotal = endHour * 60 + eMin
        var out: [Slot] = []
        var h = startHour
        while h * 60 + sMin <= endTotal {
            out.append(Slot(hour: h, minute: sMin))
            h += step
        }
        return out.isEmpty ? [Slot(hour: startHour, minute: sMin)] : out
    }

    /// How many times a day this routine is "complete".
    var dailyTarget: Int { isHourly ? max(1, slots.count) : 1 }

    func runsOn(_ day: Date) -> Bool {
        guard let wd = weekdays, !wd.isEmpty, wd.count < 7 else { return true }
        return wd.contains(Calendar.current.component(.weekday, from: day))
    }

    var cadenceLabel: String {
        let dayPart: String
        if let wd = weekdays, wd.count < 7, !wd.isEmpty {
            let syms = Calendar.current.shortWeekdaySymbols
            let names = wd.sorted().compactMap { (1...7).contains($0) ? syms[$0 - 1] : nil }
            dayPart = " · " + names.joined(separator: " ")
        } else {
            dayPart = ""
        }
        if isHourly {
            let base = step == 1 ? "Hourly" : "Every \(step)h"
            return "\(base) \(Self.time(startHour, sMin))–\(Self.time(endHour, eMin))\(dayPart)"
        }
        return "Daily \(Self.time(startHour, sMin))\(dayPart)"
    }

    static func time(_ h: Int, _ m: Int) -> String { String(format: "%d:%02d", h, m) }
}

/// One recorded completion of a routine.
struct RoutineLog: Identifiable, Codable, Equatable {
    var id = UUID()
    var routineID: UUID
    var day: Date    // start-of-day
    var at: Date

    init(routineID: UUID, day: Date) {
        self.id = UUID()
        self.routineID = routineID
        self.day = Calendar.current.startOfDay(for: day)
        self.at = Date()
    }
}
