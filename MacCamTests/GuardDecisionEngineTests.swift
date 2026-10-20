import XCTest
@testable import MacCam

final class GuardDecisionEngineTests: XCTestCase {
    func testUnlockedIgnoresCamera() {
        let action = GuardDecisionEngine.action(
            mode: .unlocked,
            cameraOn: true,
            alreadyPrompting: false,
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
            alreadyPrompting: false,
            sessionAlreadyHandled: false,
            allowOnceActive: false,
            policy: .unknown
        )
        XCTAssertEqual(action, .ignore)
    }

    func testLockedUnknownFreezesAndPrompts() {
        let action = GuardDecisionEngine.action(
            mode: .locked,
            cameraOn: true,
            alreadyPrompting: false,
            sessionAlreadyHandled: false,
            allowOnceActive: false,
            policy: .unknown
        )
        XCTAssertEqual(action, .freezeAndPrompt)
    }

    func testAllowlistSilentAllow() {
        let action = GuardDecisionEngine.action(
            mode: .locked,
            cameraOn: true,
            alreadyPrompting: false,
            sessionAlreadyHandled: false,
            allowOnceActive: false,
            policy: .allowlisted
        )
        XCTAssertEqual(action, .allowSilently)
    }

    func testBlocklistSilentBlock() {
        let action = GuardDecisionEngine.action(
            mode: .locked,
            cameraOn: true,
            alreadyPrompting: false,
            sessionAlreadyHandled: false,
            allowOnceActive: false,
            policy: .blocklisted
        )
        XCTAssertEqual(action, .blockSilently)
    }

    func testAlreadyPromptingDoesNotRetrigger() {
        let action = GuardDecisionEngine.action(
            mode: .locked,
            cameraOn: true,
            alreadyPrompting: true,
            sessionAlreadyHandled: false,
            allowOnceActive: false,
            policy: .unknown
        )
        XCTAssertEqual(action, .ignore)
    }

    func testAllowOnceSessionSkips() {
        let action = GuardDecisionEngine.action(
            mode: .locked,
            cameraOn: true,
            alreadyPrompting: false,
            sessionAlreadyHandled: false,
            allowOnceActive: true,
            policy: .unknown
        )
        XCTAssertEqual(action, .ignore)
    }

    func testTimeoutDetection() {
        let now = Date()
        XCTAssertFalse(
            GuardDecisionEngine.timedOut(isPrompting: true, deadline: now.addingTimeInterval(10), now: now)
        )
        XCTAssertTrue(
            GuardDecisionEngine.timedOut(isPrompting: true, deadline: now.addingTimeInterval(-1), now: now)
        )
        XCTAssertFalse(
            GuardDecisionEngine.timedOut(isPrompting: false, deadline: now.addingTimeInterval(-1), now: now)
        )
    }
}
