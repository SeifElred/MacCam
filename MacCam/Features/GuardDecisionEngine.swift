import Foundation

/// Pure decision logic for CameraGuard — unit-testable without macOS process APIs.
enum GuardEnforcementAction: Equatable {
    case ignore
    /// Leave camera on (allow-listed session).
    case allowSilently
    /// Disable camera hardware (apps stay open; stream fails; LED can turn off).
    case disableHardware
}

enum GuardDecisionEngine {
    static func action(
        mode: GuardMode,
        cameraOn: Bool,
        allowlistedUserLikely: Bool
    ) -> GuardEnforcementAction {
        guard mode == .locked else { return .ignore }
        guard cameraOn else { return .ignore }
        if allowlistedUserLikely { return .allowSilently }
        return .disableHardware
    }
}
