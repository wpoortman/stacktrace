import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: DataStore
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showingReport = false
    @State private var showCalendar = false
    @State private var showingExports = false
    @State private var showingDashboard = true
    @State private var searchText = ""
    @State private var tagFilter: Set<String> = []

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || !tagFilter.isEmpty
    }

    private var daysWithEntries: Set<Date> { store.daysWithEntries }

    @AppStorage(WorkdayPreferences.key) private var weekdayMask = WorkdayPreferences.defaultMask

    /// Selected weekdays of the current real-world week, in Monday-first order.
    private var workdays: [Date] {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        let monday = cal.dateInterval(of: .weekOfYear, for: Date())?.start
            ?? cal.startOfDay(for: Date())
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
                    showingExports = false
                    showingDashboard = false
                }
            } else if showingDashboard {
                DashboardView()
            } else if showingExports {
                ExportsView()
            } else {
                EntryListView(day: selectedDate)
                    .navigationTitle(DateFormat.dayHeader.string(from: selectedDate))
            }
        }
        .onAppear { NotificationManager.refresh() }
        .searchable(text: $searchText, placement: .sidebar,
                    prompt: "Search title or tag")
        .sheet(isPresented: $showingReport) {
            ReportView(initialDate: selectedDate) {
                showingExports = true
            }
        }
    }

    private func selectDay(_ day: Date) {
        guard day <= Calendar.current.startOfDay(for: Date()) else { return }
        selectedDate = Calendar.current.startOfDay(for: day)
        showingExports = false
        showingDashboard = false
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showingDashboard = true
                showingExports = false
            } label: {
                Label("Dashboard", systemImage: "square.grid.2x2.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(showingDashboard ? .accentColor : nil)

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
                            showingExports = false
                            showingDashboard = false
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
                        isFuture: day > Calendar.current.startOfDay(for: Date())
                    ) {
                        selectDay(day)
                    }
                }
            }

            Divider()

            Divider()

            Button {
                showingExports = true
                showingDashboard = false
            } label: {
                Label("Exports", systemImage: "tray.full")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(showingExports ? .accentColor : nil)

            Spacer()

            Button {
                showingReport = true
            } label: {
                Label("Generate Report…", systemImage: "doc.richtext")
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
