import Foundation
import UserNotifications

/// Presentation delegate so notifications also show while the app is frontmost,
/// and to handle the "Done" action on routine reminders.
private final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var store: DataStore?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // If this reminder has an auto-clear timer and the app is running to see
        // it, remove it from Notification Center after the set delay.
        scheduleAutoDismiss(for: notification, center: center)
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let request = response.notification.request
        let info = request.content.userInfo
        if response.actionIdentifier == NotificationManager.doneActionID,
           let idStr = info["routineID"] as? String, let rid = UUID(uuidString: idStr) {
            Task { @MainActor in
                if let store, let routine = store.routines.first(where: { $0.id == rid }),
                   !store.isDone(routine, on: Date()) {
                    store.logCompletion(routine)
                }
            }
            center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
        }
        completionHandler()
    }

    private func scheduleAutoDismiss(for notification: UNNotification, center: UNUserNotificationCenter) {
        guard let secs = notification.request.content.userInfo["dismissAfter"] as? Int, secs > 0 else { return }
        let id = notification.request.identifier
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(secs)) {
            center.removeDeliveredNotifications(withIdentifiers: [id])
        }
    }
}

/// Schedules a single repeating daily local notification reminding the user to
/// log their day. Preferences live in UserDefaults so they survive launches.
enum NotificationManager {
    private static let delegate = NotifDelegate()

    static let routineCategoryID = "ROUTINE_REMINDER"
    static let doneActionID = "ROUTINE_DONE"

    /// Install the presentation delegate and the routine reminder category (with
    /// its "Done" action). Call once at launch, passing the live data store so
    /// the "Done" button can log the completion.
    static func configure(store: DataStore? = nil) {
        let center = UNUserNotificationCenter.current()
        if let store { delegate.store = store }
        center.delegate = delegate
        let done = UNNotificationAction(identifier: doneActionID, title: "Done", options: [])
        let category = UNNotificationCategory(identifier: routineCategoryID, actions: [done],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    /// Clear routine reminders whose auto-clear delay has elapsed. Call when the
    /// app becomes active, to catch reminders delivered while it was in the
    /// background (where the foreground timer never ran).
    static func pruneExpiredRoutineNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let now = Date()
            let expired = delivered.filter { n in
                guard let secs = n.request.content.userInfo["dismissAfter"] as? Int, secs > 0 else { return false }
                return now.timeIntervalSince(n.date) >= Double(secs)
            }.map { $0.request.identifier }
            if !expired.isEmpty { center.removeDeliveredNotifications(withIdentifiers: expired) }
        }
    }

    /// Cancel all pending reminders (used during a holiday).
    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - End-of-day score reminder

    static let dayScoreEnabledKey = "dayScoreReminderEnabled"
    private static let dayScoreID = "day-score-reminder"

    static var dayScoreEnabled: Bool { UserDefaults.standard.bool(forKey: dayScoreEnabledKey) }
    private static var endOfDayHour: Int {
        (UserDefaults.standard.object(forKey: "endOfDayHour") as? Int) ?? 18
    }

    /// (Re)schedule the daily "score your day" reminder at the end-of-day hour.
    static func refreshDayScore() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dayScoreID])
        guard dayScoreEnabled else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "How did today go?"
            content.body = "Take a moment to give the day a score."
            content.sound = .default
            var comps = DateComponents(); comps.hour = endOfDayHour; comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: dayScoreID, content: content, trigger: trigger))
        }
    }

    /// Fire a sample notification so the user can see what a reminder looks
    /// like. Reports a precise message about what happened.
    static func sendTest(_ result: @escaping (String) -> Void) {
        configure()
        let center = UNUserNotificationCenter.current()
        func report(_ s: String) { DispatchQueue.main.async { result(s) } }

        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .denied {
                report("Notifications are turned off for Stacktrace. Enable them in System Settings → Notifications.")
                return
            }
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    report("Error: \(error.localizedDescription)")
                    return
                }
                guard granted else {
                    report("Permission wasn't granted. Unsigned development builds often can't get notification access — try a signed build in /Applications.")
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "Stacktrace"
                content.body = "This is what a reminder looks like."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
                let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)",
                                                    content: content, trigger: trigger)
                center.add(request) { addError in
                    if let addError {
                        report("Couldn't schedule: \(addError.localizedDescription)")
                    } else {
                        report("Sent — it appears in a couple of seconds.")
                    }
                }
            }
        }
    }
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

    /// Fire a routine's reminder once, ~2s from now, so the user can preview the
    /// banner, its "Done" button, and the auto-clear behaviour. Reports back a
    /// short status message.
    static func simulateRoutine(_ routine: Routine, _ result: @escaping (String) -> Void) {
        configure()
        let center = UNUserNotificationCenter.current()
        func report(_ s: String) { DispatchQueue.main.async { result(s) } }

        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .denied {
                report("Notifications are off for Stacktrace. Enable them in System Settings → Notifications.")
                return
            }
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error { report("Error: \(error.localizedDescription)"); return }
                guard granted else {
                    report("Permission wasn't granted. Try a signed build in /Applications.")
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "Time to move"
                content.body = routine.name.isEmpty ? "Routine" : routine.name
                content.sound = .default
                content.categoryIdentifier = routineCategoryID
                content.userInfo = ["routineID": routine.id.uuidString,
                                    "dismissAfter": routine.dismissAfter ?? 0]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
                let request = UNNotificationRequest(identifier: "\(routinePrefix)sim-\(UUID().uuidString)",
                                                    content: content, trigger: trigger)
                center.add(request) { addError in
                    if let addError { report("Couldn't schedule: \(addError.localizedDescription)") }
                    else {
                        let clear = (routine.dismissAfter ?? 0) > 0
                            ? " It auto-clears after \(routine.dismissAfter!)s." : ""
                        report("Sent — appears in ~2s. Try the Done button.\(clear)")
                    }
                }
            }
        }
    }

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
                    // nil/all-7 weekdays => fire every day (no weekday component).
                    let weekdays: [Int?]
                    if let wd = routine.weekdays, !wd.isEmpty, wd.count < 7 {
                        weekdays = wd.map { Optional($0) }
                    } else {
                        weekdays = [nil]
                    }
                    for slot in routine.slots {
                        for wd in weekdays {
                            let content = UNMutableNotificationContent()
                            content.title = "Time to move"
                            content.body = routine.name
                            content.sound = .default
                            content.categoryIdentifier = routineCategoryID
                            content.userInfo = ["routineID": routine.id.uuidString,
                                                "dismissAfter": routine.dismissAfter ?? 0]
                            var comps = DateComponents()
                            comps.hour = slot.hour
                            comps.minute = slot.minute
                            if let wd { comps.weekday = wd }
                            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                            let id = "\(routinePrefix)\(routine.id.uuidString)-\(wd.map(String.init) ?? "x")-\(slot.hour)-\(slot.minute)"
                            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                        }
                    }
                }
            }
        }
    }
}
