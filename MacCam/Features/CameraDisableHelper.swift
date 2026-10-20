import Foundation

/// One-time root LaunchDaemon so MacCam can turn the M1/M-series camera (and LED) off
/// without force-quitting user apps. Password is required only for install (and rare fallbacks).
enum CameraDisableHelper {
    static let label = "com.maccam.cameradisable"
    static let supportDir = "/Library/Application Support/MacCam"
    static let scriptPath = supportDir + "/disable-camera.sh"
    static let triggerPath = supportDir + "/trigger"
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
            "sudo /usr/bin/killall -9 \(names)",
            "sleep 0.2",
            "sudo /usr/bin/killall -9 \(names)",
            "sleep 0.2",
            "sudo /usr/bin/killall -9 \(names)"
        ].joined(separator: "; ")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: scriptPath)
            && FileManager.default.fileExists(atPath: plistPath)
    }

    /// Helper files exist and trigger is writable (ready for password-free disables).
    static var isHealthy: Bool {
        guard isInstalled else { return false }
        return FileManager.default.isWritableFile(atPath: triggerPath)
            || FileManager.default.isWritableFile(atPath: supportDir)
    }

    /// Installs root helper (one macOS password dialog) and runs a multi-pulse clear immediately.
    @discardableResult
    static func install() -> Bool {
        let script = disableScriptContents()
        let plist = launchDaemonPlist()
        let scriptB64 = Data(script.utf8).base64EncodedString()
        let plistB64 = Data(plist.utf8).base64EncodedString()

        let shell = [
            "mkdir -p '\(supportDir)'",
            "echo '\(scriptB64)' | /usr/bin/base64 -D > '\(scriptPath)'",
            "chmod 755 '\(scriptPath)'",
            "echo '\(plistB64)' | /usr/bin/base64 -D > '\(plistPath)'",
            "chmod 644 '\(plistPath)'",
            "chown root:wheel '\(scriptPath)' '\(plistPath)'",
            "touch '\(triggerPath)'",
            "chmod 666 '\(triggerPath)'",
            "/bin/launchctl bootout system/\(label) 2>/dev/null || true",
            "/bin/launchctl unload '\(plistPath)' 2>/dev/null || true",
            "/bin/launchctl bootstrap system '\(plistPath)' 2>/dev/null || true",
            "/bin/launchctl load -w '\(plistPath)' 2>/dev/null || true",
            "/bin/launchctl enable system/\(label) 2>/dev/null || true",
            "/bin/launchctl kickstart -k system/\(label) 2>/dev/null || true",
            "'\(scriptPath)'",
            "test -f '\(scriptPath)'",
            "test -f '\(plistPath)'",
            "exit 0"
        ].joined(separator: "; ")

        let ok = runAdminShell(shell)
        return ok && isInstalled
    }

    /// Ask the root helper to bounce camera services (no password if installed + healthy).
    @discardableResult
    static func requestDisable() -> Bool {
        guard isInstalled else { return false }

        let stamp = "\(Date().timeIntervalSince1970)-\(UUID().uuidString)\n"
        do {
            try stamp.write(toFile: triggerPath, atomically: true, encoding: .utf8)
        } catch {
            // Trigger not writable — run script with admin once.
            return runAdminShell("'\(scriptPath)'; exit 0")
        }
        _ = runProcess("/bin/launchctl", arguments: ["kickstart", "-k", "system/\(label)"])
        // Direct root script execution isn't possible without admin; WatchPaths + kickstart handle it.
        // Also try executing via launchctl as user may have rights on some systems:
        _ = runProcess("/bin/bash", arguments: [scriptPath])
        return true
    }

    /// One password: multi-pulse kill loop (reduces “camera grabs again” races).
    @discardableResult
    static func privilegedKillDaemons() -> Bool {
        let names = daemonNames.map { "\"\($0)\"" }.joined(separator: " ")
        let shell = [
            "for i in 1 2 3 4 5 6; do",
            "/usr/bin/killall -9 \(names) 2>/dev/null || true;",
            "/bin/sleep 0.12;",
            "done",
            "exit 0"
        ].joined(separator: " ")
        return runAdminShell(shell)
    }

    /// Unprivileged best-effort (usually fails on root daemons — still try).
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

    // MARK: - Embedded files

    private static func disableScriptContents() -> String {
        let killLines = daemonNames
            .map { "  /usr/bin/killall -9 \"\($0)\" 2>/dev/null || true" }
            .joined(separator: "\n")
        return """
        #!/bin/bash
        # MacCam — disable built-in camera hardware (M1 Pro / Apple Silicon)
        # Runs as root. Does not quit user apps. Multi-pulse to beat re-acquire races.
        for i in 1 2 3 4 5 6; do
        \(killLines)
          /bin/sleep 0.12
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
