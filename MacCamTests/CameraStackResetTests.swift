import XCTest
@testable import MacCam

final class CameraStackResetTests: XCTestCase {
    func testMatchesKnownDaemons() {
        XCTAssertTrue(CameraStackReset.matchesDaemon("appleh13camerad"))
        XCTAssertTrue(CameraStackReset.matchesDaemon("VDCAssistant"))
        XCTAssertTrue(CameraStackReset.matchesDaemon("AppleCameraAssistant"))
        XCTAssertFalse(CameraStackReset.matchesDaemon("Finder"))
        XCTAssertFalse(CameraStackReset.matchesDaemon("zoom.us"))
        XCTAssertFalse(CameraStackReset.matchesDaemon("Google Chrome"))
    }
}
