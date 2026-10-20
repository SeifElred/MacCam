import Foundation

/// Facade used by CameraGuard — prefers the installed root helper (100% path on M1 Pro).
enum CameraStackReset {
    static var daemonNames: [String] { CameraDisableHelper.daemonNames }

    static func matchesDaemon(_ processName: String) -> Bool {
        let lower = processName.lowercased()
        return daemonNames.contains { lower == $0.lowercased() || lower.contains($0.lowercased()) }
    }

    enum Strategy {
        case helperOnly
        case helperThenAdmin
        case adminOnly
    }

    /// Disable camera hardware. Does not quit Zoom/Chrome/FaceTime.
    @discardableResult
    static func disableCameraHardware(
        using kill: (pid_t) -> Bool,
        strategy: Strategy
    ) -> Bool {
        CameraDisableHelper.unprivilegedKillDaemons(using: kill)

        switch strategy {
        case .helperOnly:
            return CameraDisableHelper.requestDisable()
        case .helperThenAdmin:
            if CameraDisableHelper.isInstalled {
                _ = CameraDisableHelper.requestDisable()
                return true
            }
            return CameraDisableHelper.privilegedKillDaemons()
        case .adminOnly:
            return CameraDisableHelper.privilegedKillDaemons()
        }
    }
}
