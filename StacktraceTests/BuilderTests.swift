import XCTest
@testable import Stacktrace

final class BuilderTests: XCTestCase {
    private func entries() -> [ReportEntry] {
        var full = ReportEntry(date: Date()); full.title = "Shipped feature"
        var win = ReportEntry(date: Date()); win.quickKind = "win"; win.detail = "Fixed the bug"
        var meeting = ReportEntry(date: Date()); meeting.eventID = "e"; meeting.title = "Standup"
        return [full, win, meeting]
    }

    func testHTMLContainsContentAndIcons() {
        let html = ReportHTMLBuilder.html(entries: entries(), from: Date(), to: Date())
        XCTAssertTrue(html.contains("Shipped feature"))
        XCTAssertTrue(html.contains("Fixed the bug"))
        XCTAssertTrue(html.contains("🎉"))   // win icon
        XCTAssertTrue(html.contains("📅"))   // meeting icon
    }

    func testQuickItemNotTitledUntitled() {
        var win = ReportEntry(date: Date()); win.quickKind = "win"; win.detail = "A win"
        let html = ReportHTMLBuilder.html(entries: [win], from: Date(), to: Date())
        XCTAssertFalse(html.contains("Untitled"))
    }

    func testMarkdownStructure() {
        let md = ReportMarkdownBuilder.markdown(entries: entries(), from: Date(), to: Date())
        XCTAssertTrue(md.contains("# Work Report"))
        XCTAssertTrue(md.contains("Shipped feature"))
        XCTAssertTrue(md.contains("🎉 Fixed the bug"))
    }

    func testEmptyPeriod() {
        let html = ReportHTMLBuilder.html(entries: [], from: Date(), to: Date())
        XCTAssertTrue(html.contains("No entries"))
    }
}

final class AutoExportTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AutoExport.frequencyKey)
        super.tearDown()
    }

    @MainActor
    func testMonthlyPeriodIsPreviousMonth() {
        UserDefaults.standard.set("monthly", forKey: AutoExport.frequencyKey)
        let cal = Calendar.current
        let scheduled = cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let (start, end, _) = AutoExport.period(endingAt: scheduled)
        XCTAssertEqual(cal.component(.month, from: start), 2)
        XCTAssertEqual(cal.component(.day, from: start), 1)
        XCTAssertEqual(cal.component(.month, from: end), 2)
        XCTAssertEqual(cal.component(.day, from: end), 28)
    }

    @MainActor
    func testWeeklyPeriodIsSevenDays() {
        UserDefaults.standard.set("weekly", forKey: AutoExport.frequencyKey)
        let cal = Calendar.current
        let scheduled = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let (start, end, _) = AutoExport.period(endingAt: scheduled)
        let days = cal.dateComponents([.day], from: start, to: end).day
        XCTAssertEqual(days, 6)   // inclusive 7-day span
        XCTAssertLessThan(end, scheduled)
    }
}
