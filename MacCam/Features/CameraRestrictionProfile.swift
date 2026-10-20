import Foundation

/// System-scoped camera ban — deepest software control without disabling SIP.
/// Combines:
/// 1) allowCamera=false (app restriction / NIST STIG approach)
/// 2) Device Access Allowed=false (CoreMediaIO — classic iSight disabler approach)
/// LED is hardwired to camera power; this is what keeps the sensor unpowered when idle.
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
        	<string>System</string>
        	<key>PayloadType</key>
        	<string>Configuration</string>
        	<key>PayloadUUID</key>
        	<string>\(outerUUID)</string>
        	<key>PayloadVersion</key>
        	<integer>1</integer>
        	<key>PayloadDescription</key>
        	<string>System camera ban: apps cannot use the camera and CoreMediaIO device access is denied. Remove this profile (or Unlock MacCam) when you need FaceTime/Photo Booth.</string>
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

    /// Best-effort check whether our restriction profile is installed.
    static var isActive: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/profiles")
        process.arguments = ["list", "-all"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            if text.contains(payloadIdentifier) { return true }
        } catch {}

        // Fallback: restriction defaults suite (NIST check).
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        check.arguments = [
            "-l", "JavaScript", "-e",
            "$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess').objectForKey('allowCamera').js"
        ]
        let out = Pipe()
        check.standardOutput = out
        check.standardError = FileHandle.nullDevice
        do {
            try check.run()
            check.waitUntilExit()
            let raw = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw == "false"
        } catch {
            return false
        }
    }
}
