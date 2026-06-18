import XCTest
@testable import Stacktrace

@MainActor
final class DataStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stacktrace-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makeStore() -> DataStore { DataStore(directoryOverride: dir) }

    func testAddAndQueryEntry() {
        let store = makeStore()
        var e = ReportEntry(date: Date())
        e.title = "Wrote tests"
        store.upsert(e)
        XCTAssertEqual(store.entries(on: Date()).count, 1)
        XCTAssertEqual(store.entries(on: Date()).first?.title, "Wrote tests")
    }

    func testDeleteEntry() {
        let store = makeStore()
        let e = ReportEntry(date: Date())
        store.upsert(e)
        store.delete(e)
        XCTAssertTrue(store.entries(on: Date()).isEmpty)
    }

    func testTagsAddDedupRenameDelete() {
        let store = makeStore()
        store.addTag("ProjectX")
        store.addTag("projectx")            // case-insensitive dup
        XCTAssertEqual(store.tags, ["ProjectX"])
        store.renameTag("ProjectX", to: "ProjectY")
        XCTAssertEqual(store.tags, ["ProjectY"])
        store.deleteTag("ProjectY")
        XCTAssertTrue(store.tags.isEmpty)
    }

    func testTagRenamePropagatesToEntries() {
        let store = makeStore()
        var e = ReportEntry(date: Date())
        e.tags = ["A"]
        store.upsert(e)
        store.renameTag("A", to: "B")
        XCTAssertEqual(store.entries(on: Date()).first?.tags, ["B"])
    }

    func testDayRating() {
        let store = makeStore()
        XCTAssertNil(store.dayRating(for: Date()))
        store.setDayRating(8, for: Date())
        XCTAssertEqual(store.dayRating(for: Date()), 8)
        store.setDayRating(11, for: Date())   // clamps to 10
        XCTAssertEqual(store.dayRating(for: Date()), 10)
    }

    func testHolidayDetection() {
        let store = makeStore()
        XCTAssertFalse(store.isOnHoliday())
        store.addHoliday(start: Date(), end: Date())
        XCTAssertTrue(store.isOnHoliday())

        let dir2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("stacktrace-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir2) }
        let store2 = DataStore(directoryOverride: dir2)
        let future = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        store2.addHoliday(start: future, end: future)
        XCTAssertFalse(store2.isOnHoliday())
    }

    func testReorderPersists() {
        let store = makeStore()
        var a = ReportEntry(date: Date()); a.title = "A"
        var b = ReportEntry(date: Date()); b.title = "B"
        store.upsert(a); store.upsert(b)
        XCTAssertEqual(store.entries(on: Date()).map(\.title), ["A", "B"])
        store.moveEntries(on: Date(), from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(store.entries(on: Date()).map(\.title), ["B", "A"])
    }

    func testPersistenceAcrossInstances() {
        let store = makeStore()
        var e = ReportEntry(date: Date()); e.title = "Persisted"
        store.upsert(e)
        store.addTag("Keep")

        let reopened = DataStore(directoryOverride: dir)
        XCTAssertEqual(reopened.entries(on: Date()).first?.title, "Persisted")
        XCTAssertEqual(reopened.tags, ["Keep"])
    }

    func testActiveMinutes() {
        let store = makeStore()
        store.addExercise("Run", minutes: 20, on: Date())
        store.addExercise("Walk", minutes: 10, on: Date())
        XCTAssertEqual(store.activeMinutes(from: Date(), to: Date()), 30)
    }
}
