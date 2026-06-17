import SwiftUI

/// First-run walkthrough with a little quick setup at the end.
struct OnboardingView: View {
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage(NotificationManager.enabledKey) private var reminderEnabled = false

    @State private var step = 0
    @State private var launchAtLogin = LoginItem.isEnabled

    private struct Page { let symbol: String; let color: Color; let title: String; let body: String }
    private let pages = [
        Page(symbol: "square.stack.3d.up.fill", color: .blue,
             title: "Welcome to Stacktrace",
             body: "Show progress, not hours. A quick daily log of what you did and how it went — turned into clean reports."),
        Page(symbol: "square.and.pencil", color: .green,
             title: "Log your day",
             body: "Capture full entries, one-tap wins or setbacks, a mood check-in, and exercise. Drag to reorder; nothing about clocking time."),
        Page(symbol: "flame.fill", color: .orange,
             title: "Build the habit",
             body: "Streaks, a contribution graph, movement routines, reminders, and an end-of-day score keep it motivating."),
        Page(symbol: "doc.richtext", color: .indigo,
             title: "Report with ease",
             body: "Export any period to PDF or copy as Markdown for standups. Connect your calendar to reflect on meetings too."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if step < pages.count {
                page(pages[step])
            } else {
                quickSetup
            }
            Spacer(minLength: 0)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                pageDots
                Spacer()
                Button(step < pages.count ? "Next" : "Get Started") {
                    if step < pages.count { step += 1 } else { didOnboard = true }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 520, height: 460)
        .interactiveDismissDisabled(true)
    }

    private func page(_ p: Page) -> some View {
        VStack(spacing: 16) {
            Image(systemName: p.symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(p.color, in: RoundedRectangle(cornerRadius: 20))
            Text(p.title).font(.title.bold())
            Text(p.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(.horizontal, 30)
    }

    private var quickSetup: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 20))
            Text("Quick setup").font(.title.bold())
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Daily reminder to log your day", isOn: $reminderEnabled)
                    .onChange(of: reminderEnabled) { _, _ in NotificationManager.refresh() }
                Toggle("Launch Stacktrace at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, want in
                        LoginItem.set(want); launchAtLogin = LoginItem.isEnabled
                    }
            }
            .frame(maxWidth: 360)
            Text("You can change everything later in Settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 30)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0...pages.count, id: \.self) { i in
                Circle()
                    .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }
}
