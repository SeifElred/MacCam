import Foundation

/// Resets macOS camera services so hardware releases and the green LED can turn off.
/// Killing only the frontmost app often fails — helpers/daemons keep the sensor open.
enum CameraStackReset {
    /// User-space camera / capture related process names (partial, case-insensitive).
    static let daemonNames: [String] = [
        "appleh13camerad",
        "AppleCameraAssistant",
        "VDCAssistant",
        "UVCAssistant",
        "cameracaptured",
        "AVConference",
        "ContinuityCaptureAgent"
    ]

    /// Helper / browser render processes that commonly hold the camera.
    static let helperNameHints: [String] = [
        "chrome helper",
        "chromium helper",
        "edge helper",
        "webkit.gpu",
        "webkit networking",
        "webkit webcontent",
        "zoom.us",
        "cpthost",
        "discord helper",
        "teams helper",
        "screencapture",
        "photobooth",
        "facetime",
        "avconferenced"
    ]

    static func matchesDaemon(_ processName: String) -> Bool {
        let lower = processName.lowercased()
        return daemonNames.contains { lower == $0.lowercased() || lower.contains($0.lowercased()) }
    }

    static func matchesHelper(_ processName: String) -> Bool {
        let lower = processName.lowercased()
        return helperNameHints.contains { lower.contains($0) }
    }

    /// Best-effort: SIGKILL matching processes. Safe if a name is not running.
    @discardableResult
    static func killDaemons(using kill: (pid_t) -> Bool) -> [String] {
        var killed: [String] = []
        for process in ProcessEnumerator.allProcesses() {
            guard matchesDaemon(process.name) else { continue }
            if kill(process.pid) {
                killed.append(process.name)
            }
        }
        // Also invoke killall for names we might not have enumerated.
        for name in daemonNames {
            runKillall(name)
        }
        return Array(Set(killed)).sorted()
    }

    static func helperPIDs() -> [pid_t] {
        ProcessEnumerator.allProcesses()
            .filter { matchesHelper($0.name) || matchesDaemon($0.name) }
            .map(\.pid)
    }

    private static func runKillall(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-9", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // ignore — binary missing or permission denied
        }
    }
}
