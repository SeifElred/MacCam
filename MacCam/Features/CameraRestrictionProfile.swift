import Foundation

/// System-scoped camera ban — deepest software control without disabling SIP.
/// Combines:
/// 1) allowCamera=false (app restriction / NIST STIG approach)
/// 2) Device Access Allowed=false (CoreMediaIO — classic iSight disabler approach)
/// Blocks apps from opening the camera. LED is hardwired to ISP power — ban alone
/// does not guarantee the physical LED is dark if something still wakes appleh13camerad.
enum CameraRestrictionProfile {
    static let payloadIdentifier = "com.maccam.camera.disable"
    static let restrictionsIdentifier = "com.maccam.camera.disable.restrictions"
    static let cmioIdentifier = "com.maccam.camera.disable.cmio"

    /// Stable UUIDs so reinstall replaces the same profile.
    private static let outerUUID = "A1B2C3D4-E5F6-4789-A012-3456789ABCDE"
    private static let innerUUID = "B2C3D4E5-F6A7-4890-B123-456789ABCDEF"
    private static let cmioUUID = "C3D4E5F6-A7B8-4901-C234-56789ABCDEF0"

    static var profileXML: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        	<key>PayloadContent</key>
        	<array>
        		<dict>
        			<key>PayloadType</key>
        			<string>com.apple.applicationaccess</string>
        			<key>PayloadIdentifier</key>
        			<string>\(restrictionsIdentifier)</string>
        			<key>PayloadUUID</key>
        			<string>\(innerUUID)</string>
        			<key>PayloadVersion</key>
        			<integer>1</integer>
        			<key>PayloadEnabled</key>
        			<true/>
        			<key>PayloadDisplayName</key>
        			<string>MacCam Camera Restriction</string>
        			<key>allowCamera</key>
        			<false/>
        		</dict>
        		<dict>
        			<key>PayloadType</key>
        			<string>com.apple.coremediaio.support</string>
        			<key>PayloadIdentifier</key>
        			<string>\(cmioIdentifier)</string>
        			<key>PayloadUUID</key>
        			<string>\(cmioUUID)</string>
        			<key>PayloadVersion</key>
        			<integer>1</integer>
        			<key>PayloadEnabled</key>
        			<true/>
        			<key>PayloadDisplayName</key>
        			<string>MacCam CMIO Device Access</string>
        			<key>Device Access Allowed</key>
        			<false/>
        		</dict>
        	</array>
        	<key>PayloadDisplayName</key>
        	<string>MacCam Disable Camera</string>
        	<key>PayloadIdentifier</key>
        	<string>\(payloadIdentifier)</string>
        	<key>PayloadRemovalDisallowed</key>
        	<false/>
        	<key>PayloadScope</key>
        	<string>User</string>
        	<key>PayloadType</key>
        	<string>Configuration</string>
        	<key>PayloadUUID</key>
        	<string>\(outerUUID)</string>
        	<key>PayloadVersion</key>
        	<integer>1</integer>
        	<key>PayloadDescription</key>
        	<string>Camera ban for this user. Unlock / Use Camera removes it without an admin password. Re-lock asks you to Install once.</string>
        	<key>PayloadOrganization</key>
        	<string>MacCam</string>
        </dict>
        </plist>
        """
    }

    /// Writes the profile next to the root helper for privileged install.
    @discardableResult
    static func writeToSupportDirectory(_ directory: String = CameraDisableHelper.supportDir) -> URL? {
        let url = URL(fileURLWithPath: directory).appendingPathComponent("disable-camera.mobileconfig")
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: directory),
                withIntermediateDirectories: true
            )
        } catch {}
        do {
            try profileXML.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("maccam-disable-camera.mobileconfig")
            do {
                try profileXML.write(to: temp, atomically: true, encoding: .utf8)
                return temp
            } catch {
                return nil
            }
        }
    }

    /// Writes to the user's MacCam support folder (for open / Install).
    @discardableResult
    static func writeToUserSupportDirectory() -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacCam", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("disable-camera.mobileconfig")
        do {
            try profileXML.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static var cachedActive: (at: Date, value: Bool)?
    private static let cacheTTL: TimeInterval = 8

    /// Invalidate after install/remove so UI updates quickly.
    static func invalidateCache() {
        cachedActive = nil
    }

    /// Fast check: `allowCamera == false` via UserDefaults (no `profiles`/`osascript` spawn).
    /// Spawning those every tick was freezing the menu bar app.
    static var isActive: Bool {
        if let cached = cachedActive, Date().timeIntervalSince(cached.at) < cacheTTL {
            return cached.value
        }
        let active = readAllowCameraDisabled()
        cachedActive = (Date(), active)
        return active
    }

    private static func readAllowCameraDisabled() -> Bool {
        // Prefer MacCam helper state via prefs the root helper toggles (no profile cycle).
        let paths = [
            "/Library/Preferences/com.apple.applicationaccess.plist",
            "/Library/Preferences/com.apple.coremediaio.support.plist",
            "/Library/Managed Preferences/com.apple.applicationaccess.plist",
            NSHomeDirectory() + "/Library/Managed Preferences/com.apple.applicationaccess.plist"
        ]
        for path in paths {
            if let dict = NSDictionary(contentsOfFile: path) as? [String: Any] {
                if allowCameraIsDisabled(dict["allowCamera"]) { return true }
                if let cmio = dict["Device Access Allowed"] as? Bool, cmio == false { return true }
                if let cmio = dict["Device Access Allowed"] as? NSNumber, cmio.boolValue == false { return true }
            }
        }
        let suite = UserDefaults(suiteName: "com.apple.applicationaccess")
        return allowCameraIsDisabled(suite?.object(forKey: "allowCamera"))
    }

    private static func allowCameraIsDisabled(_ raw: Any?) -> Bool {
        guard let raw else { return false }
        if let flag = raw as? Bool { return flag == false }
        if let number = raw as? NSNumber { return number.boolValue == false }
        if let text = raw as? String { return text == "0" || text.lowercased() == "false" }
        return false
    }
}
