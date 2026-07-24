import SwiftUI

/// Lists the day's calendar meetings that haven't been reflected on yet, with
/// quick actions to log them. Renders nothing unless calendar is connected and
/// there are pending meetings.
struct MeetingsReview: View {
    let day: Date
    @EnvironmentObject private var store: DataStore
    @ObservedObject private var calendar = CalendarService.shared
    @AppStorage("calendarEnabled") private var enabled = false
    @State private var reviewAction: MeetingReviewAction?

    private var isPast: Bool { day <= Calendar.current.startOfDay(for: Date()) }

    private var pending: [CalendarMeeting] {
        guard enabled, calendar.authorized, isPast, !store.isOnHoliday(day) else { return [] }
        let logged = store.loggedMeetingIDs(on: day)
        return calendar.meetings(on: day).filter { !logged.contains($0.id) }
    }

    /// Pending meetings grouped by their source calendar, in first-seen order.
    private var groups: [CalendarGroup] {
        var order: [String] = []
        var byCal: [String: [CalendarMeeting]] = [:]
        for m in pending {
            if byCal[m.calendarTitle] == nil { order.append(m.calendarTitle) }
            byCal[m.calendarTitle, default: []].append(m)
        }
        return order.map { title in
            let items = byCal[title] ?? []
            return CalendarGroup(title: title,
                                 color: CalendarColor.from(items.first?.colorComponents),
                                 meetings: items)
        }
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
            VStack(alignment: .leading, spacing: 14) {
                Label("Meetings to review", systemImage: "calendar")
                    .font(.headline)
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle().fill(group.color).frame(width: 9, height: 9)
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(group.meetings) { meeting in
                            HStack(spacing: 10) {
                                Image(systemName: "person.2.fill").foregroundStyle(group.color)
                                Text(meeting.title).lineLimit(1)
                                Spacer()
                                Button("Didn't attend…") {
                                    reviewAction = MeetingReviewAction(
                                        meeting: meeting, kind: .didNotAttend)
                                }
                                .buttonStyle(.borderless)
                                Button("Didn't happen…") {
                                    reviewAction = MeetingReviewAction(
                                        meeting: meeting, kind: .didNotHappen)
                                }
                                .buttonStyle(.borderless)
                                Button("Log") {
                                    reviewAction = MeetingReviewAction(
                                        meeting: meeting, kind: .reflection)
                                }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12)))
            .sheet(item: $reviewAction) { action in
                switch action.kind {
                case .reflection:
                    MeetingReflectionSheet(day: day, meeting: action.meeting)
                case .didNotAttend:
                    MeetingAbsenceSheet(day: day, meeting: action.meeting,
                                        initialOutcome: .didNotAttend)
                case .didNotHappen:
                    MeetingAbsenceSheet(day: day, meeting: action.meeting,
                                        initialOutcome: .didNotHappen)
                }
            }
        }
    }
}

private struct MeetingReviewAction: Identifiable {
    enum Kind: String { case reflection, didNotAttend, didNotHappen }
    let meeting: CalendarMeeting
    let kind: Kind
    var id: String { "\(meeting.id)-\(kind.rawValue)" }
}

/// A day's pending meetings from one source calendar.
private struct CalendarGroup: Identifiable {
    var id: String { title }
    let title: String
    let color: Color
    let meetings: [CalendarMeeting]
}

/// Builds a SwiftUI Color from a calendar's stored sRGB components.
enum CalendarColor {
    static func from(_ components: [Double]?) -> Color {
        guard let c = components, c.count >= 3 else { return .blue }
        return Color(.sRGB, red: c[0], green: c[1], blue: c[2],
                     opacity: c.count >= 4 ? c[3] : 1)
    }
}

/// Prompt to reflect on a meeting: happened? what went well / badly?
private struct MeetingReflectionSheet: View {
    let day: Date
    let meeting: CalendarMeeting
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var outcome: MeetingOutcome = .attended
    @State private var absenceReason = ""
    @State private var wentWell = ""
    @State private var wentBad = ""
    @State private var mood: Int?
    @State private var enhancing = false
    @State private var enhanceError: String?

