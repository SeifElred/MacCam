import Foundation

/// Pure decision logic for CameraGuard — unit-testable without macOS process APIs.
enum GuardEnforcementAction: Equatable {
    case ignore
    case allowSilently
    /// Force-stop the process so camera hardware (and LED) can release.
    case blockNow
}

enum GuardDecisionEngine {
    static func action(
        mode: GuardMode,
        cameraOn: Bool,
        allowOnceActive: Bool,
        policy: PolicyDecision
    ) -> GuardEnforcementAction {
        guard mode == .locked else { return .ignore }
        guard cameraOn else { return .ignore }
        if allowOnceActive { return .ignore }

        switch policy {
        case .allowlisted:
            return .allowSilently
        case .blocklisted, .unknown:
            return .blockNow
        }
    }
}
