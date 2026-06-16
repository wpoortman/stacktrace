import SwiftUI

/// Movement & exercise hub: log exercise, see active minutes, and check off
/// your routines for today.
struct ActivityView: View {
    @EnvironmentObject private var store: DataStore
    @State private var showExercise = false

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var weekActiveMinutes: Int {
        let week = Calendar.current.weekInterval(for: Date())
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: week.end) ?? week.start
        return store.activeMinutes(from: week.start, to: lastDay)
    }

    private var todayExercises: [ReportEntry] {
        store.entries(on: today).filter { $0.isExercise }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                exerciseCard
                if !store.routines.isEmpty { routinesCard }
                else { routinesEmpty }
            }
            .padding(24)
        }
        .navigationTitle("Activity")
        .sheet(isPresented: $showExercise) {
            ExerciseWizard(day: today)
        }
    }

    private var exerciseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Exercise", systemImage: "figure.run")
                    .font(.headline)
                Spacer()
                Text("\(weekActiveMinutes) min this week")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button {
                showExercise = true
            } label: {
                Label("Log exercise", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            if todayExercises.isEmpty {
                Text("Nothing logged today.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(todayExercises) { e in
                    ExerciseRow(entry: e) { store.delete(e) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12)))
    }

    private var routinesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Move a little", systemImage: "figure.walk")
                .font(.headline)
            ForEach(store.routines) { routine in
                RoutineRow(routine: routine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12)))
    }

    private var routinesEmpty: some View {
        ContentUnavailableView("No routines yet", systemImage: "figure.walk",
            description: Text("Add movement routines in Settings → Routines to track them here."))
    }
}
