import Foundation

/// Disables the Mac camera hardware by bouncing camera system services.
/// User apps are left running — they simply lose the camera (as if none is plugged in).
/// That releases the sensor so the green LED can turn off.
enum CameraStackReset {
    /// Camera hardware / capture services only — never user apps (Zoom, Chrome, etc.).
    static let daemonNames: [String] = [
        "appleh13camerad",
        "AppleCameraAssistant",
        "VDCAssistant",
        "UVCAssistant",
        "cameracaptured"
    ]

    static func matchesDaemon(_ processName: String) -> Bool {
        let lower = processName.lowercased()
        return daemonNames.contains { lower == $0.lowercased() || lower.contains($0.lowercased()) }
    }

    /// Bounce camera services. Does not quit FaceTime/Zoom/Chrome — only the camera stack.
    @discardableResult
    static func disableCameraHardware(using kill: (pid_t) -> Bool) -> [String] {
        var hit: [String] = []
        for process in ProcessEnumerator.allProcesses() {
            guard matchesDaemon(process.name) else { continue }
            if kill(process.pid) {
                hit.append(process.name)
            }
        }
        for name in daemonNames {
            runKillall(name)
            hit.append(name)
        }
        return Array(Set(hit)).sorted()
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
            // ignore
        }
    }
}
