import Foundation

/// Calendar weekday (1 = Sunday … 7 = Saturday, matching `Calendar`).
enum Weekday: Int, CaseIterable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    /// Localized full name, e.g. "Monday".
    var name: String {
        Calendar.current.weekdaySymbols[rawValue - 1]
    }

    /// Monday-first display order.
    static let displayOrder: [Weekday] =
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
}

/// Which weekdays appear in the sidebar "this week" list. Stored as a bitmask
/// in UserDefaults so it can be read with @AppStorage anywhere.
enum WorkdayPreferences {
    static let key = "selectedWeekdays"

    static let defaultMask =
        bitmask([.monday, .tuesday, .wednesday, .thursday, .friday])

    static func bitmask(_ days: [Weekday]) -> Int {
        days.reduce(0) { $0 | (1 << $1.rawValue) }
    }

    static func contains(_ mask: Int, _ day: Weekday) -> Bool {
        mask & (1 << day.rawValue) != 0
    }

    static func toggled(_ mask: Int, _ day: Weekday) -> Int {
        mask ^ (1 << day.rawValue)
    }
}
