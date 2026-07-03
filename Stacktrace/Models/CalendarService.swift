import Foundation
import EventKit

/// A calendar event surfaced for reflection.
struct CalendarMeeting: Identifiable, Equatable {
    let id: String              // EKEvent identifier
    let title: String
    let start: Date
    let calendarTitle: String   // the source calendar (e.g. "Work", "Personal")
    let colorComponents: [Double]?  // sRGB rgba of the calendar's colour, if any
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
            .map { event in
                CalendarMeeting(id: event.eventIdentifier ?? UUID().uuidString,
                                title: event.title ?? "Meeting",
                                start: event.startDate,
                                calendarTitle: event.calendar?.title ?? "Calendar",
                                colorComponents: Self.rgba(event.calendar?.cgColor))
            }
    }

    /// sRGB [r, g, b, a] for a calendar's colour, for tinting in the UI.
    private static func rgba(_ cgColor: CGColor?) -> [Double]? {
        guard let cgColor,
              let converted = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                intent: .defaultIntent, options: nil),
              let c = converted.components, c.count >= 3 else { return nil }
        let a = c.count >= 4 ? c[3] : 1
        return [Double(c[0]), Double(c[1]), Double(c[2]), Double(a)]
    }
}
