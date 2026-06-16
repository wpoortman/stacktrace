import Foundation
import EventKit

/// A calendar event surfaced for reflection.
struct CalendarMeeting: Identifiable, Equatable {
    let id: String      // EKEvent identifier
    let title: String
    let start: Date
}

/// Reads meetings from the macOS Calendar via EventKit. Because macOS Calendar
/// aggregates iCloud, Google, and Exchange accounts, this covers all of them
/// without any per-provider API or secrets.
@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    private let store = EKEventStore()

    @Published var authorized = false

    init() { refreshAuthState() }

    func refreshAuthState() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            authorized = status == .fullAccess
        } else {
            authorized = status == .authorized
        }
    }

    @discardableResult
    func requestAccess() async -> Bool {
        let granted: Bool
        do {
            if #available(macOS 14.0, *) {
                granted = try await store.requestFullAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
        } catch {
            granted = false
        }
        authorized = granted
        return granted
    }

    /// Timed (non all-day) events for a day, earliest first.
    func meetings(on day: Date) -> [CalendarMeeting] {
        guard authorized else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map { CalendarMeeting(id: $0.eventIdentifier ?? UUID().uuidString,
                                   title: ($0.title ?? "Meeting"),
                                   start: $0.startDate) }
    }
}
