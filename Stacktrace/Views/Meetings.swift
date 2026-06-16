import SwiftUI

/// Lists the day's calendar meetings that haven't been reflected on yet, with
/// quick actions to log them. Renders nothing unless calendar is connected and
/// there are pending meetings.
struct MeetingsReview: View {
    let day: Date
    @EnvironmentObject private var store: DataStore
    @ObservedObject private var calendar = CalendarService.shared
    @AppStorage("calendarEnabled") private var enabled = false
    @State private var reflecting: CalendarMeeting?

    private var isPast: Bool { day <= Calendar.current.startOfDay(for: Date()) }

    private var pending: [CalendarMeeting] {
        guard enabled, calendar.authorized, isPast else { return [] }
        let logged = store.loggedMeetingIDs(on: day)
        return calendar.meetings(on: day).filter { !logged.contains($0.id) }
    }

    var body: some View {
        Group {
            content
        }
        .onAppear { calendar.refreshAuthState() }
    }

    @ViewBuilder
    private var content: some View {
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Meetings to review", systemImage: "calendar")
                    .font(.headline)
                ForEach(pending) { meeting in
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.fill").foregroundStyle(.blue)
                        Text(meeting.title).lineLimit(1)
                        Spacer()
                        Button("Didn't happen") {
                            store.addMeeting(eventID: meeting.id, title: meeting.title,
                                             happened: false, wentWell: "", wentBad: "",
                                             mood: nil, on: day)
                        }
                        .buttonStyle(.borderless)
                        Button("Log") { reflecting = meeting }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12)))
            .sheet(item: $reflecting) { meeting in
                MeetingReflectionSheet(day: day, meeting: meeting)
            }
        }
    }
}

/// Prompt to reflect on a meeting: happened? what went well / badly?
private struct MeetingReflectionSheet: View {
    let day: Date
    let meeting: CalendarMeeting
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var wentWell = ""
    @State private var wentBad = ""
    @State private var mood: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading) {
                    Text(meeting.title).font(.headline).lineLimit(2)
                    Text("Reflect on this meeting").font(.caption).foregroundStyle(.secondary)
                }
            }

            MoodPicker(mood: $mood)
            field("What went well", text: $wentWell)
            field("What didn't / to improve", text: $wentBad)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    store.addMeeting(eventID: meeting.id, title: meeting.title,
                                     happened: true,
                                     wentWell: wentWell, wentBad: wentBad,
                                     mood: mood, on: day)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            SpellCheckTextEditor(text: text)
                .frame(height: 60)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        }
    }
}

/// Compact row for a logged meeting reflection in the day list.
struct MeetingRow: View {
    let entry: ReportEntry
    var onDelete: () -> Void = {}
    @State private var hovering = false

    private var happened: Bool { entry.happened ?? true }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.title2).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.blue, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? "Meeting" : entry.title)
                    .font(.body)
                if !happened {
                    Text("Didn't happen").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        if let m = entry.mood {
                            Label(MoodScale.label(m), systemImage: MoodScale.symbol(m))
                                .foregroundStyle(MoodColor.color(for: m))
                        }
                        if !entry.wentWell.isEmpty {
                            Label("Went well", systemImage: "hand.thumbsup").foregroundStyle(.green)
                        }
                        if !entry.wentBad.isEmpty {
                            Label("To improve", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                    }
                    .font(.caption2)
                }
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0.4)
            .help("Remove")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
