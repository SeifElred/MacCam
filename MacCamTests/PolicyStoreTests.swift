import XCTest
@testable import MacCam

final class PolicyStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: PolicyStore!

    override func setUp() {
        super.setUp()
        suiteName = "com.maccam.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = PolicyStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testUnknownByDefault() {
        let app = AppIdentity(bundleID: "com.example.cam", processName: "CamApp")
        XCTAssertEqual(store.decision(for: app), .unknown)
    }

    func testAllowlistAndBlocklistAreExclusive() {
        let app = AppIdentity(bundleID: "us.zoom.xos", processName: "zoom.us")
        store.addToAllowlist(app)
        XCTAssertEqual(store.decision(for: app), .allowlisted)

        store.addToBlocklist(app)
        XCTAssertEqual(store.decision(for: app), .blocklisted)
        XCTAssertFalse(store.allowlist.contains(where: { $0.bundleID == app.bundleID }))
    }

    func testMatchByBundleIDIgnoringProcessName() {
        let a = AppIdentity(bundleID: "com.apple.FaceTime", processName: "FaceTime")
        let b = AppIdentity(bundleID: "com.apple.FaceTime", processName: "FaceTime Helper")
        store.addToAllowlist(a)
        XCTAssertEqual(store.decision(for: b), .allowlisted)
    }

    func testMatchByProcessNameWhenBundleEmpty() {
        let a = AppIdentity(bundleID: "", processName: "MysteryCam")
        let b = AppIdentity(bundleID: "", processName: "mysterycam")
        store.addToBlocklist(a)
        XCTAssertEqual(store.decision(for: b), .blocklisted)
    }

    func testPersistenceRoundTrip() {
        let app = AppIdentity(bundleID: "com.hnc.Discord", processName: "Discord")
        store.addToBlocklist(app)

        let reloaded = PolicyStore(defaults: defaults)
        XCTAssertEqual(reloaded.decision(for: app), .blocklisted)
        XCTAssertEqual(reloaded.blocklist.count, 1)
    }

    func testClearLists() {
        let app = AppIdentity(bundleID: "com.apple.Safari", processName: "Safari")
        store.addToAllowlist(app)
        store.clearAllowlist()
        XCTAssertEqual(store.allowlist.count, 0)
        XCTAssertEqual(store.decision(for: app), .unknown)
    }
}