    private var hasNotes: Bool {
        !(wentWell.trimmingCharacters(in: .whitespaces).isEmpty
          && wentBad.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var canEnhance: Bool {
        outcome == .attended
            ? hasNotes
            : !absenceReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading) {
                    Text(meeting.title).font(.headline).lineLimit(2)
                    Text(outcome == .attended
                         ? "Reflect on this meeting"
                         : "Record why you weren't there")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Outcome", selection: $outcome) {
                ForEach(MeetingOutcome.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if outcome == .attended {
                MoodPicker(mood: $mood)
                field("What went well", text: $wentWell)
                field("What didn't / to improve", text: $wentBad)
            } else {
                field(outcome == .didNotAttend
                      ? "Why didn't you attend? (optional)"
                      : "Why didn't it happen? (optional)",
                      text: $absenceReason)
            }
            EnhanceButton(enhancing: enhancing, error: enhanceError,
                          canRun: canEnhance, action: enhance)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    store.addMeeting(eventID: meeting.id, title: meeting.title,
                                     outcome: outcome,
                                     absenceReason: absenceReason,
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

    private func enhance() {
        enhanceError = nil
        enhancing = true
        let snapshot = outcome == .attended
            ? EntryText(title: "", detail: "", wentWell: wentWell, wentBad: wentBad)
            : EntryText(title: "", detail: absenceReason, wentWell: "", wentBad: "")
        Task {
            do {
                let result = try await EnhancementService.enhance(snapshot)
                if outcome == .attended {
                    wentWell = result.wentWell
                    wentBad = result.wentBad
                } else {
                    absenceReason = result.detail
                }
            } catch {
                enhanceError = error.localizedDescription
            }
            enhancing = false
        }
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

/// Records that a calendar meeting was missed or cancelled, with an optional
/// explanation that remains visible in the day log and generated reports.
private struct MeetingAbsenceSheet: View {
    let day: Date
    let meeting: CalendarMeeting
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var outcome: MeetingOutcome
    @State private var reason = ""
    @State private var enhancing = false
    @State private var enhanceError: String?

    private let absenceOutcomes: [MeetingOutcome] = [.didNotAttend, .didNotHappen]

    init(day: Date, meeting: CalendarMeeting, initialOutcome: MeetingOutcome) {
        self.day = day
        self.meeting = meeting
        _outcome = State(initialValue: initialOutcome)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.orange, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading) {
                    Text(meeting.title).font(.headline).lineLimit(2)
                    Text("Record why you weren't there")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Outcome", selection: $outcome) {
                ForEach(absenceOutcomes) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text(outcome == .didNotAttend
                     ? "Why didn't you attend? (optional)"
                     : "Why didn't it happen? (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SpellCheckTextEditor(text: $reason)
                    .frame(height: 76)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor)))
            }
            EnhanceButton(
                enhancing: enhancing,
                error: enhanceError,
                canRun: !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: enhance
            )

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    store.addMeeting(eventID: meeting.id, title: meeting.title,
                                     outcome: outcome, absenceReason: reason, on: day)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func enhance() {
        enhanceError = nil
        enhancing = true
        let snapshot = EntryText(title: "", detail: reason, wentWell: "", wentBad: "")
        Task {
            do {
                reason = try await EnhancementService.enhance(snapshot).detail
            } catch {
                enhanceError = error.localizedDescription
            }
            enhancing = false
        }
    }
}

/// Compact row for a logged meeting reflection in the day list.
struct MeetingRow: View {
    let entry: ReportEntry
    var onDelete: () -> Void = {}
    @EnvironmentObject private var store: DataStore
    @State private var hovering = false

    private var outcome: MeetingOutcome { entry.resolvedMeetingOutcome }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.title2).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.blue, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title.isEmpty ? "Meeting" : entry.title)
                        .font(.body)
                    if let project = store.projectName(entry.projectID) {
                        ProjectChip(name: project)
                    }
                }
                if outcome != .attended {
                    Text(outcome.label).font(.caption).foregroundStyle(.secondary)
                    if let reason = entry.absenceReason, !reason.isEmpty {
                        Text("Reason: \(reason)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
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
