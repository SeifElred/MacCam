import XCTest
@testable import MacCam

final class CameraStackResetTests: XCTestCase {
    func testMatchesKnownDaemons() {
        XCTAssertTrue(CameraStackReset.matchesDaemon("appleh13camerad"))
        XCTAssertTrue(CameraStackReset.matchesDaemon("VDCAssistant"))
        XCTAssertTrue(CameraStackReset.matchesDaemon("AppleCameraAssistant"))
        XCTAssertFalse(CameraStackReset.matchesDaemon("Finder"))
    }

    func testMatchesHelpers() {
        XCTAssertTrue(CameraStackReset.matchesHelper("Google Chrome Helper"))
        XCTAssertTrue(CameraStackReset.matchesHelper("Zoom.us"))
        XCTAssertFalse(CameraStackReset.matchesHelper("Notes"))
    }
}
