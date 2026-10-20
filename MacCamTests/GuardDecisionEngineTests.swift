import XCTest
@testable import MacCam

final class GuardDecisionEngineTests: XCTestCase {
    func testUnlockedIgnores() {
        XCTAssertEqual(
            GuardDecisionEngine.action(mode: .unlocked, cameraOn: true, allowlistedUserLikely: false),
            .ignore
        )
    }

    func testLockedCameraOffIgnores() {
        XCTAssertEqual(
            GuardDecisionEngine.action(mode: .locked, cameraOn: false, allowlistedUserLikely: false),
            .ignore
        )
    }

    func testLockedDisablesHardware() {
        XCTAssertEqual(
            GuardDecisionEngine.action(mode: .locked, cameraOn: true, allowlistedUserLikely: false),
            .disableHardware
        )
    }

    func testAllowlistedLeftAlone() {
        XCTAssertEqual(
            GuardDecisionEngine.action(mode: .locked, cameraOn: true, allowlistedUserLikely: true),
            .allowSilently
        )
    }
}
