import XCTest
@testable import Stacktrace

/// Guards that the JSON the MCP server writes is read correctly by the app.
@MainActor
final class MCPCompatTests: XCTestCase {
    func testLoadsMCPWrittenStore() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("st-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Shaped exactly like mcp/index.js output (ISO8601, no fractional secs).
        let json = """
        {
          "entries": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "date": "2026-06-18T22:00:00Z",
              "title": "", "detail": "shipped MCP",
              "wentWell": "", "wentBad": "", "tags": [],
              "createdAt": "2026-06-19T21:35:53Z",
              "quickKind": "win", "mood": 5
            },
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "date": "2026-06-18T22:00:00Z",
              "title": "Wrote server", "detail": "",
              "wentWell": "", "wentBad": "", "tags": ["mcp"],
              "createdAt": "2026-06-19T21:35:54Z", "mood": 4
            }
          ],
          "tags": ["mcp"],
          "routines": [], "routineLogs": [],
          "dayRatings": [
            { "id": "33333333-3333-3333-3333-333333333333",
              "day": "2026-06-18T22:00:00Z", "score": 8, "at": "2026-06-19T21:35:55Z" }
          ],
          "holidays": []
        }
        """
        try json.write(to: dir.appendingPathComponent("data.json"), atomically: true, encoding: .utf8)

        let store = DataStore(directoryOverride: dir)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.tags, ["mcp"])
        XCTAssertTrue(store.entries.contains { $0.quickKind == "win" && $0.detail == "shipped MCP" })
        XCTAssertTrue(store.entries.contains { $0.title == "Wrote server" && $0.mood == 4 })
        XCTAssertEqual(store.dayRatings.first?.score, 8)
    }
}
