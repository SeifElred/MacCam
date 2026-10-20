import Foundation

/// Generates the macOS configuration profile that sets allowCamera=false.
/// This is the deepest safe “no camera” control on M1 Pro (OS policy, not LED bit-banging).
enum CameraRestrictionProfile {
    static let payloadIdentifier = "com.maccam.camera.disable"
    static let restrictionsIdentifier = "com.maccam.camera.disable.restrictions"

    /// Stable UUIDs so reinstall replaces the same profile.
    private static let outerUUID = "A1B2C3D4-E5F6-4789-A012-3456789ABCDE"
    private static let innerUUID = "B2C3D4E5-F6A7-4890-B123-456789ABCDEF"

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
        	</array>
        	<key>PayloadDisplayName</key>
        	<string>MacCam Disable Camera</string>
        	<key>PayloadIdentifier</key>
        	<string>\(payloadIdentifier)</string>
        	<key>PayloadRemovalDisallowed</key>
        	<false/>
        	<key>PayloadType</key>
        	<string>Configuration</string>
        	<key>PayloadUUID</key>
        	<string>\(outerUUID)</string>
        	<key>PayloadVersion</key>
        	<integer>1</integer>
        	<key>PayloadDescription</key>
        	<string>Disables the built-in camera while MacCam Privacy Lock is on. Remove this profile or unlock MacCam to use the camera again.</string>
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
        } catch {
            // Root helper creates the directory; user-space write may fail before install.
        }
        do {
            try profileXML.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            // Fallback: temp location; helper install embeds profile via base64 anyway.
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("maccam-disable-camera.mobileconfig")
            do {
                try profileXML.write(to: temp, atomically: true, encoding: .utf8)
                return temp
            } catch {
                return nil
            }
        }
    }

    /// Best-effort check whether our restriction profile is installed.
    static var isActive: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/profiles")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.contains(payloadIdentifier)
        } catch {
            return false
        }
    }
}
