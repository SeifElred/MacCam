import XCTest
@testable import MacCam

final class CameraRestrictionProfileTests: XCTestCase {
    func testProfileContainsAllowCameraFalse() {
        let xml = CameraRestrictionProfile.profileXML
        XCTAssertTrue(xml.contains("com.apple.applicationaccess"))
        XCTAssertTrue(xml.contains("allowCamera"))
        XCTAssertTrue(xml.contains("<false/>"))
        XCTAssertTrue(xml.contains(CameraRestrictionProfile.payloadIdentifier))
    }

    func testWriteProfileToTemp() {
        let url = CameraRestrictionProfile.writeToSupportDirectory(
            FileManager.default.temporaryDirectory.path
        )
        XCTAssertNotNil(url)
        if let url {
            let text = try? String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(text, CameraRestrictionProfile.profileXML)
        }
    }
}
