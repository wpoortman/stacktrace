import SwiftUI
import AppKit

/// Sheet to choose a date range and export a PDF report.
/// Defaults to the calendar week of the day the sheet was opened from.
struct ReportView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var pro: ProManager
    @Environment(\.dismiss) private var dismiss

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generator: PDFReportGenerator?
    @State private var customName = ""
    @State private var note: String?
    @State private var selectedProject: UUID?
    @State private var selectedCharts: Set<TrendChart> = Set(TrendChart.allCases)

    /// Called after a successful export so the host can reveal the Exports list.
    var onExported: () -> Void = {}

    init(initialDate: Date, onExported: @escaping () -> Void = {}) {
        self.onExported = onExported
        let week = Calendar.current.weekInterval(for: initialDate)
        _startDate = State(initialValue: week.start)
        // weekInterval end is exclusive (next week 00:00) — step back a day.
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: week.end) ?? week.start
        _endDate = State(initialValue: lastDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Generate Report")
                .font(.title2.bold())

            HStack(spacing: 20) {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, displayedComponents: .date)
            }
            .datePickerStyle(.field)

            HStack(spacing: 8) {
                presetButton("This week", .weekOfYear, offset: 0)
                presetButton("Last week", .weekOfYear, offset: -1)
                presetButton("This month", .month, offset: 0)
            }

            if !store.projects.isEmpty {
                Picker("Project", selection: $selectedProject) {
                    Text("All entries").tag(UUID?.none)
                    ForEach(store.projects) { p in Text(p.name).tag(UUID?.some(p.id)) }
                }
            }

            if pro.isPro && selectedProject == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trend graphs to include")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        ForEach(TrendChart.allCases) { chart in
                            Toggle(chart.label, isOn: Binding(
                                get: { selectedCharts.contains(chart) },
                                set: { on in
                                    if on { selectedCharts.insert(chart) }
                                    else { selectedCharts.remove(chart) }
                                }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField(defaultBaseName(), text: $customName)
                    .textFieldStyle(.roundedBorder)
                Text("File name — leave blank to use the default shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ReportPreviewCount(start: startDate, end: endDate, projectID: selectedProject)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Copy as Markdown", action: copyMarkdown)
                Button {
                    export()
                } label: {
                    if isGenerating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Export PDF…")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || endDate < startDate)
            }
        }
        .padding(24)
        .frame(width: 480, height: 460)
    }

    private func presetButton(_ title: String, _ unit: Calendar.Component, offset: Int) -> some View {
        Button(title) {
            let cal = Calendar.current
            let base = cal.date(byAdding: unit, value: offset, to: Date()) ?? Date()
            if let interval = cal.dateInterval(of: unit, for: base) {
                startDate = interval.start
                endDate = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Inputs for the builders, scoped to the selected project (if any).
    private struct ReportData {
        var entries: [ReportEntry]
        var routines: [Routine]
        var logs: [RoutineLog]
        var ratings: [DayRating]
        var holidays: [HolidayPeriod]
        var projectNames: [UUID: String]
    }

    private func reportData() -> ReportData {
        let names = Dictionary(store.projects.map { ($0.id, $0.name) }) { a, _ in a }
        if let p = selectedProject {
            // A project report is just that project's entries.
            return ReportData(entries: store.entries(forProject: p, from: startDate, to: endDate),
                              routines: [], logs: [], ratings: [], holidays: [], projectNames: names)
        }
        let lo = Calendar.current.startOfDay(for: startDate)
        let hi = Calendar.current.startOfDay(for: endDate)
        let routines = store.routines.filter { $0.includeInReport }
        let ids = Set(routines.map(\.id))
        let logs = store.routineLogs.filter { ids.contains($0.routineID) && $0.day >= lo && $0.day <= hi }
        let ratings = store.dayRatings.filter { $0.day >= lo && $0.day <= hi }
        return ReportData(entries: store.entries(from: startDate, to: endDate),
                          routines: routines, logs: logs, ratings: ratings,
                          holidays: store.holidays, projectNames: names)
    }

    private func export() {
        errorMessage = nil
        let d = reportData()
        let url = ExportStore.uniqueURL(baseName: resolvedBaseName())
        isGenerating = true
        // Trends charts: Pro-only, and only for the all-entries report.
        let charts = (pro.isPro && selectedProject == nil)
            ? TrendsChartRenderer.charts(store, from: startDate, to: endDate, kinds: selectedCharts) : []
        let html = ReportHTMLBuilder.html(entries: d.entries, routines: d.routines,
                                          routineLogs: d.logs, dayRatings: d.ratings,
                                          holidays: d.holidays, projectNames: d.projectNames,
                                          charts: charts,
                                          from: startDate, to: endDate)
        let gen = PDFReportGenerator()
        generator = gen
        gen.generate(html: html, to: url) { result in
            isGenerating = false
            generator = nil
            switch result {
            case .success:
                onExported()
                dismiss()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copyMarkdown() {
        let d = reportData()
        let md = ReportMarkdownBuilder.markdown(entries: d.entries, routines: d.routines,
                                                routineLogs: d.logs, dayRatings: d.ratings,
                                                holidays: d.holidays, projectNames: d.projectNames,
                                                from: startDate, to: endDate)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        errorMessage = nil
        note = "Copied as Markdown — paste into Slack, email, or notes."
    }

    private func defaultBaseName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let prefix = store.projectName(selectedProject) ?? "Work"
        return "\(prefix) Report \(f.string(from: startDate)) to \(f.string(from: endDate))"
    }

    /// Custom name if given (sanitized), otherwise the default.
    private func resolvedBaseName() -> String {
        let cleaned = customName
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? defaultBaseName() : cleaned
    }
}

/// Live count of entries in the chosen range.
private struct ReportPreviewCount: View {
    let start: Date
    let end: Date
    let projectID: UUID?
    @EnvironmentObject private var store: DataStore

    private var count: Int {
        if let p = projectID { return store.entries(forProject: p, from: start, to: end).count }
        return store.entries(from: start, to: end).count
    }

    var body: some View {
        Label("\(count) \(count == 1 ? "entry" : "entries") in range",
              systemImage: "doc.text")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
