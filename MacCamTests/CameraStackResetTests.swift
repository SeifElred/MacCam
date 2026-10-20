import XCTest
@testable import MacCam

final class CameraStackResetTests: XCTestCase {
    func testMatchesKnownDaemonsIncludingM1() {
        XCTAssertTrue(CameraStackReset.matchesDaemon("appleh13camerad"))
        XCTAssertTrue(CameraStackReset.matchesDaemon("VDCAssistant"))
        XCTAssertTrue(CameraDisableHelper.daemonNames.contains("appleh13camerad"))
        XCTAssertFalse(CameraStackReset.matchesDaemon("Finder"))
        XCTAssertFalse(CameraStackReset.matchesDaemon("zoom.us"))
    }
}
