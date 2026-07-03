import SwiftUI
import Charts
import AppKit

/// The trend graphs that can be embedded in an export.
enum TrendChart: String, CaseIterable, Identifiable {
    case score, mood, activeMinutes
    var id: String { rawValue }
    var label: String {
        switch self {
        case .score: return "Overall day score"
        case .mood: return "Average mood"
        case .activeMinutes: return "Active minutes"
        }
    }
}

/// Renders the Trends charts to PNGs (base64) for embedding in the PDF, over a
/// given date range. Mirrors the on-screen Trends look.
@MainActor
enum TrendsChartRenderer {
    private struct DayPoint: Identifiable {
        let date: Date
        let score: Int?
        let mood: Double?
        let minutes: Int
        var id: Date { date }
    }

    private static func points(_ store: DataStore, from: Date, to: Date) -> [DayPoint] {
        let cal = Calendar.current
        let lo = cal.startOfDay(for: from)
        let hi = cal.startOfDay(for: to)
        let stats = store.dayStats()
        var out: [DayPoint] = []
        var d = lo
        while d <= hi {
            out.append(DayPoint(date: d,
                                score: store.dayRating(for: d),
                                mood: stats[d]?.avgMood,
                                minutes: store.activeMinutes(from: d, to: d)))
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return out
    }

    static func charts(_ store: DataStore, from: Date, to: Date,
                       kinds: Set<TrendChart> = Set(TrendChart.allCases)) -> [ReportChart] {
        let pts = points(store, from: from, to: to)
        // Nothing worth charting.
        guard pts.contains(where: { $0.score != nil || $0.mood != nil || $0.minutes > 0 }) else {
            return []
        }

        var result: [ReportChart] = []

        let scorePts = pts.filter { $0.score != nil }
        if kinds.contains(.score), !scorePts.isEmpty {
            let chart = Chart(scorePts) { p in
                LineMark(x: .value("Day", p.date), y: .value("Score", p.score ?? 0))
                    .foregroundStyle(.blue).interpolationMethod(.catmullRom)
                PointMark(x: .value("Day", p.date), y: .value("Score", p.score ?? 0))
                    .foregroundStyle(.blue)
            }
            .chartYScale(domain: 0...10)
            if let b64 = render(chart) { result.append(ReportChart(title: "Overall day score (/10)", pngBase64: b64)) }
        }

        let moodPts = pts.filter { $0.mood != nil }
        if kinds.contains(.mood), !moodPts.isEmpty {
            let chart = Chart(moodPts) { p in
                LineMark(x: .value("Day", p.date), y: .value("Mood", p.mood ?? 0))
                    .foregroundStyle(.green).interpolationMethod(.catmullRom)
                PointMark(x: .value("Day", p.date), y: .value("Mood", p.mood ?? 0))
                    .foregroundStyle(.green)
            }
            .chartYScale(domain: 1...5)
            if let b64 = render(chart) { result.append(ReportChart(title: "Average mood (/5)", pngBase64: b64)) }
        }

        if kinds.contains(.activeMinutes), pts.contains(where: { $0.minutes > 0 }) {
            let chart = Chart(pts) { p in
                BarMark(x: .value("Day", p.date), y: .value("Minutes", p.minutes))
                    .foregroundStyle(Color(red: 0.20, green: 0.62, blue: 0.86))
            }
            if let b64 = render(chart) { result.append(ReportChart(title: "Active minutes per day", pngBase64: b64)) }
        }

        return result
    }

    private static func render<V: View>(_ chart: V) -> String? {
        let view = chart
            .frame(width: 680, height: 220)
            .padding(8)
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png.base64EncodedString()
    }
}
