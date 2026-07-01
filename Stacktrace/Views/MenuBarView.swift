import SwiftUI
import AppKit

/// Compact quick-capture shown from the menu bar. Log today's mood or a quick
/// win / setback without opening the main window.
struct MenuBarView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.openWindow) private var openWindow

    @State private var text = ""
    @State private var kind = "win"
    @State private var justLogged = false

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var todayCount: Int { store.entries(on: today).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("How did today go?").font(.headline)
                Spacer()
                if justLogged {
                    Label("Logged", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                        .transition(.opacity)
                }
            }

            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { m in
                    Button {
                        store.addCheckin(mood: m); flash()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: MoodScale.symbol(m)).font(.title3)
                            Text(MoodScale.label(m)).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(MoodColor.color(for: m).opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(MoodColor.color(for: m))
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("", selection: $kind) {
                Text("Win").tag("win")
                Text("Setback").tag("fail")
                Text("Note").tag("note")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addQuick)
                Button("Add", action: addQuick)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            HStack {
                Text("\(todayCount) logged today")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open Stacktrace") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var placeholder: String {
        switch kind {
        case "win": return "A small win…"
        case "fail": return "A setback…"
        default: return "What did you do?"
        }
    }

    private func addQuick() {
        store.addQuick(text, kind: kind, on: today)
        text = ""
        flash()
    }

    private func flash() {
        withAnimation { justLogged = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { justLogged = false }
        }
    }
}
