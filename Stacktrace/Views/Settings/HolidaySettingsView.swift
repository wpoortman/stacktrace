import SwiftUI

/// Add time-off periods. While a holiday is active the app pauses reminders,
/// rating prompts, meeting prompts, and automatic export.
struct HolidaySettingsView: View {
    @EnvironmentObject private var store: DataStore
    @State private var start = Date()
    @State private var end = Date()

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    var body: some View {
        Form {
            Section {
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                Button("Add holiday") {
                    store.addHoliday(start: start, end: end)
                }
                .buttonStyle(.borderedProminent)
            } header: {
                Text("Add time off")
            } footer: {
                Text("During a holiday, Stacktrace stops nudging — no reminders, no rating or meeting prompts, no auto-export. You can still log if you want to.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !store.holidays.isEmpty {
                Section("Scheduled") {
                    ForEach(store.holidays) { h in
                        HStack {
                            Image(systemName: "beach.umbrella.fill").foregroundStyle(.teal)
                            Text("\(Self.df.string(from: h.start)) – \(Self.df.string(from: h.end))")
                            if store.isOnHoliday() , h.start <= Date(), Date() <= h.end {
                                Text("active").font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.teal.opacity(0.2), in: Capsule())
                            }
                            Spacer()
                            Button(role: .destructive) { store.deleteHoliday(h) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
