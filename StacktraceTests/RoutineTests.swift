import XCTest
@testable import Stacktrace

final class RoutineTests: XCTestCase {
    func testHourlySlotsEveryHour() {
        var r = Routine(name: "Stretch")
        r.cadence = "hourly"; r.startHour = 9; r.endHour = 12
        XCTAssertEqual(r.slots.map(\.hour), [9, 10, 11, 12])
        XCTAssertEqual(r.dailyTarget, 4)
    }

    func testMaxPerDayCapsSlots() {
        var r = Routine(name: "Water")
        r.cadence = "hourly"; r.startHour = 8; r.endHour = 20  // would be 13 slots
        r.maxPerDay = 5
        XCTAssertEqual(r.slots.map(\.hour), [8, 9, 10, 11, 12])
        XCTAssertEqual(r.dailyTarget, 5)
    }

    func testMaxPerDayIgnoredWhenAboveWindow() {
        var r = Routine(name: "Stretch")
        r.cadence = "hourly"; r.startHour = 9; r.endHour = 11
        r.maxPerDay = 10  // window only yields 3
        XCTAssertEqual(r.slots.map(\.hour), [9, 10, 11])
    }

    func testHourlyInterval() {
        var r = Routine(name: "Walk")
        r.cadence = "hourly"; r.startHour = 9; r.endHour = 17; r.hourStep = 2
        XCTAssertEqual(r.slots.map(\.hour), [9, 11, 13, 15, 17])
    }

    func testStartMinuteAppliesToSlots() {
        var r = Routine(name: "Water")
        r.cadence = "hourly"; r.startHour = 9; r.endHour = 11; r.startMinute = 30
        // 9:30 and 10:30 fit; 11:30 exceeds 11:00.
        XCTAssertEqual(r.slots.map(\.hour), [9, 10])
        XCTAssertEqual(r.slots.map(\.minute), [30, 30])
        XCTAssertTrue(r.cadenceLabel.contains("9:30"))
    }

    func testDailyTargetIsOne() {
        var r = Routine(name: "Journal")
        r.cadence = "daily"
        XCTAssertEqual(r.dailyTarget, 1)
        XCTAssertEqual(r.slots.count, 1)
    }

    func testRunsOnWeekdays() {
        let cal = Calendar.current
        // Find a known Monday.
        var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 15 // Mon
        let monday = cal.date(from: comps)!
        let tuesday = cal.date(byAdding: .day, value: 1, to: monday)!

        var r = Routine(name: "Mon only")
        r.weekdays = [2] // Monday
        XCTAssertTrue(r.runsOn(monday))
        XCTAssertFalse(r.runsOn(tuesday))

        var every = Routine(name: "Every")
        every.weekdays = nil
        XCTAssertTrue(every.runsOn(tuesday))
    }
}

final class ReportEntryTests: XCTestCase {
    func testQuickFlags() {
        var win = ReportEntry(date: Date()); win.quickKind = "win"; win.detail = "shipped"
        XCTAssertTrue(win.isQuick)
        XCTAssertFalse(win.isExercise)
        XCTAssertFalse(win.isMeeting)
        XCTAssertFalse(win.isCheckin)
    }

    func testCheckinFlag() {
        var c = ReportEntry(date: Date()); c.mood = 4
        XCTAssertTrue(c.isCheckin)
        c.title = "Has title"
        XCTAssertFalse(c.isCheckin)   // title present → full entry
    }

    func testExerciseFlag() {
        var e = ReportEntry(date: Date()); e.exercise = "Run"; e.durationMinutes = 20
        XCTAssertTrue(e.isExercise)
    }

    func testMeetingFlag() {
        var m = ReportEntry(date: Date()); m.eventID = "evt-1"; m.title = "Standup"
        XCTAssertTrue(m.isMeeting)
    }
}
