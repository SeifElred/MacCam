import XCTest
@testable import MacCam

final class CameraStackResetTests: XCTestCase {
    func testMatchesKnownDaemonsIncludingM1() {
        // Never soft-kill appleh13camerad — respawn powers the ISP / green LED.
        XCTAssertFalse(CameraStackReset.matchesDaemon("appleh13camerad"))
        XCTAssertFalse(CameraDisableHelper.daemonNames.contains("appleh13camerad"))
        XCTAssertTrue(CameraStackReset.matchesDaemon("VDCAssistant"))
        XCTAssertFalse(CameraStackReset.matchesDaemon("ContinuityCaptureAgent"))
        XCTAssertFalse(CameraStackReset.matchesDaemon("Finder"))
        XCTAssertFalse(CameraStackReset.matchesDaemon("zoom.us"))
    }
}
