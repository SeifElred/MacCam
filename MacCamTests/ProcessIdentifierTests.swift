import AppKit
import XCTest
@testable import MacCam

final class ProcessIdentifierTests: XCTestCase {
    func testIgnoresSelfPID() {
        let score = ProcessIdentifier.score(
            bundleID: "us.zoom.xos",
            processName: "zoom.us",
            isFrontmost: true,
            isActive: true,
            activationPolicy: .regular,
            selfPID: 42,
            pid: 42
        )
        XCTAssertEqual(score, 0)
    }

    func testFrontmostKnownCameraAppScoresHighestPattern() {
        let zoomFront = ProcessIdentifier.score(
            bundleID: "us.zoom.xos",
            processName: "zoom.us",
            isFrontmost: true,
            isActive: true,
            activationPolicy: .regular,
            selfPID: 1,
            pid: 100
        )
        let safariBackground = ProcessIdentifier.score(
            bundleID: "com.apple.Safari",
            processName: "Safari",
            isFrontmost: false,
            isActive: false,
            activationPolicy: .regular,
            selfPID: 1,
            pid: 101
        )
        XCTAssertGreaterThan(zoomFront, safariBackground)
        XCTAssertGreaterThan(zoomFront, 150)
    }

    func testKnownCameraBonusApplied() {
        let faceTime = ProcessIdentifier.score(
            bundleID: "com.apple.FaceTime",
            processName: "FaceTime",
            isFrontmost: false,
            isActive: false,
            activationPolicy: .regular,
            selfPID: 1,
            pid: 55
        )
        let unknown = ProcessIdentifier.score(
            bundleID: "com.example.notes",
            processName: "Notes",
            isFrontmost: false,
            isActive: false,
            activationPolicy: .regular,
            selfPID: 1,
            pid: 56
        )
        XCTAssertGreaterThan(faceTime, unknown)
    }

    func testNameHeuristicWhenBundleMissing() {
        let cam = ProcessIdentifier.score(
            bundleID: "",
            processName: "USB Camera Helper",
            isFrontmost: false,
            isActive: false,
            activationPolicy: .regular,
            selfPID: 1,
            pid: 77
        )
        let other = ProcessIdentifier.score(
            bundleID: "",
            processName: "Calculator",
            isFrontmost: false,
            isActive: false,
            activationPolicy: .regular,
            selfPID: 1,
            pid: 78
        )
        XCTAssertGreaterThan(cam, other)
    }
}
