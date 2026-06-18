import XCTest
@testable import Stacktrace

final class TeamTests: XCTestCase {
    func testQualityFactorBounds() {
        XCTAssertEqual(TeamMetrics.qualityFactor(wellbeing: 5, dayScore: nil), 1.0, accuracy: 0.001)
        XCTAssertEqual(TeamMetrics.qualityFactor(wellbeing: 1, dayScore: nil), 0.7, accuracy: 0.001)
        // Falls back to dayScore when wellbeing missing.
        XCTAssertEqual(TeamMetrics.qualityFactor(wellbeing: nil, dayScore: 10), 1.0, accuracy: 0.001)
        // Never below 0.7 or above 1.0.
        let f = TeamMetrics.qualityFactor(wellbeing: nil, dayScore: nil)
        XCTAssertGreaterThanOrEqual(f, 0.7)
        XCTAssertLessThanOrEqual(f, 1.0)
    }

    @MainActor
    func testDailyMetricFromStore() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("st-team-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DataStore(directoryOverride: dir)

        store.addQuick("win a", kind: "win", on: Date())
        store.addQuick("win b", kind: "win", on: Date())
        store.addQuick("setback", kind: "fail", on: Date())
        store.setDayRating(7, for: Date())

        let m = TeamMetrics.dailyMetric(from: store, on: Date())
        XCTAssertEqual(m.wins, 2)
        XCTAssertEqual(m.losses, 1)
        XCTAssertEqual(m.dayScore, 7)
        XCTAssertEqual(m.entries, 3)
        XCTAssertNotNil(m.wellbeing)   // wins=5, fail=2 carry implicit moods
    }

    func testMockAPIReturnsRate() async throws {
        let api = MockTeamAPI()
        let profile = try await api.me()
        XCTAssertEqual(profile.role, "Developer")
        let rate = try await api.push(DailyMetric(date: "2026-06-18", entries: 1,
                                                  wins: 1, losses: 0, wellbeing: 5, dayScore: 10))
        XCTAssertEqual(rate, 8000)   // top quality → full base rate
    }
}
