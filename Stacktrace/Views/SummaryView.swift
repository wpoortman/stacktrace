import SwiftUI
import AppKit

/// Generates a standalone AI-written summary from all source items in a period.
/// The result remains editable before it is copied or exported as a PDF.
struct SummaryView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedProject: UUID?
    @State private var generatedSummary = ""
    @State private var customName = ""
    @State private var generating = false
    @State private var exporting = false
    @State private var generator: PDFReportGenerator?
    @State private var errorMessage: String?
    @State private var note: String?

    /// Called after a PDF is saved so the host can reveal the Exports list.
    var onExported: () -> Void = {}

    init(initialDate: Date, onExported: @escaping () -> Void = {}) {
        self.onExported = onExported
        let week = Calendar.current.weekInterval(for: initialDate)
        _startDate = State(initialValue: week.start)
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: week.end) ?? week.start
        _endDate = State(initialValue: lastDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Generate Summary").font(.title2.bold())
                Text("AI turns the logged items in a period into a standalone written summary.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    periodSection

                    if !store.projects.isEmpty {
                        Picker("Project", selection: $selectedProject) {
                            Text("All entries").tag(UUID?.none)
                            ForEach(store.projects) { project in
                                Text(project.name).tag(UUID?.some(project.id))
                            }
                        }
                        .onChange(of: selectedProject) { _, _ in invalidateSummary() }
                    }

                    sourceCount

                    if AIConfig.hasAPIKey {
                        Label("Uses the standalone summary prompt from Settings → AI.",
                              systemImage: "text.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Add an AI provider key in Settings → AI before generating.",
                              systemImage: "key")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }

                    if !generatedSummary.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Generated summary").font(.headline)
                            Text("Edit anything you like before copying or exporting it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            SpellCheckTextEditor(text: $generatedSummary)
                                .padding(4)
                                .frame(minHeight: 210)
                                .background(Color(nsColor: .textBackgroundColor),
                                            in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor)))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("PDF file name").font(.headline)
                            TextField(defaultBaseName(), text: $customName)
                                .textFieldStyle(.roundedBorder)
                            Text("Leave blank to use the default shown.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

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
                }
                .padding(.trailing, 4)
            }

            Divider()
            footer
        }
        .padding(24)
        .frame(width: 540, height: 650)
    }

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Period").font(.headline)
            HStack(spacing: 20) {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                    .onChange(of: startDate) { _, _ in invalidateSummary() }
                DatePicker("To", selection: $endDate, displayedComponents: .date)
                    .onChange(of: endDate) { _, _ in invalidateSummary() }
            }
            .datePickerStyle(.field)

            HStack(spacing: 8) {
                presetButton("This week", .weekOfYear, offset: 0)
                presetButton("Last week", .weekOfYear, offset: -1)
                presetButton("This month", .month, offset: 0)
                presetButton("Last month", .month, offset: -1)
            }
        }
        .disabled(generating || exporting)
    }

    private var sourceCount: some View {
        let data = sourceData()
        return Label("\(data.itemCount) \(data.itemCount == 1 ? "source item" : "source items") in range",
                     systemImage: "text.document")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }
            Spacer()
            if generatedSummary.isEmpty {
                Button {
                    generate()
                } label: {
                    if generating { ProgressView().controlSize(.small) }
                    else { Label("Generate Summary", systemImage: "sparkles") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canGenerate)
            } else {
                Button("Regenerate") { generate() }
                    .disabled(generating || exporting)
                Button("Copy", action: copySummary)
                    .disabled(exporting)
                Button {
                    exportPDF()
                } label: {
                    if exporting { ProgressView().controlSize(.small) }
                    else { Text("Export PDF") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(exporting || generating || generatedSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var canGenerate: Bool {
        AIConfig.hasAPIKey && !generating && !exporting
            && endDate >= startDate && sourceData().itemCount > 0
    }

    private func presetButton(_ title: String, _ unit: Calendar.Component,
                              offset: Int) -> some View {
        Button(title) {
            let calendar = Calendar.current
            let base = calendar.date(byAdding: unit, value: offset, to: Date()) ?? Date()
            guard let interval = calendar.dateInterval(of: unit, for: base) else { return }
            startDate = interval.start
            endDate = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
            invalidateSummary()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private struct SourceData {
        var entries: [ReportEntry]
        var routines: [Routine]
        var logs: [RoutineLog]
        var ratings: [DayRating]
        var holidays: [HolidayPeriod]
        var projectNames: [UUID: String]

        var itemCount: Int { entries.count + logs.count + ratings.count }
    }

    /// Mirrors the full report's source rules so the two generation modes use
    /// the same facts for a selected period and optional project.
    private func sourceData() -> SourceData {
        let names = Dictionary(store.projects.map { ($0.id, $0.name) }) { first, _ in first }
        if let projectID = selectedProject {
            return SourceData(entries: store.entries(forProject: projectID, from: startDate, to: endDate),
                              routines: [], logs: [], ratings: [], holidays: [],
                              projectNames: names)
        }

        let calendar = Calendar.current
        let lowerBound = calendar.startOfDay(for: startDate)
        let upperBound = calendar.startOfDay(for: endDate)
        let routines = store.routines.filter { $0.includeInReport }
        let routineIDs = Set(routines.map(\.id))
        let logs = store.routineLogs.filter {
            routineIDs.contains($0.routineID) && $0.day >= lowerBound && $0.day <= upperBound
        }
        let ratings = store.dayRatings.filter { $0.day >= lowerBound && $0.day <= upperBound }
        return SourceData(entries: store.entries(from: startDate, to: endDate),
                          routines: routines, logs: logs, ratings: ratings,
                          holidays: store.holidays, projectNames: names)
    }

    private func generate() {
        let data = sourceData()
        guard data.itemCount > 0 else {
            errorMessage = "There are no logged items in this period to summarize."
            return
        }

        let markdown = ReportMarkdownBuilder.markdown(
            entries: data.entries,
            routines: data.routines,
            routineLogs: data.logs,
            dayRatings: data.ratings,
            holidays: data.holidays,
            projectNames: data.projectNames,
            from: startDate,
            to: endDate
        )
        let period = "\(DateFormat.short.string(from: startDate)) – \(DateFormat.short.string(from: endDate))"

        errorMessage = nil
        note = nil
        generating = true
        Task {
            do {
                generatedSummary = try await EnhancementService.generatePeriodSummary(
                    markdown, period: period, itemCount: data.itemCount)
            } catch {
                errorMessage = error.localizedDescription
            }
            generating = false
        }
    }

    private func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedSummary, forType: .string)
        note = "Copied — paste the summary into email, Slack, or notes."
        errorMessage = nil
    }

    private func exportPDF() {
        let summary = generatedSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return }
        let data = sourceData()
        let html = SummaryHTMLBuilder.html(summary: summary, itemCount: data.itemCount,
                                           from: startDate, to: endDate)
        let url = ExportStore.uniqueURL(baseName: resolvedBaseName())
        let pdfGenerator = PDFReportGenerator()
        generator = pdfGenerator
        exporting = true
        errorMessage = nil
        pdfGenerator.generate(html: html, to: url) { result in
            exporting = false
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

    private func invalidateSummary() {
        guard !generating && !exporting else { return }
        generatedSummary = ""
        customName = ""
        errorMessage = nil
        note = nil
    }

    private func defaultBaseName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let prefix = store.projectName(selectedProject) ?? "Work"
        return "\(prefix) Summary \(formatter.string(from: startDate)) to \(formatter.string(from: endDate))"
    }

    private func resolvedBaseName() -> String {
        let cleaned = customName
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? defaultBaseName() : cleaned
    }
}
