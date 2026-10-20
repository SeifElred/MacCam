import Foundation

/// Pure decision logic for CameraGuard — unit-testable without macOS process APIs.
enum GuardEnforcementAction: Equatable {
    case ignore
    case allowSilently
    /// Stop the process so it releases the camera (no freeze).
    case blockNow
}

enum GuardDecisionEngine {
    static func action(
        mode: GuardMode,
        cameraOn: Bool,
        sessionAlreadyHandled: Bool,
        allowOnceActive: Bool,
        policy: PolicyDecision
    ) -> GuardEnforcementAction {
        guard mode == .locked else { return .ignore }
        guard cameraOn else { return .ignore }
        if sessionAlreadyHandled || allowOnceActive { return .ignore }

        switch policy {
        case .allowlisted:
            return .allowSilently
        case .blocklisted, .unknown:
            // Locked = camera must not stay on. Quit the user process so hardware releases.
            return .blockNow
        }
    }
}
