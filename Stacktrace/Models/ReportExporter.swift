import Foundation

/// Builds and writes a report PDF for a date range into the Exports folder.
/// Shared by manual and automatic export.
@MainActor
enum ReportExporter {
    /// Retains the in-flight generator until completion.
    private static var live: [PDFReportGenerator] = []

    static func export(store: DataStore, from: Date, to: Date, baseName: String,
                       completion: @escaping (Result<URL, Error>) -> Void) {
        let entries = store.entries(from: from, to: to)
        let lo = Calendar.current.startOfDay(for: from)
        let hi = Calendar.current.startOfDay(for: to)
        let routines = store.routines.filter { $0.includeInReport }
        let ids = Set(routines.map(\.id))
        let logs = store.routineLogs.filter { ids.contains($0.routineID) && $0.day >= lo && $0.day <= hi }
        let ratings = store.dayRatings.filter { $0.day >= lo && $0.day <= hi }

        let names = Dictionary(store.projects.map { ($0.id, $0.name) }) { a, _ in a }
        let html = ReportHTMLBuilder.html(entries: entries, routines: routines,
                                          routineLogs: logs, dayRatings: ratings,
                                          holidays: store.holidays, projectNames: names,
                                          from: from, to: to)
        let url = ExportStore.uniqueURL(baseName: baseName)
        let gen = PDFReportGenerator()
        live.append(gen)
        gen.generate(html: html, to: url) { result in
            live.removeAll { $0 === gen }
            completion(result)
        }
    }
}
