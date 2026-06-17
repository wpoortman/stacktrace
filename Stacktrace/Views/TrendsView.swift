import SwiftUI
import Charts

/// Visual trends over the last few weeks: day score, mood, and active minutes.
struct TrendsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var pro: ProManager

    private let daysBack = 42   // 6 weeks

    private struct DayPoint: Identifiable {
        let date: Date
        let score: Int?
        let mood: Double?
        let minutes: Int
        var id: Date { date }
    }

    private var points: [DayPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let stats = store.dayStats()
        return (0..<daysBack).reversed().compactMap { offset -> DayPoint? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayPoint(
                date: day,
                score: store.dayRating(for: day),
                mood: stats[day]?.avgMood,
                minutes: store.activeMinutes(from: day, to: day)
            )
        }
    }

    var body: some View {
        if !pro.isPro {
            ProLockedView(feature: "Trends")
                .navigationTitle("Trends")
        } else {
            chartsBody
        }
    }

    private var chartsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if points.allSatisfy({ $0.score == nil && $0.mood == nil && $0.minutes == 0 }) {
                    ContentUnavailableView("Not enough data yet", systemImage: "chart.xyaxis.line",
                        description: Text("Log entries, ratings, and exercise to see trends here."))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    chartCard("Overall day score", unit: "/ 10") {
                        Chart(points.filter { $0.score != nil }) { p in
                            LineMark(x: .value("Day", p.date),
                                     y: .value("Score", p.score ?? 0))
                            .foregroundStyle(Color.accentColor)
                            .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Day", p.date),
                                      y: .value("Score", p.score ?? 0))
                            .foregroundStyle(Color.accentColor)
                        }
                        .chartYScale(domain: 0...10)
                    }

                    chartCard("Average mood", unit: "/ 5") {
                        Chart(points.filter { $0.mood != nil }) { p in
                            LineMark(x: .value("Day", p.date),
                                     y: .value("Mood", p.mood ?? 0))
                            .foregroundStyle(Color.green)
                            .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Day", p.date),
                                      y: .value("Mood", p.mood ?? 0))
                            .foregroundStyle(Color.green)
                        }
                        .chartYScale(domain: 1...5)
                    }

                    chartCard("Active minutes", unit: "per day") {
                        Chart(points) { p in
                            BarMark(x: .value("Day", p.date),
                                    y: .value("Minutes", p.minutes))
                            .foregroundStyle(Color(red: 0.20, green: 0.62, blue: 0.86))
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Trends")
    }

    private func chartCard<Content: View>(_ title: String, unit: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            content()
                .frame(height: 180)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12)))
    }
}
