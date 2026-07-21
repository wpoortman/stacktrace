import XCTest
@testable import Stacktrace

final class AppConfigTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppConfig.devURLKey)
        UserDefaults.standard.removeObject(forKey: AIConfig.periodSummaryPromptKey)
        super.tearDown()
    }

    func testNormalizedURLAddsScheme() {
        XCTAssertEqual(AppConfig.normalizedURL("localhost:8000")?.absoluteString, "http://localhost:8000")
        XCTAssertEqual(AppConfig.normalizedURL("127.0.0.1:8000")?.absoluteString, "http://127.0.0.1:8000")
    }

    func testNormalizedURLKeepsValidScheme() {
        XCTAssertEqual(AppConfig.normalizedURL("https://api.example.com")?.absoluteString,
                       "https://api.example.com")
    }

    func testNormalizedURLRejectsJunk() {
        XCTAssertNil(AppConfig.normalizedURL(""))
        XCTAssertNil(AppConfig.normalizedURL("   "))
        XCTAssertNil(AppConfig.normalizedURL("ftp://nope.com"))
    }

    func testAdminURLDerivesFromDevDomain() {
        UserDefaults.standard.set("127.0.0.1:8000", forKey: AppConfig.devURLKey)
        // DEBUG builds honor the dev override.
        #if DEBUG
        XCTAssertEqual(AppConfig.adminURL.absoluteString, "http://127.0.0.1:8000/admin")
        XCTAssertEqual(AppConfig.pricingURL.absoluteString, "http://127.0.0.1:8000/pricing")
        #endif
    }

    func testPeriodSummaryPromptHasEditableDefault() {
        UserDefaults.standard.removeObject(forKey: AIConfig.periodSummaryPromptKey)
        XCTAssertEqual(AIConfig.periodSummaryPrompt, AIConfig.defaultPeriodSummaryPrompt)

        UserDefaults.standard.set("Write this as a weekly retrospective.",
                                  forKey: AIConfig.periodSummaryPromptKey)
        XCTAssertEqual(AIConfig.periodSummaryPrompt, "Write this as a weekly retrospective.")

        UserDefaults.standard.set("   \n", forKey: AIConfig.periodSummaryPromptKey)
        XCTAssertEqual(AIConfig.periodSummaryPrompt, AIConfig.defaultPeriodSummaryPrompt)
    }
}
