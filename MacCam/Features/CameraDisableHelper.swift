import AppKit
import Foundation

/// SIP-safe camera lock helper for M1 Pro.
/// - Lock: install user `allowCamera=false` profile + kill camera daemons (no launchctl on appleh13camerad).
/// - Unlock: remove that profile; let launchd respawn the camera when an app opens it.
/// Never bootout/disable/kickstart `com.apple.appleh13camerad` — SIP returns "Operation not permitted".
enum CameraDisableHelper {
    static let label = "com.maccam.cameradisable"
    static let supportDir = "/Library/Application Support/MacCam"
    static let scriptPath = supportDir + "/disable-camera.sh"
    static let triggerPath = supportDir + "/trigger"
    static let commandPath = supportDir + "/command"
    static let profilePath = supportDir + "/disable-camera.mobileconfig"
    static let userProfilePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + "/Library/Application Support/MacCam/disable-camera.mobileconfig"
    }()
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"

    static let daemonNames: [String] = [
        "appleh13camerad",
        "AppleCameraAssistant",
        "VDCAssistant",
        "UVCAssistant",
        "cameracaptured",
        "ContinuityCaptureAgent"
    ]

    static var terminalFixCommand: String {
        let names = daemonNames.joined(separator: " ")
        return [
            "mkdir -p \"$HOME/Library/Application Support/MacCam\"",
            "open '\(userProfilePath)'",
            "echo 'In the dialog: Install the MacCam profile, then enter your password.'",
            "/usr/bin/killall -9 \(names) 2>/dev/null || true"
        ].joined(separator: "; ")
    }

    /// Restores camera after unlock (SIP-safe — no appleh13camerad kickstart).
    static var terminalRestoreCommand: String {
        [
            "# Remove MacCam camera ban (try without sudo first):",
            "profiles remove -identifier=\(CameraRestrictionProfile.payloadIdentifier)",
            "profiles -R -p \(CameraRestrictionProfile.payloadIdentifier)",
            "# If still listed, open System Settings → General → Device Management / Profiles and remove “MacCam Disable Camera”",
            "open \"x-apple.systempreferences:com.apple.Profiles-Settings.extension\"",
            "/usr/bin/killall -9 appleh13camerad 2>/dev/null || true",
            "echo 'Quit and reopen Photo Booth / FaceTime'"
        ].joined(separator: "; ")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: scriptPath)
            && FileManager.default.fileExists(atPath: plistPath)
    }

    static var isHealthy: Bool {
        guard isInstalled else { return false }
        return FileManager.default.isWritableFile(atPath: triggerPath)
            || FileManager.default.isWritableFile(atPath: supportDir)
    }

    static var isRestrictionActive: Bool {
        CameraRestrictionProfile.isActive
    }

    /// One-time: install helper files + write user profile copy (password for LaunchDaemon only).
    @discardableResult
    static func install() -> Bool {
        writeUserProfileFile()
        let script = disableScriptContents()
        let plist = launchDaemonPlist()
        let profile = CameraRestrictionProfile.profileXML

        let scriptB64 = Data(script.utf8).base64EncodedString()
        let plistB64 = Data(plist.utf8).base64EncodedString()
        let profileB64 = Data(profile.utf8).base64EncodedString()

        let shell = [
            "mkdir -p '\(supportDir)'",
            "echo '\(scriptB64)' | /usr/bin/base64 -D > '\(scriptPath)'",
            "chmod 755 '\(scriptPath)'",
            "echo '\(plistB64)' | /usr/bin/base64 -D > '\(plistPath)'",
            "chmod 644 '\(plistPath)'",
            "echo '\(profileB64)' | /usr/bin/base64 -D > '\(profilePath)'",
            "chmod 644 '\(profilePath)'",
            "chown root:wheel '\(scriptPath)' '\(plistPath)' '\(profilePath)'",
            "touch '\(triggerPath)'",
            "chmod 666 '\(triggerPath)'",
            "touch '\(commandPath)'",
            "chmod 666 '\(commandPath)'",
            "/bin/launchctl bootout system/\(label) 2>/dev/null || true",
            "/bin/launchctl unload '\(plistPath)' 2>/dev/null || true",
            "/bin/launchctl bootstrap system '\(plistPath)' 2>/dev/null || true",
            "/bin/launchctl load -w '\(plistPath)' 2>/dev/null || true",
            "/bin/launchctl enable system/\(label) 2>/dev/null || true",
            "test -f '\(scriptPath)'",
            "test -f '\(plistPath)'",
            "exit 0"
        ].joined(separator: "; ")

        let ok = runAdminShell(shell)
        // Soft lock only — do not open Install Profile here (avoids dialog spam during setup).
        _ = requestLockQuiet()
        return ok && isInstalled
    }

    /// Soft lock: trigger helper + kill camera daemons. Never opens Install Profile UI.
    @discardableResult
    static func requestLockQuiet() -> Bool {
        writeUserProfileFile()
        writeCommand("lock")
        _ = fireHelper()
        unprivilegedKillDaemons { pid in kill(pid, SIGKILL) == 0 }
        return true
    }

    /// One-shot: open .mobileconfig so the user can Install the ban (user domain).
    static func presentRestrictionProfileOnce() {
        guard !isRestrictionActive else { return }
        openProfileForUserInstall()
    }

    @discardableResult
    static func requestLock() -> Bool {
        // Quiet by default — callers that need the Install dialog call presentRestrictionProfileOnce().
        requestLockQuiet()
    }

    @discardableResult
    static func requestUnlock() -> Bool {
        writeCommand("unlock")
        _ = fireHelper()
        removeUserRestrictionProfiles()
        unprivilegedKillDaemons { pid in kill(pid, SIGKILL) == 0 }
        return true
    }

    @discardableResult
    static func requestDisable() -> Bool {
        requestLockQuiet()
    }

    @discardableResult
    static func privilegedLockFull() -> Bool {
        writeUserProfileFile()
        // Do not open profile here — password prompt + Install dialog together feels like a hang.
        let names = daemonNames.map { "\"\($0)\"" }.joined(separator: " ")
        let shell = [
            "for i in 1 2 3; do /usr/bin/killall -9 \(names) 2>/dev/null || true; /bin/sleep 0.1; done",
            "exit 0"
        ].joined(separator: "; ")
        return runAdminShell(shell)
    }

    @discardableResult
    static func privilegedUnlockFull() -> Bool {
        // Remove profile as console user (sudo profiles remove often returns -205).
        removeUserRestrictionProfiles()
        openProfilesSettings()
        let shell = [
            // Best-effort system-domain remove (ignore -205).
            "/usr/bin/profiles remove -identifier=\(CameraRestrictionProfile.payloadIdentifier) 2>/dev/null || true",
            "/usr/bin/profiles -R -p \(CameraRestrictionProfile.payloadIdentifier) 2>/dev/null || true",
            // Bounce only via killall — launchd/SIP restarts appleh13camerad when an app needs it.
            "/usr/bin/killall -9 appleh13camerad 2>/dev/null || true",
            "exit 0"
        ].joined(separator: "; ")
        _ = runAdminShell(shell)
        removeUserRestrictionProfiles()
        return !isRestrictionActive
    }

    @discardableResult
    static func privilegedKillDaemons() -> Bool {
        privilegedLockFull()
    }

    static func unprivilegedKillDaemons(using kill: (pid_t) -> Bool) {
        for process in ProcessEnumerator.allProcesses() {
            let lower = process.name.lowercased()
            if daemonNames.contains(where: { lower == $0.lowercased() || lower.contains($0.lowercased()) }) {
                _ = kill(process.pid)
            }
        }
        for name in daemonNames {
            _ = runProcess("/usr/bin/killall", arguments: ["-9", name])
        }
    }

    static func openProfilesSettings() {
        // Sonoma/Sequoia: Device Management / Profiles pane.
        let urls = [
            "x-apple.systempreferences:com.apple.Profiles-Settings.extension",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
            "/System/Library/PreferencePanes/Profiles.prefPane"
        ]
        for raw in urls {
            if let url = URL(string: raw) ?? URL(fileURLWithPath: raw) as URL? {
                if NSWorkspace.shared.open(url) { return }
            }
        }
    }

    // MARK: - Internals

    @discardableResult
    private static func writeUserProfileFile() -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacCam", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("disable-camera.mobileconfig")
        do {
            try CameraRestrictionProfile.profileXML.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func openProfileForUserInstall() {
        guard let url = writeUserProfileFile() else { return }
        // Opening .mobileconfig shows Install for the current user (correct profile domain).
        NSWorkspace.shared.open(url)
    }

    private static func removeUserRestrictionProfiles() {
        // Current user domain (install via open lands here; sudo profiles remove → -205).
        _ = runProcess("/usr/bin/profiles", arguments: [
            "remove", "-identifier=\(CameraRestrictionProfile.payloadIdentifier)"
        ])
        _ = runProcess("/usr/bin/profiles", arguments: [
            "-R", "-p", CameraRestrictionProfile.payloadIdentifier
        ])
        let uid = getuid()
        _ = runProcess("/bin/launchctl", arguments: [
            "asuser", "\(uid)",
            "/usr/bin/profiles", "remove",
            "-identifier=\(CameraRestrictionProfile.payloadIdentifier)"
        ])
    }

    private static func writeCommand(_ command: String) {
        let cmdURL = URL(fileURLWithPath: commandPath)
        try? (command + "\n").write(to: cmdURL, atomically: true, encoding: .utf8)
        usleep(50_000)
        let stamp = "\(Date().timeIntervalSince1970)-\(command)\n"
        try? stamp.write(toFile: triggerPath, atomically: true, encoding: .utf8)
    }

    @discardableResult
    private static func fireHelper() -> Bool {
        guard isInstalled else { return false }
        _ = runProcess("/bin/launchctl", arguments: ["kickstart", "-k", "system/\(label)"])
        return true
    }

    private static func disableScriptContents() -> String {
        let killLines = daemonNames
            .map { "  /usr/bin/killall -9 \"\($0)\" 2>/dev/null || true" }
            .joined(separator: "\n")
        return """
        #!/bin/bash
        # MacCam helper — SIP-safe (never kickstart/bootout appleh13camerad)
        SUPPORT="\(supportDir)"
        CMD_FILE="$SUPPORT/command"
        PROFILE="$SUPPORT/disable-camera.mobileconfig"
        CMD=$(/usr/bin/tr -d '\\n' < "$CMD_FILE" 2>/dev/null || echo lock)
        CONSOLE_USER=$(/usr/bin/stat -f%Su /dev/console)
        CONSOLE_UID=$(/usr/bin/id -u "$CONSOLE_USER")

        if [ "$CMD" = "unlock" ]; then
          # Remove user-domain profile (sudo profiles remove often returns -205).
          /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" /usr/bin/profiles remove -identifier=\(CameraRestrictionProfile.payloadIdentifier) 2>/dev/null || true
          /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" /usr/bin/profiles -R -p \(CameraRestrictionProfile.payloadIdentifier) 2>/dev/null || true
          /usr/bin/profiles remove -identifier=\(CameraRestrictionProfile.payloadIdentifier) 2>/dev/null || true
          # Soft bounce only — SIP restarts the daemon when an app opens the camera.
        \(killLines)
          exit 0
        fi

        # --- LOCK ---
        # Copy profile into the user folder only. Do NOT auto-open Install UI (causes lag/spam).
        if [ -f "$PROFILE" ]; then
          /bin/mkdir -p "/Users/$CONSOLE_USER/Library/Application Support/MacCam" 2>/dev/null || true
          /bin/cp -f "$PROFILE" "/Users/$CONSOLE_USER/Library/Application Support/MacCam/disable-camera.mobileconfig" 2>/dev/null || true
        fi
        for i in 1 2 3; do
        \(killLines)
          /bin/sleep 0.08
        done
        exit 0
        """
    }

    private static func launchDaemonPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        	<key>Label</key>
        	<string>\(label)</string>
        	<key>ProgramArguments</key>
        	<array>
        		<string>/bin/bash</string>
        		<string>\(scriptPath)</string>
        	</array>
        	<key>WatchPaths</key>
        	<array>
        		<string>\(triggerPath)</string>
        	</array>
        	<key>RunAtLoad</key>
        	<true/>
        	<key>ThrottleInterval</key>
        	<integer>0</integer>
        	<key>StandardOutPath</key>
        	<string>\(supportDir)/helper.log</string>
        	<key>StandardErrorPath</key>
        	<string>\(supportDir)/helper.log</string>
        </dict>
        </plist>
        """
    }

    @discardableResult
    private static func runAdminShell(_ shell: String) -> Bool {
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        return runProcess("/usr/bin/osascript", arguments: ["-e", appleScript]) == 0
    }

    @discardableResult
    private static func runProcess(_ launchPath: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
