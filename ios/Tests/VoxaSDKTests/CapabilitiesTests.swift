import XCTest
@testable import VoxaSDK

final class CapabilitiesTests: XCTestCase {
    func testNonJwtIsClientProfile() {
        let p = TokenProfile.from(token: "not-a-jwt")
        XCTAssertEqual(p.role, "CLIENT")
        XCTAssertTrue(p.can(.chat))
        XCTAssertTrue(p.can(.joinCall))
        XCTAssertFalse(p.can(.transcript))
        XCTAssertFalse(p.can(.monitor))
    }

    func testAgentRoleDerivesAgentCapabilities() {
        // A JWT with payload {"role":"AGENT"} (signature irrelevant for client-side gating).
        let header = Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8).base64EncodedString()
        let payload = Data(#"{"role":"AGENT","tenantId":"t1","userId":"u1"}"#.utf8).base64EncodedString()
        let token = "\(header).\(payload).sig"
        let p = TokenProfile.from(token: token)
        XCTAssertEqual(p.role, "AGENT")
        XCTAssertEqual(p.tenantId, "t1")
        XCTAssertTrue(p.can(.transcript))
        XCTAssertTrue(p.can(.presence))
        XCTAssertFalse(p.can(.monitor)) // supervisor-only
    }
}
