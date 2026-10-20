import XCTest
@testable import MacCam

final class ActivityLogTests: XCTestCase {
    func testRecordInsertsNewestFirstAndPersists() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("maccam-activity-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let log = ActivityLog(fileURL: url)
        let app = AppIdentity(bundleID: "us.zoom.xos", processName: "zoom.us", displayName: "Zoom")

        let exp = expectation(description: "record")
        log.record(ActivityEvent(app: app, action: .blocked, detail: "test"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(log.events.count, 1)
            XCTAssertEqual(log.events.first?.action, .blocked)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        // Allow async persist
        let persistExp = expectation(description: "persist")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            persistExp.fulfill()
        }
        wait(for: [persistExp], timeout: 1.0)

        let reloaded = ActivityLog(fileURL: url)
        let loadExp = expectation(description: "load")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(reloaded.events.count, 1)
            XCTAssertEqual(reloaded.events.first?.app.bundleID, "us.zoom.xos")
            loadExp.fulfill()
        }
        wait(for: [loadExp], timeout: 1.0)
    }

    func testRecentCapsCount() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("maccam-activity-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let log = ActivityLog(fileURL: url)
        let app = AppIdentity(bundleID: "com.apple.FaceTime", processName: "FaceTime")

        let exp = expectation(description: "many")
        for i in 0..<10 {
            log.record(ActivityEvent(app: app, action: .allowed, detail: "\(i)"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(log.recent(5).count, 5)
            XCTAssertEqual(log.events.count, 10)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
}
