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

    func testZipSelectedExports() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = dir.appendingPathComponent("First.pdf")
        let second = dir.appendingPathComponent("Second.pdf")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)

        let destination = dir.appendingPathComponent("Selected.zip")
        try ExportStore.zip(urls: [first, second], to: destination)

        let zip = try Data(contentsOf: destination)
        XCTAssertTrue(zip.starts(with: Data([0x50, 0x4b, 0x03, 0x04])))
        XCTAssertTrue(zip.contains(Data([0x50, 0x4b, 0x01, 0x02])))
        let zipText = String(decoding: zip, as: UTF8.self)
        XCTAssertTrue(zipText.contains("First.pdf"))
        XCTAssertTrue(zipText.contains("Second.pdf"))
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
