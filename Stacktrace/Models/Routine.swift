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
    var remind: Bool = true
    var includeInReport: Bool = true
    var createdAt = Date()

    var isHourly: Bool { cadence == "hourly" }

    /// How many times a day this routine is "complete".
    var dailyTarget: Int {
        isHourly ? max(1, endHour - startHour + 1) : 1
    }

    var cadenceLabel: String {
        isHourly ? "Hourly · \(startHour):00–\(endHour):00" : "Daily · \(startHour):00"
    }
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
