import SwiftUI

/// Motivational overview: streaks, quick stats and a GitHub-style
/// contribution graph coloured by how each day went.
struct DashboardView: View {
    @EnvironmentObject private var store: DataStore
    @AppStorage("lastCelebratedStreak") private var lastCelebrated = 0
    @State private var showConfetti = false
    @State private var confettiID = 0
    @State private var editingToday: ReportEntry?

    private let milestones = [3, 7, 14, 30, 50, 100]

    private var streak: Int { store.currentStreak() }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var todayLogged: Bool { store.hasEntries(on: today) }

    private var thisWeekCount: Int {
        let week = Calendar.current.weekInterval(for: Date())
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: week.end) ?? week.start
        return store.entriesCount(from: week.start, to: lastDay)
    }

    private var weekActiveMinutes: Int {
        let week = Calendar.current.weekInterval(for: Date())
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: week.end) ?? week.start
        return store.activeMinutes(from: week.start, to: lastDay)
    }

    private var reachedMilestone: Int? {
        milestones.filter { $0 <= streak }.max()
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    greeting
                    if let day = store.dayNeedingRating() { ratingCard(day) }
                    if let m = reachedMilestone { milestoneBanner(m) }
                    todayCard
                    if !store.routines.isEmpty { routinesCard }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4),
                              spacing: 14) {
                        StatCard(title: "Current streak",
                                 value: "\(streak)", unit: streak == 1 ? "day" : "days",
                                 symbol: "flame.fill", tint: .orange)
                        StatCard(title: "This week",
                                 value: "\(thisWeekCount)", unit: thisWeekCount == 1 ? "entry" : "entries",
                                 symbol: "calendar", tint: .blue)
                        StatCard(title: "Total logged",
                                 value: "\(store.totalEntries)", unit: store.totalEntries == 1 ? "entry" : "entries",
                                 symbol: "tray.full.fill", tint: .purple)
                        moodCard
                        StatCard(title: "Active this week",
                                 value: "\(weekActiveMinutes)", unit: "min",
                                 symbol: "figure.run", tint: Color(red: 0.20, green: 0.62, blue: 0.86))
                        dayScoreCard
                    }

                    ContributionGraph(stats: store.dayStats())
                }
                .padding(24)
            }

            if showConfetti {
                ConfettiView()
                    .id(confettiID)
                    .transition(.opacity)
            }
        }
        .navigationTitle("Dashboard")
        .sheet(item: $editingToday) { entry in
            EntryEditorView(entry: entry, isNew: true)
        }
        .onAppear(perform: checkMilestone)
        .onChange(of: store.totalEntries) { _, _ in checkMilestone() }
    }

    // MARK: Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(.title2.bold())
            Text(subhead)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var headline: String {
        switch streak {
        case 0: return "Ready when you are."
        case 1: return "You're on the board."
        case 2...4: return "\(streak)-day streak — nice rhythm."
        default: return "\(streak) days straight. On fire."
        }
    }

    private var subhead: String {
        if streak == 0 { return "Log what you did today to start a streak." }
        if !todayLogged { return "Log today to keep your \(streak)-day streak alive." }
        return "Nice — today's in. Keep the momentum."
    }

    private var dayScoreCard: some View {
        let avg = store.averageDayRating
        return StatCard(
            title: "Avg day score",
            value: avg.map { String(format: "%.1f", $0) } ?? "—",
            unit: avg != nil ? "/ 10" : "no ratings",
            symbol: "star.fill",
            tint: avg.map { MoodColor.color(forScore: 1 + ($0 - 1) / 9 * 4) } ?? .secondary
        )
    }

    private var moodCard: some View {
        let avg = store.averageMood
        return StatCard(
            title: "Avg mood",
            value: avg.map { String(format: "%.1f", $0) } ?? "—",
            unit: avg != nil ? "/ 5" : "no ratings",
            symbol: avg.map { MoodScale.symbol(Int($0.rounded())) } ?? "questionmark.circle",
            tint: avg.map { MoodColor.color(forScore: $0) } ?? .secondary
        )
    }

    // MARK: Milestone banner

    private func milestoneBanner(_ m: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill").foregroundStyle(.orange)
            Text("\(m)-day streak — keep it burning!")
                .font(.callout.weight(.semibold))
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25)))
    }

    // MARK: Today card

    @ViewBuilder
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if todayLogged {
                Label("Today's logged", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Add a quick win or setback, or write a full entry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("How did today go?")
                    .font(.headline)
                Text("One tap to start — you can add detail anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                quickMoodRow
            }

            QuickActions(day: today) {
                editingToday = ReportEntry(date: today)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12)))
    }

    private var quickMoodRow: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { m in
                Button {
                    store.addCheckin(mood: m)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: MoodScale.symbol(m)).font(.title3)
                        Text(MoodScale.label(m)).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(MoodColor.color(for: m).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(MoodColor.color(for: m))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Milestone celebration

    private func checkMilestone() {
        let s = streak
        if s == 0 { lastCelebrated = 0; return }
        if milestones.contains(s), s > lastCelebrated {
            lastCelebrated = s
            confettiID += 1
            withAnimation { showConfetti = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                withAnimation { showConfetti = false }
            }
        }
    }

    // MARK: Routines

    private var routinesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Move a little", systemImage: "figure.walk")
                .font(.headline)
            ForEach(store.routines) { routine in
                RoutineRow(routine: routine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12)))
    }

    // MARK: Day rating prompt

    private func ratingCard(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let label = isToday ? "today" : DateFormat.dayHeader.string(from: day)
        return VStack(alignment: .leading, spacing: 10) {
            Text("How was \(label) overall?")
                .font(.headline)
            Text("Give the whole day a score from 1 to 10.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(1...10, id: \.self) { n in
                    Button {
                        store.setDayRating(n, for: day)
                    } label: {
                        Text("\(n)")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(score10Color(n).opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(score10Color(n))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.25)))
    }

    /// Map 1…10 onto the orange→green mood ramp.
    private func score10Color(_ n: Int) -> Color {
        MoodColor.color(forScore: 1 + Double(n - 1) / 9 * 4)
    }
}

