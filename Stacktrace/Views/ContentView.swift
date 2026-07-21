import SwiftUI

enum MainPanel {
    case dashboard, activity, meetings, trends, day, exports
}

private enum GenerateOption: String, Identifiable {
    case report, summary
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var store: DataStore
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var generateOption: GenerateOption?
    @State private var showCalendar = false
    @State private var panel: MainPanel = .dashboard
    @State private var searchText = ""
    @State private var tagFilter: Set<String> = []
    @AppStorage("didOnboard") private var didOnboard = false
    /// Drives the "this week" list; bumped when the calendar day changes so the
    /// sidebar rolls over to the new week without a relaunch.
    @State private var todayAnchor = Calendar.current.startOfDay(for: Date())

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || !tagFilter.isEmpty
    }

    private var daysWithEntries: Set<Date> { store.daysWithEntries }

    @AppStorage(WorkdayPreferences.key) private var weekdayMask = WorkdayPreferences.defaultMask

    /// Selected weekdays of the current real-world week, in Monday-first order.
    private var workdays: [Date] {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        let monday = cal.dateInterval(of: .weekOfYear, for: todayAnchor)?.start
            ?? cal.startOfDay(for: todayAnchor)
        return (0..<7).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: offset, to: monday),
                  let day = Weekday(rawValue: cal.component(.weekday, from: date)),
                  WorkdayPreferences.contains(weekdayMask, day)
            else { return nil }
            return date
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if isSearching {
                SearchView(query: searchText, tagFilter: $tagFilter) { date in
                    selectedDate = Calendar.current.startOfDay(for: date)
                    searchText = ""
                    tagFilter = []
                    panel = .day
                }
            } else {
                switch panel {
                case .dashboard: DashboardView()
                case .activity: ActivityView()
                case .meetings: MeetingsView()
                case .trends: TrendsView()
                case .exports: ExportsView()
                case .day:
                    EntryListView(day: selectedDate)
                        .navigationTitle(DateFormat.dayHeader.string(from: selectedDate))
                }
            }
        }
        .onAppear {
            NotificationManager.configure(store: store)
            NotificationManager.clearLegacyRoutineNotifications()
            RoutineReminder.shared.configure(store: store)
            applySchedule()
            refreshToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshToday()
            RoutineReminder.shared.reschedule()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshToday()
        }
        .onChange(of: store.holidays) { _, _ in applySchedule() }
        .onChange(of: store.routines) { _, _ in RoutineReminder.shared.reschedule() }
        .sheet(isPresented: .init(get: { !didOnboard }, set: { _ in })) {
            OnboardingView()
        }
        .searchable(text: $searchText, placement: .sidebar,
                    prompt: "Search title or tag")
        .sheet(item: $generateOption) { option in
            switch option {
            case .report:
                ReportView(initialDate: selectedDate) {
                    panel = .exports
                }
            case .summary:
                SummaryView(initialDate: selectedDate) {
                    panel = .exports
                }
            }
        }
    }

    /// Roll the sidebar to the current week when the day changes.
    private func refreshToday() {
        let start = Calendar.current.startOfDay(for: Date())
        if start != todayAnchor { todayAnchor = start }
    }

    /// Pause all nudges while on holiday; otherwise schedule normally.
    private func applySchedule() {
        // Don't touch notifications / auto-export while running unit tests.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        if store.isOnHoliday() {
            NotificationManager.cancelAll()
            RoutineReminder.shared.reschedule()  // clears timers while on holiday
        } else {
            NotificationManager.refresh()
            NotificationManager.refreshDayScore()
            RoutineReminder.shared.reschedule()
            AutoExport.runIfDue(store: store)
        }
    }

    private func selectDay(_ day: Date) {
        guard day <= Calendar.current.startOfDay(for: Date()) else { return }
        selectedDate = Calendar.current.startOfDay(for: day)
        panel = .day
    }

    private func navButton(_ title: String, _ symbol: String,
                           _ color: Color, _ target: MainPanel) -> some View {
        Button {
            panel = target
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(color, in: RoundedRectangle(cornerRadius: 6))
                Text(title)
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panel == target ? Color.accentColor.opacity(0.18) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 2) {
                navButton("Dashboard", "square.grid.2x2.fill", .blue, .dashboard)
                navButton("Activity", "figure.run", .green, .activity)
                navButton("Meetings", "person.2.fill", .indigo, .meetings)
                navButton("Trends", "chart.xyaxis.line", .orange, .trends)
                navButton("Exports", "tray.full.fill", .gray, .exports)
            }

            HStack {
                Text("THIS WEEK")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showCalendar.toggle()
                } label: {
                    Image(systemName: "calendar")
                }
                .buttonStyle(.borderless)
                .help("Pick a custom date")
                .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                    DatePicker("Day", selection: $selectedDate, in: ...Date(),
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding()
                        .onChange(of: selectedDate) { _, _ in
                            panel = .day
                            showCalendar = false
                        }
                }
            }

            VStack(spacing: 2) {
                ForEach(workdays, id: \.self) { day in
                    WeekdayRow(
                        day: day,
                        isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate),
                        hasEntries: daysWithEntries.contains(Calendar.current.startOfDay(for: day)),
                        isFuture: day > todayAnchor
                    ) {
                        selectDay(day)
                    }
                }
            }

            Spacer()

            Menu {
                Button {
                    generateOption = .report
                } label: {
                    Label("Report…", systemImage: "doc.richtext")
                }
                Button {
                    generateOption = .summary
                } label: {
                    Label("Summary…", systemImage: "text.document")
                }
            } label: {
                Label("Generate", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 240)
    }
}

private struct WeekdayRow: View {
    let day: Date
    let isSelected: Bool
    let hasEntries: Bool
    let isFuture: Bool
    let action: () -> Void

    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
    private static let dayNum: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(Self.weekday.string(from: day))
                    .fontWeight(isToday ? .semibold : .regular)
                Spacer()
                if hasEntries {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
                Text(Self.dayNum.string(from: day))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Color.accentColor.opacity(0.18) : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .opacity(isFuture ? 0.35 : 1)
    }
}
