import SwiftUI

/// Sheet to choose a date range and export a PDF report.
/// Defaults to the calendar week of the day the sheet was opened from.
struct ReportView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generator: PDFReportGenerator?
    @State private var customName = ""

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

            VStack(alignment: .leading, spacing: 4) {
                TextField(defaultBaseName(), text: $customName)
                    .textFieldStyle(.roundedBorder)
                Text("File name — leave blank to use the default shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ReportPreviewCount(start: startDate, end: endDate)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
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
        .frame(width: 480, height: 400)
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

    private func export() {
        errorMessage = nil
        let entries = fetchEntries()
        let url = ExportStore.uniqueURL(baseName: resolvedBaseName())

        isGenerating = true
        let html = ReportHTMLBuilder.html(entries: entries, from: startDate, to: endDate)
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

    private func fetchEntries() -> [ReportEntry] {
        store.entries(from: startDate, to: endDate)
    }

    private func defaultBaseName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "Work Report \(f.string(from: startDate)) to \(f.string(from: endDate))"
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
    @EnvironmentObject private var store: DataStore

    private var count: Int { store.entries(from: start, to: end).count }

    var body: some View {
        Label("\(count) \(count == 1 ? "entry" : "entries") in range",
              systemImage: "doc.text")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
