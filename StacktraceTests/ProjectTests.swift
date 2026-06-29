import XCTest
@testable import Stacktrace

@MainActor
final class ProjectTests: XCTestCase {
    private func makeStore() -> DataStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("st-proj-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return DataStore(directoryOverride: dir)
    }

    func testCrud() {
        let store = makeStore()
        let p = Project(name: "Acme", details: "Client work")
        store.upsertProject(p)
        XCTAssertEqual(store.projects.count, 1)
        XCTAssertEqual(store.projectName(p.id), "Acme")

        var edited = p; edited.name = "Acme Co"
        store.upsertProject(edited)
        XCTAssertEqual(store.projects.count, 1)
        XCTAssertEqual(store.projectName(p.id), "Acme Co")
    }

    func testAttachAndFilter() {
        let store = makeStore()
        let p = Project(name: "Acme")
        store.upsertProject(p)
        var e = ReportEntry(date: Date()); e.title = "Did work"; e.projectID = p.id
        store.upsert(e)
        var other = ReportEntry(date: Date()); other.title = "Other"
        store.upsert(other)

        let filtered = store.entries(forProject: p.id, from: Date(), to: Date())
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.title, "Did work")
    }

    func testDeleteProjectClearsLinks() {
        let store = makeStore()
        let p = Project(name: "Acme")
        store.upsertProject(p)
        var e = ReportEntry(date: Date()); e.projectID = p.id
        store.upsert(e)

        store.deleteProject(p)
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertNil(store.entries(on: Date()).first?.projectID)
    }
}
