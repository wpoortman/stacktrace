import SwiftUI

/// Lightweight one-shot confetti burst. Drops a set of coloured pieces that
/// fall and fade. Render it in an overlay; it animates on appear.
struct ConfettiView: View {
    var pieceCount = 70
    private let colors: [Color] = [
        Color(red: 0.20, green: 0.72, blue: 0.40),
        Color(red: 0.96, green: 0.72, blue: 0.20),
        Color(red: 0.36, green: 0.42, blue: 1.0),
        Color(red: 0.93, green: 0.35, blue: 0.45),
        Color(red: 0.54, green: 0.30, blue: 1.0),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<pieceCount, id: \.self) { i in
                    Piece(
                        color: colors[i % colors.count],
                        startX: Double.random(in: 0...geo.size.width),
                        size: Double.random(in: 6...11),
                        delay: Double.random(in: 0...0.5),
                        duration: Double.random(in: 1.4...2.4),
                        drift: Double.random(in: -40...40),
                        spin: Double.random(in: 1...4),
                        height: geo.size.height
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private struct Piece: View {
        let color: Color
        let startX: Double
        let size: Double
        let delay: Double
        let duration: Double
        let drift: Double
        let spin: Double
        let height: Double
        @State private var animate = false

        var body: some View {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: size, height: size * 0.6)
                .rotationEffect(.degrees(animate ? spin * 360 : 0))
                .opacity(animate ? 0 : 1)
                .position(x: startX + (animate ? drift : 0),
                          y: animate ? height + 30 : -30)
                .onAppear {
                    withAnimation(.easeIn(duration: duration).delay(delay)) {
                        animate = true
                    }
                }
        }
    }
}
