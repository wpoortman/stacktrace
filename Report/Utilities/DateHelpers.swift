import Foundation

extension Calendar {
    /// Date interval covering the calendar week that contains `date`.
    func weekInterval(for date: Date) -> DateInterval {
        dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: startOfDay(for: date), duration: 7 * 86_400)
    }
}

enum DateFormat {
    /// "Monday, 9 June 2026"
    static let dayHeader: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM yyyy"
        return f
    }()

    /// "9 Jun 2026"
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()
}
