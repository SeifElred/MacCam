import Foundation

/// Root LaunchDaemon helper: OS camera restriction profile + appleh13camerad bootout.
/// Does not force-quit user apps. One-time password to install the helper.
enum CameraDisableHelper {
    static let label = "com.maccam.cameradisable"
    static let supportDir = "/Library/Application Support/MacCam"
    static let scriptPath = supportDir + "/disable-camera.sh"
    static let triggerPath = supportDir + "/trigger"
    static let commandPath = supportDir + "/command"
    static let profilePath = supportDir + "/disable-camera.mobileconfig"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"

    /// M1 Pro uses appleh13camerad for the built-in FaceTime camera.
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
            "sudo /usr/bin/profiles install -type configuration -path '\(profilePath)'",
            "sudo /usr/bin/killall -9 \(names)",
            "sudo /bin/launchctl bootout system/com.apple.appleh13camerad",
            "sleep 0.2",
            "sudo /usr/bin/killall -9 \(names)"
        ].joined(separator: "; ")
    }

    /// Restores camera after unlock (run if apps still cannot see the camera).
    static var terminalRestoreCommand: String {
        [
            "sudo /usr/bin/profiles remove -identifier=\(CameraRestrictionProfile.payloadIdentifier)",
            "sudo /usr/bin/profiles -R -p \(CameraRestrictionProfile.payloadIdentifier)",
            "sudo /bin/launchctl enable system/com.apple.appleh13camerad",
            "sudo /bin/launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.appleh13camerad.plist",
            "sudo /bin/launchctl kickstart -k system/com.apple.appleh13camerad",
            "sudo /usr/bin/killall -9 appleh13camerad",
            "sudo /bin/launchctl kickstart -k system/com.apple.appleh13camerad"
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

    /// Installs root helper + embeds mobileconfig (one password dialog).
    @discardableResult
    static func install() -> Bool {
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
            "echo lock > '\(commandPath)'",
            "'\(scriptPath)'",
            "test -f '\(scriptPath)'",
            "test -f '\(plistPath)'",
            "test -f '\(profilePath)'",
            "exit 0"
        ].joined(separator: "; ")

        let ok = runAdminShell(shell)
        return ok && isInstalled
    }

    /// Lock: install allowCamera=false profile + bootout camera daemon (no user-app quits).
    @discardableResult
    static func requestLock() -> Bool {
        writeCommand("lock")
        return fireHelper()
    }

    /// Unlock: remove restriction profile + restore appleh13camerad.
    @discardableResult
    static func requestUnlock() -> Bool {
        writeCommand("unlock")
        return fireHelper()
    }

    /// Backward-compatible alias used by older call sites.
    @discardableResult
    static func requestDisable() -> Bool {
        requestLock()
    }

    /// Admin fallback: multi-pulse kill + bootout + profile install in one password.
    @discardableResult
    static func privilegedLockFull() -> Bool {
        let names = daemonNames.map { "\"\($0)\"" }.joined(separator: " ")
        let profileB64 = Data(CameraRestrictionProfile.profileXML.utf8).base64EncodedString()
        let shell = [
            "mkdir -p '\(supportDir)'",
            "echo '\(profileB64)' | /usr/bin/base64 -D > '\(profilePath)'",
            "chmod 644 '\(profilePath)'",
            "/usr/bin/profiles install -type configuration -path '\(profilePath)' 2>/dev/null || true",
            "for i in 1 2 3 4 5 6; do /usr/bin/killall -9 \(names) 2>/dev/null || true; /bin/sleep 0.12; done",
            // bootout only — do NOT launchctl disable (that can stick and block unlock).
            "/bin/launchctl bootout system/com.apple.appleh13camerad 2>/dev/null || true",
            "exit 0"
        ].joined(separator: "; ")
        return runAdminShell(shell)
    }

    /// Always use this on Unlock — removes OS ban and brings appleh13camerad back.
    @discardableResult
    static func privilegedUnlockFull() -> Bool {
        let shell = [
            "/usr/bin/profiles remove -identifier=\(CameraRestrictionProfile.payloadIdentifier) 2>/dev/null || true",
            "/usr/bin/profiles -R -p \(CameraRestrictionProfile.payloadIdentifier) 2>/dev/null || true",
            "/bin/launchctl enable system/com.apple.appleh13camerad 2>/dev/null || true",
            "/bin/launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.appleh13camerad.plist 2>/dev/null || true",
            "/bin/launchctl load -w /System/Library/LaunchDaemons/com.apple.appleh13camerad.plist 2>/dev/null || true",
            "/bin/launchctl kickstart -k system/com.apple.appleh13camerad 2>/dev/null || true",
            // If a zombie instance blocks devices, bounce once cleanly:
            "/usr/bin/killall -9 appleh13camerad 2>/dev/null || true",
            "/bin/sleep 0.3",
            "/bin/launchctl kickstart -k system/com.apple.appleh13camerad 2>/dev/null || true",
            "exit 0"
        ].joined(separator: "; ")
        return runAdminShell(shell)
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

    // MARK: - Internals

    private static func writeCommand(_ command: String) {
        // Write command before trigger so WatchPaths always sees the right action.
        let cmdURL = URL(fileURLWithPath: commandPath)
        try? (command + "\n").write(to: cmdURL, atomically: true, encoding: .utf8)
        // Brief settle so the helper never races an empty/stale command file.
        usleep(50_000)
        let stamp = "\(Date().timeIntervalSince1970)-\(command)\n"
        try? stamp.write(toFile: triggerPath, atomically: true, encoding: .utf8)
    }

    @discardableResult
    private static func fireHelper() -> Bool {
        guard isInstalled else { return false }
        _ = runProcess("/bin/launchctl", arguments: ["kickstart", "-k", "system/\(label)"])
        // WatchPaths also fires from trigger write.
        return true
    }

    private static func disableScriptContents() -> String {
        let killLines = daemonNames
            .map { "  /usr/bin/killall -9 \"\($0)\" 2>/dev/null || true" }
            .joined(separator: "\n")
        return """
        #!/bin/bash
        # MacCam root helper — M1 Pro / Apple Silicon
        # Commands: lock (default) | unlock
        # Does NOT quit user apps (Zoom/Chrome/FaceTime stay open).
        SUPPORT="\(supportDir)"
        CMD_FILE="$SUPPORT/command"
        PROFILE="$SUPPORT/disable-camera.mobileconfig"
        CMD=$(/bin/cat "$CMD_FILE" 2>/dev/null || echo lock)

        if [ "$CMD" = "unlock" ]; then
          /usr/bin/profiles remove -identifier=\(CameraRestrictionProfile.payloadIdentifier) 2>/dev/null || true
          /usr/bin/profiles -R -p \(CameraRestrictionProfile.payloadIdentifier) 2>/dev/null || true
          /bin/launchctl enable system/com.apple.appleh13camerad 2>/dev/null || true
          /bin/launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.appleh13camerad.plist 2>/dev/null || true
          /bin/launchctl load -w /System/Library/LaunchDaemons/com.apple.appleh13camerad.plist 2>/dev/null || true
          /bin/launchctl kickstart -k system/com.apple.appleh13camerad 2>/dev/null || true
          /usr/bin/killall -9 appleh13camerad 2>/dev/null || true
          /bin/sleep 0.3
          /bin/launchctl kickstart -k system/com.apple.appleh13camerad 2>/dev/null || true
          exit 0
        fi

        # --- LOCK ---
        if [ -f "$PROFILE" ]; then
          /usr/bin/profiles install -type configuration -path "$PROFILE" 2>/dev/null || true
        fi

        for i in 1 2 3 4 5 6; do
        \(killLines)
          /bin/sleep 0.12
        done

        # Temporary stop only — never "disable" (that sticks and blocks unlock).
        /bin/launchctl bootout system/com.apple.appleh13camerad 2>/dev/null || true
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
