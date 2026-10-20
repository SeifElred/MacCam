import Foundation

/// Facade for camera disable — prefers OS restriction profile + daemon bootout.
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

    @discardableResult
    static func disableCameraHardware(
        using kill: (pid_t) -> Bool,
        strategy: Strategy
    ) -> Bool {
        CameraDisableHelper.unprivilegedKillDaemons(using: kill)

        switch strategy {
        case .helperOnly:
            return CameraDisableHelper.requestLock()
        case .helperThenAdmin:
            if CameraDisableHelper.isInstalled {
                _ = CameraDisableHelper.requestLock()
                return true
            }
            return CameraDisableHelper.privilegedLockFull()
        case .adminOnly:
            return CameraDisableHelper.privilegedLockFull()
        }
    }
}
