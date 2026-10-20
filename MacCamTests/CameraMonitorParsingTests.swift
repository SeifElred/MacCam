import XCTest
@testable import MacCam

final class CameraMonitorParsingTests: XCTestCase {
    /// Smoke test: enumerating devices must not crash (may return empty in CI without camera).
    func testDeviceEnumerationDoesNotCrash() {
        let devices = CameraMonitor.allDeviceIDs()
        XCTAssertGreaterThanOrEqual(devices.count, 0)
        // Calling status APIs for each device should be safe.
        for id in devices {
            _ = CameraMonitor.isRunningSomewhere(id)
            _ = CameraMonitor.isBuiltIn(id)
            _ = CameraMonitor.isLikelyVirtualOnly(id)
            _ = CameraMonitor.transportType(id)
        }
    }

    func testIsAnyCameraRunningCallable() {
        // Result depends on hardware; we only assert it returns without trapping.
        _ = CameraMonitor.isAnyCameraRunning(includeExternal: true)
        _ = CameraMonitor.isAnyCameraRunning(includeExternal: false)
    }
}
