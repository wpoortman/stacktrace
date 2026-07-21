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

enum DashboardPrompt {
    /// The dashboard's whole-day reflection belongs near the end of the workday,
    /// not at a time when the user cannot know how the day went yet.
    static func shouldAskHowDayWent(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        (16..<18).contains(calendar.component(.hour, from: date))
    }
}
