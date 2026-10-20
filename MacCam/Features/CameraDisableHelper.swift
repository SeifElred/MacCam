import Foundation

/// One-time root LaunchDaemon so MacCam can turn the M1/M-series camera (and LED) off
/// without force-quitting user apps. Password is required only for install.
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

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: scriptPath)
            && FileManager.default.fileExists(atPath: plistPath)
    }

    /// Installs root helper (one macOS password dialog).
    @discardableResult
    static func install() -> Bool {
        let script = disableScriptContents()
        let plist = launchDaemonPlist()

        // Escape for embedding inside `do shell script "..."`.
        let scriptB64 = Data(script.utf8).base64EncodedString()
        let plistB64 = Data(plist.utf8).base64EncodedString()

        // Single-line shell so osascript quoting stays reliable.
        let shell = [
            "set -e",
            "mkdir -p '\(supportDir)'",
            "echo '\(scriptB64)' | /usr/bin/base64 -D > '\(scriptPath)'",
            "chmod 755 '\(scriptPath)'",
            "echo '\(plistB64)' | /usr/bin/base64 -D > '\(plistPath)'",
            "chmod 644 '\(plistPath)'",
            "chown root:wheel '\(scriptPath)' '\(plistPath)'",
            "touch '\(triggerPath)'",
            "chmod 666 '\(triggerPath)'",
            "/bin/launchctl bootout system/\(label) 2>/dev/null || true",
            "/bin/launchctl bootstrap system '\(plistPath)' 2>/dev/null || /bin/launchctl load -w '\(plistPath)' 2>/dev/null || true",
            "/bin/launchctl enable system/\(label) 2>/dev/null || true",
            "'\(scriptPath)'",
            "exit 0"
        ].joined(separator: "; ")

        return runAdminShell(shell)
    }

    /// Ask the root helper to bounce camera services (no password if installed).
    @discardableResult
    static func requestDisable() -> Bool {
        if isInstalled {
            // WatchPaths fires when the trigger file is written.
            let stamp = "\(Date().timeIntervalSince1970)\n"
            do {
                try stamp.write(toFile: triggerPath, atomically: true, encoding: .utf8)
            } catch {
                // Fallback: run script via admin if trigger isn't writable yet.
                return runAdminShell("'\(scriptPath)'; exit 0")
            }
            // Also invoke directly via launchctl kickstart when possible.
            _ = runProcess("/bin/launchctl", arguments: ["kickstart", "-k", "system/\(label)"])
            return true
        }
        return false
    }

    /// Privileged one-shot kill (password each time unless auth is cached). Used as fallback.
    @discardableResult
    static func privilegedKillDaemons() -> Bool {
        let names = daemonNames.joined(separator: " ")
        let shell = "/usr/bin/killall -9 \(names) 2>/dev/null; exit 0"
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
        let kills = daemonNames.map { "  /usr/bin/killall -9 \"\($0)\" 2>/dev/null || true" }.joined(separator: "\n")
        return """
        #!/bin/bash
        # MacCam — disable built-in camera hardware (M1/Apple Silicon + Intel)
        # Runs as root via LaunchDaemon. Does not quit user apps.
        \(kills)
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
