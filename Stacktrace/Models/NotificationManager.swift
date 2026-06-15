import Foundation
import UserNotifications

/// Schedules a single repeating daily local notification reminding the user to
/// log their day. Preferences live in UserDefaults so they survive launches.
enum NotificationManager {
    static let enabledKey = "reminderEnabled"
    static let hourKey = "reminderHour"
    static let minuteKey = "reminderMinute"
    private static let requestID = "daily-log-reminder"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var hour: Int {
        UserDefaults.standard.object(forKey: hourKey) as? Int ?? 17
    }
    static var minute: Int {
        UserDefaults.standard.object(forKey: minuteKey) as? Int ?? 0
    }

    /// Ask permission, then (re)schedule or cancel based on current prefs.
    static func refresh() {
        let center = UNUserNotificationCenter.current()
        guard isEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [requestID])
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            schedule()
        }
    }

    private static func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID])

        let content = UNMutableNotificationContent()
        content.title = "How did today go?"
        content.body = "Take a moment to log your day in Stacktrace."
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Routine reminders

    private static let routinePrefix = "routine-"

    /// Reschedule reminders for all routines. Daily routines fire once at their
    /// start hour; hourly routines fire each hour within their window.
    static func refreshRoutines(_ routines: [Routine]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(routinePrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            let active = routines.filter { $0.remind }
            guard !active.isEmpty else { return }
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                for routine in active {
                    let hours = routine.isHourly
                        ? Array(routine.startHour...max(routine.startHour, routine.endHour))
                        : [routine.startHour]
                    for h in hours {
                        let content = UNMutableNotificationContent()
                        content.title = "Time to move"
                        content.body = routine.name
                        content.sound = .default
                        var comps = DateComponents(); comps.hour = h; comps.minute = 0
                        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                        let id = "\(routinePrefix)\(routine.id.uuidString)-\(h)"
                        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                    }
                }
            }
        }
    }
}
