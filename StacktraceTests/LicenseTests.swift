import XCTest
@testable import Stacktrace

final class LicenseTests: XCTestCase {
    private func sample() -> Entitlement {
        Entitlement(key: "K", plan: .team, seats: 50, deviceID: "dev",
                    expires: Date().addingTimeInterval(1000))
    }

    func testSignVerifyRoundTrip() {
        let signed = LicenseCrypto.sign(sample())
        XCTAssertTrue(LicenseCrypto.verify(signed))
    }

    func testTamperedPayloadFails() {
        var signed = LicenseCrypto.sign(sample())
        signed.payload.seats = 9999   // tamper after signing
        XCTAssertFalse(LicenseCrypto.verify(signed))
    }

    func testMockServicePlans() async throws {
        let svc = MockLicenseService()
        let team = try await svc.activate(key: "TEAM-DEV", deviceID: "d")
        XCTAssertEqual(team.payload.plan, .team)
        XCTAssertEqual(team.payload.seats, 50)
        XCTAssertTrue(LicenseCrypto.verify(team))

        let indiv = try await svc.activate(key: "HELLO", deviceID: "d")
        XCTAssertEqual(indiv.payload.plan, .individual)
        XCTAssertEqual(indiv.payload.seats, 1)
    }

    func testEmptyKeyThrows() async {
        let svc = MockLicenseService()
        do {
            _ = try await svc.activate(key: "  ", deviceID: "d")
            XCTFail("expected error")
        } catch {
            // expected
        }
    }
}
