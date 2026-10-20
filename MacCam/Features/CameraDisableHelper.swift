import AppKit
import Foundation

/// SIP-safe camera lock.
///
/// **Password once (lifetime):** install the LaunchDaemon helper.
/// Lock / Unlock writes a command file; the root daemon applies it (StartInterval + WatchPaths).
/// Never installs/removes configuration profiles in daily use.
enum CameraDisableHelper {
    static let label = "com.maccam.cameradisable"
    static let supportDir = "/Library/Application Support/MacCam"
    static let scriptPath = supportDir + "/disable-camera.sh"
    static let triggerPath = supportDir + "/trigger"
    static let commandPath = supportDir + "/command"
    static let statePath = supportDir + "/lock_state"
    static let appliedPath = supportDir + "/last_applied"
    static let versionPath = supportDir + "/helper_version"
    /// Bump when the on-disk LaunchDaemon script must be rewritten (needs one admin password).
    static let helperVersion = "6"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"

    /// Capture helpers only. Never appleh13camerad (re-lights LED). ContinuityCaptureAgent
    /// is not loop-killed — that breaks Continuity and makes the Mac feel broken.
    static let daemonNames: [String] = [
        "AppleCameraAssistant",
        "VDCAssistant",
        "UVCAssistant",
        "cameracaptured"
    ]

    static var terminalFixCommand: String {
        "open -a MacCam; echo 'Use Allow / Deny when a camera app opens.'"
    }

