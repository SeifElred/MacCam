import Foundation

/// Disables the Mac camera hardware by bouncing camera system services.
/// User apps are left running — they simply lose the camera (as if none is plugged in).
enum CameraStackReset {
    /// Camera hardware / capture services — never user apps (Zoom, Chrome, etc.).
    static let daemonNames: [String] = [
        "appleh13camerad",
        "AppleCameraAssistant",
        "VDCAssistant",
        "UVCAssistant",
        "cameracaptured",
        "ContinuityCaptureAgent",
        "CMIOExtensionHost",
        "cmioextensionhelper"
    ]

    static func matchesDaemon(_ processName: String) -> Bool {
        let lower = processName.lowercased()
        return daemonNames.contains { lower == $0.lowercased() || lower.contains($0.lowercased()) }
    }

    struct DisableResult {
        var attemptedNames: [String]
        var unprivilegedKillSucceeded: Bool
        var usedAdmin: Bool
        var adminPromptShown: Bool
    }

    /// Bounce camera services without quitting FaceTime/Zoom/Chrome.
    /// Root-owned daemons often ignore user-level kill — then we escalate once via admin.
    @discardableResult
    static func disableCameraHardware(
        using kill: (pid_t) -> Bool,
        allowAdminEscalation: Bool
    ) -> DisableResult {
        var hit: [String] = []
        var anyKill = false

        for process in ProcessEnumerator.allProcesses() {
            guard matchesDaemon(process.name) else { continue }
            if kill(process.pid) {
                hit.append(process.name)
                anyKill = true
            }
        }

        for name in daemonNames {
            if runKillall(name) {
                hit.append(name)
                anyKill = true
            }
        }

        var usedAdmin = false
        var adminPrompt = false
        if allowAdminEscalation {
            adminPrompt = true
            usedAdmin = runPrivilegedKillall(daemonNames)
            if usedAdmin {
                hit.append(contentsOf: daemonNames)
            }
        }

        return DisableResult(
            attemptedNames: Array(Set(hit)).sorted(),
            unprivilegedKillSucceeded: anyKill,
            usedAdmin: usedAdmin,
            adminPromptShown: adminPrompt
        )
    }

    @discardableResult
    private static func runKillall(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-9", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            // 0 = killed something, 1 = no matching process (still ok)
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Prompts for Mac password once; required because camera daemons are often root-owned.
    @discardableResult
    static func runPrivilegedKillall(_ names: [String]) -> Bool {
        let joined = names.joined(separator: " ")
        // `exit 0` so a missing process name does not fail the whole script.
        let shell = "/usr/bin/killall -9 \(joined) 2>/dev/null; exit 0"
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
