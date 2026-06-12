import SwiftUI

/// 1…5 sentiment scale used on entries and across the dashboard.
enum MoodScale {
    static let labels = ["Rough", "Tough", "Okay", "Good", "Great"]
    static let symbols = [
        "cloud.heavyrain.fill",
        "cloud.fill",
        "cloud.sun.fill",
        "sun.max.fill",
        "sparkles",
    ]
    static func label(_ m: Int) -> String { labels[max(1, min(5, m)) - 1] }
    static func symbol(_ m: Int) -> String { symbols[max(1, min(5, m)) - 1] }
}

/// Maps a mood score (1…5) to a colour on an orange → amber → green ramp.
/// This is the motivational signal: tougher days lean orange, great days green.
enum MoodColor {
    private static let stops: [(Double, (Double, Double, Double))] = [
        (1.0, (0.93, 0.35, 0.22)),   // orange-red
        (3.0, (0.96, 0.72, 0.20)),   // amber
        (5.0, (0.20, 0.72, 0.40)),   // green
    ]

    static func color(forScore score: Double) -> Color {
        let s = max(1.0, min(5.0, score))
        for i in 1..<stops.count {
            let (x0, c0) = stops[i - 1]
            let (x1, c1) = stops[i]
            if s <= x1 {
                let t = (s - x0) / (x1 - x0)
                return Color(
                    red: c0.0 + (c1.0 - c0.0) * t,
                    green: c0.1 + (c1.1 - c0.1) * t,
                    blue: c0.2 + (c1.2 - c0.2) * t
                )
            }
        }
        let last = stops.last!.1
        return Color(red: last.0, green: last.1, blue: last.2)
    }

    static func color(for mood: Int) -> Color { color(forScore: Double(mood)) }
}

/// Tappable 1…5 mood selector. Tapping the active level clears it.
struct MoodPicker: View {
    @Binding var mood: Int?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { m in
                let selected = mood == m
                Button {
                    mood = selected ? nil : m
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: MoodScale.symbol(m))
                            .font(.title3)
                        Text(MoodScale.label(m))
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        selected ? MoodColor.color(for: m).opacity(0.20)
                                 : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(selected ? MoodColor.color(for: m) : .clear, lineWidth: 2)
                    )
                    .foregroundStyle(selected ? MoodColor.color(for: m) : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