    static var terminalRestoreCommand: String {
        "open -a MacCam; echo 'Click Allow when prompted, or unlock Camera Lock in the menu.'"
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: scriptPath)
            && FileManager.default.fileExists(atPath: plistPath)
    }

    static var isHelperCurrent: Bool {
        guard isInstalled else { return false }
        let onDisk = (try? String(contentsOfFile: versionPath, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return onDisk == helperVersion
    }

    static var isHealthy: Bool {
        guard isInstalled else { return false }
        return FileManager.default.isWritableFile(atPath: triggerPath)
            || FileManager.default.isWritableFile(atPath: commandPath)
    }

    static var isRestrictionActive: Bool {
        if let state = try? String(contentsOfFile: statePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            if state == "locked" { return true }
            if state == "unlocked" { return false }
        }
        return CameraRestrictionProfile.isActive
    }

    static func invalidateRestrictionCache() {
        CameraRestrictionProfile.invalidateCache()
    }

    /// One-time admin password.
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
            "touch '\(triggerPath)' '\(commandPath)' '\(statePath)' '\(appliedPath)'",
            "chmod 666 '\(triggerPath)' '\(commandPath)'",
            "chmod 644 '\(statePath)' '\(appliedPath)'",
            "echo '\(helperVersion)' > '\(versionPath)'",
            "chmod 644 '\(versionPath)'",
            "/usr/bin/profiles remove -identifier=\(CameraRestrictionProfile.payloadIdentifier) 2>/dev/null || true",
            "/bin/launchctl bootout system/\(label) 2>/dev/null || true",
            "/bin/launchctl bootstrap system '\(plistPath)' 2>/dev/null || true",
            "/bin/launchctl enable system/\(label) 2>/dev/null || true",
            "/bin/launchctl kickstart -k system/\(label) 2>/dev/null || true",
            "echo lock > '\(commandPath)'",
            "/bin/bash '\(scriptPath)' once",
            "test -f '\(scriptPath)'",
            "exit 0"
        ].joined(separator: "; ")

        let ok = runAdminShell(shell)
        CameraRestrictionProfile.invalidateCache()
        return ok && isInstalled
    }

    @discardableResult
    static func requestLockQuiet() -> Bool { lockPasswordless() }

    @discardableResult
    static func requestLock() -> Bool { lockPasswordless() }

    @discardableResult
    static func requestDisable() -> Bool { lockPasswordless() }

    @discardableResult
    static func requestUnlock() -> Bool { unlockPasswordless() }

    @discardableResult
    static func unlockPasswordless() -> Bool {
        guard isInstalled else { return false }
        writeCommand("unlock")
        return waitForState("unlocked", timeoutSeconds: 1.5)
    }

    @discardableResult
    static func lockPasswordless() -> Bool {
        guard isInstalled else { return false }
        writeCommand("lock")
        return waitForState("locked", timeoutSeconds: 1.5)
    }

    @discardableResult
    static func privilegedLockFull() -> Bool {
        isInstalled ? lockPasswordless() : install()
    }

    @discardableResult
    static func privilegedUnlockFull() -> Bool {
        if isInstalled { return unlockPasswordless() }
        return install() && unlockPasswordless()
    }

    @discardableResult
    static func privilegedKillDaemons() -> Bool { lockPasswordless() }

    static func presentRestrictionProfileOnce() {}

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

    static func openProfilesSettings() {}

    // MARK: - Internals

    private static func writeCommand(_ command: String) {
        // Non-atomic writes so WatchPaths sees a content change on the same inode.
        let cmdURL = URL(fileURLWithPath: commandPath)
        try? (command + "\n").write(to: cmdURL, atomically: false, encoding: .utf8)
        let stamp = "\(command)-\(Date().timeIntervalSince1970)\n"
        try? stamp.write(toFile: triggerPath, atomically: false, encoding: .utf8)
        // Nudge launchd (may fail without root — StartInterval backup covers that).
        _ = runProcess("/bin/launchctl", arguments: ["kickstart", "-k", "system/\(label)"])
    }

    private static func waitForState(_ wanted: String, timeoutSeconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            CameraRestrictionProfile.invalidateCache()
            if let state = try? String(contentsOfFile: statePath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               state == wanted {
                // Soft-kill only when locking — killing capture agents on unlock races Photo Booth.
                if wanted == "locked" {
                    unprivilegedKillDaemons { pid in kill(pid, SIGKILL) == 0 }
                }
                return wanted == "locked" ? isRestrictionActive : !isRestrictionActive
            }
            usleep(40_000)
            // Re-poke trigger periodically.
            let poke = "poke-\(Date().timeIntervalSince1970)\n"
            try? poke.write(toFile: triggerPath, atomically: false, encoding: .utf8)
        }
        CameraRestrictionProfile.invalidateCache()
        if wanted == "locked" {
            unprivilegedKillDaemons { pid in kill(pid, SIGKILL) == 0 }
        }
        if wanted == "unlocked" { return !isRestrictionActive }
        return isRestrictionActive
    }

    private static func disableScriptContents() -> String {
        let killLines = daemonNames
            .map { "  /usr/bin/killall -9 \"\($0)\" 2>/dev/null || true" }
            .joined(separator: "\n")
        return """
        #!/bin/bash
        # MacCam helper v5 — fast lock/unlock loop (kickstart is not permitted from the app).
        SUPPORT="\(supportDir)"
        CMD_FILE="$SUPPORT/command"
        STATE_FILE="$SUPPORT/lock_state"
        APPLIED_FILE="$SUPPORT/last_applied"
        LOG="$SUPPORT/helper.log"
        soft_kill() {
        \(killLines)
        }
        log() { echo "$(/bin/date '+%H:%M:%S') $*" >> "$LOG"; }
        apply_once() {
          CMD=$(/usr/bin/tr -d ' \\t\\n\\r' < "$CMD_FILE" 2>/dev/null || echo lock)
          LAST=$(/usr/bin/tr -d ' \\t\\n\\r' < "$APPLIED_FILE" 2>/dev/null || echo)
          CUR=$(/usr/bin/tr -d ' \\t\\n\\r' < "$STATE_FILE" 2>/dev/null || echo)
          if [ "$CMD" = "$LAST" ]; then
            # Already applied — do nothing. Continuous soft_kill fights Continuity and keeps the Mac weird.
            return 0
          fi
          if [ "$CMD" = "unlock" ]; then
            /usr/bin/defaults write /Library/Preferences/com.apple.applicationaccess allowCamera -bool true
            /usr/bin/defaults write /Library/Preferences/com.apple.coremediaio.support "Device Access Allowed" -bool true
            echo unlocked > "$STATE_FILE"
            echo unlock > "$APPLIED_FILE"
            log "unlocked"
            return 0
          fi
          /usr/bin/defaults write /Library/Preferences/com.apple.applicationaccess allowCamera -bool false
          /usr/bin/defaults write /Library/Preferences/com.apple.coremediaio.support "Device Access Allowed" -bool false
          echo locked > "$STATE_FILE"
          echo lock > "$APPLIED_FILE"
          soft_kill
          log "locked"
          return 0
        }
        if [ "${1:-}" = "once" ]; then
          apply_once
          exit 0
        fi
        # Poll command file — kickstart from the app is blocked by macOS.
        while true; do
          apply_once
          sleep 0.15
        done
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
        	<key>RunAtLoad</key>
        	<true/>
        	<key>KeepAlive</key>
        	<true/>
        	<key>ThrottleInterval</key>
        	<integer>1</integer>
        	<key>StandardOutPath</key>
        	<string>\(supportDir)/helper-daemon.log</string>
        	<key>StandardErrorPath</key>
        	<string>\(supportDir)/helper-daemon.log</string>
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