private struct RoutineRow: View {
    let routine: Routine
    @EnvironmentObject private var store: DataStore

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var count: Int { store.completions(routine, on: today) }
    private var done: Bool { store.isDone(routine, on: today) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name).font(.callout.weight(.medium))
                Text(routine.cadenceLabel).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if routine.isHourly {
                Text("\(count)/\(routine.dailyTarget)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                if count > 0 {
                    Button { store.undoCompletion(routine, on: today) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
                Button { store.logCompletion(routine, on: today) } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            } else {
                Button {
                    if done { store.undoCompletion(routine, on: today) }
                    else { store.logCompletion(routine, on: today) }
                } label: {
                    Text(done ? "Undo" : "Done")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title.bold())
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color.secondary.opacity(0.12)))
    }
}

/// GitHub-style grid: columns = weeks, rows = weekdays (Mon-first).
/// Cell hue = how the day went, opacity = how much was logged.
private struct ContributionGraph: View {
    let stats: [Date: DataStore.DayStat]

    private let weeksBack = 26
    private let cell: CGFloat = 15
    private let spacing: CGFloat = 4

    private var calendar: Calendar {
        var c = Calendar.current; c.firstWeekday = 2; return c
    }

    private var columns: [[Date]] {
        let cal = calendar
        let today = cal.startOfDay(for: Date())
        let thisMonday = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let firstMonday = cal.date(byAdding: .day, value: -7 * (weeksBack - 1), to: thisMonday) ?? thisMonday
        return (0..<weeksBack).map { w in
            let weekStart = cal.date(byAdding: .day, value: 7 * w, to: firstMonday) ?? firstMonday
            return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    weekdayLabels
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: spacing) {
                            ForEach(week, id: \.self) { day in
                                cellView(day)
                            }
                        }
                    }
                }
            }

            legend
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color.secondary.opacity(0.12)))
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: spacing) {
            ForEach(0..<7, id: \.self) { i in
                Text(["Mon", "", "Wed", "", "Fri", "", "Sun"][i])
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(height: cell, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ day: Date) -> some View {
        let today = calendar.startOfDay(for: Date())
        let future = day > today
        let stat = stats[day]
        RoundedRectangle(cornerRadius: 3)
            .fill(color(for: stat, future: future))
            .frame(width: cell, height: cell)
            .help(tooltip(day, stat))
    }

    private func color(for stat: DataStore.DayStat?, future: Bool) -> Color {
        guard let stat, stat.count > 0, !future else {
            return Color.secondary.opacity(future ? 0.04 : 0.12)
        }
        let score = stat.avgMood ?? 3.0   // logged-but-unrated reads neutral
        let opacity = min(1.0, 0.5 + Double(min(stat.count, 4) - 1) * 0.165)
        return MoodColor.color(forScore: score).opacity(opacity)
    }

    private func tooltip(_ day: Date, _ stat: DataStore.DayStat?) -> String {
        let date = DateFormat.short.string(from: day)
        guard let stat, stat.count > 0 else { return "\(date): no entries" }
        let n = "\(stat.count) \(stat.count == 1 ? "entry" : "entries")"
        if let m = stat.avgMood {
            return "\(date): \(n) · \(MoodScale.label(Int(m.rounded())))"
        }
        return "\(date): \(n)"
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Text("Tougher")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach([1.0, 2.0, 3.0, 4.0, 5.0], id: \.self) { s in
                RoundedRectangle(cornerRadius: 3)
                    .fill(MoodColor.color(forScore: s))
                    .frame(width: 13, height: 13)
            }
            Text("Great")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text("Brighter = more logged")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
