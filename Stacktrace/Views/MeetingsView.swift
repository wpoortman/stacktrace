import SwiftUI

/// Today's meetings to review, plus recent reflections.
struct MeetingsView: View {
    @EnvironmentObject private var store: DataStore
    @ObservedObject private var calendar = CalendarService.shared
    @AppStorage("calendarEnabled") private var enabled = false

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var recent: [ReportEntry] {
        store.entries(on: today).filter { $0.isMeeting }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !enabled || !calendar.authorized {
                    notConnected
                } else {
                    MeetingsReview(day: today)
                    if !recent.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reviewed today").font(.headline)
                            ForEach(recent) { m in
                                MeetingRow(entry: m) { store.delete(m) }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12)))
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Meetings")
        .onAppear { calendar.refreshAuthState() }
    }

    private var notConnected: some View {
        ContentUnavailableView {
            Label("Calendar not connected", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("Connect your calendar to review the day's meetings and reflect on how they went.")
        } actions: {
            Button("Connect Calendar") {
                Task {
                    let granted = await calendar.requestAccess()
                    if granted { enabled = true }
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
