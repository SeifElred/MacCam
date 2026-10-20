import XCTest
@testable import MacCam

final class GuardDecisionEngineTests: XCTestCase {
    func testUnlockedIgnoresCamera() {
        let action = GuardDecisionEngine.action(
            mode: .unlocked,
            cameraOn: true,
            sessionAlreadyHandled: false,
            allowOnceActive: false,
            policy: .unknown
        )
        XCTAssertEqual(action, .ignore)
    }

    func testLockedCameraOffIgnores() {
        let action = GuardDecisionEngine.action(
            mode: .locked,
            cameraOn: false,
            sessionAlreadyHandled: false,
            allowOnceActive: false,
            policy: .unknown
        )
        XCTAssertEqual(action, .ignore)
    }

    func testLockedUnknownBlocksImmediately() {
        let action = GuardDecisionEngine.action(
            mode: .locked,
            cameraOn: true,
            sessionAlreadyHandled: false,
            allowOnceActive: false,
            policy: .unknown
        )
        XCTAssertEqual(action, .blockNow)
    }

    func testAllowlistSilentAllow() {
        let action = GuardDecisionEngine.action(
            mode: .locked,
            cameraOn: true,
            sessionAlreadyHandled: false,
            allowOnceActive: false,
            policy: .allowlisted
        )
        XCTAssertEqual(action, .allowSilently)
    }

    func testBlocklistBlocksNow() {
        let action = GuardDecisionEngine.action(
            mode: .locked,
            cameraOn: true,
            sessionAlreadyHandled: false,
            allowOnceActive: false,
            policy: .blocklisted
        )
        XCTAssertEqual(action, .blockNow)
    }

    func testAllowOnceSessionSkips() {
        let action = GuardDecisionEngine.action(
            mode: .locked,
            cameraOn: true,
            sessionAlreadyHandled: false,
            allowOnceActive: true,
            policy: .unknown
        )
        XCTAssertEqual(action, .ignore)
    }

    func testAlreadyHandledSkips() {
        let action = GuardDecisionEngine.action(
            mode: .locked,
            cameraOn: true,
            sessionAlreadyHandled: true,
            allowOnceActive: false,
            policy: .unknown
        )
        XCTAssertEqual(action, .ignore)
    }
}
