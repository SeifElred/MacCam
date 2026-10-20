import Foundation

/// Pure decision logic for CameraGuard — unit-testable without macOS process APIs.
enum GuardEnforcementAction: Equatable {
    case ignore
    case allowSilently
    case blockSilently
    case freezeAndPrompt
}

enum GuardDecisionEngine {
    static func action(
        mode: GuardMode,
        cameraOn: Bool,
        alreadyPrompting: Bool,
        sessionAlreadyHandled: Bool,
        allowOnceActive: Bool,
        policy: PolicyDecision
    ) -> GuardEnforcementAction {
        guard mode == .locked else { return .ignore }
        guard cameraOn else { return .ignore }
        if alreadyPrompting { return .ignore }
        if sessionAlreadyHandled || allowOnceActive { return .ignore }

        switch policy {
        case .allowlisted:
            return .allowSilently
        case .blocklisted:
            return .blockSilently
        case .unknown:
            return .freezeAndPrompt
        }
    }

    static func timedOut(
        isPrompting: Bool,
        deadline: Date?,
        now: Date
    ) -> Bool {
        guard isPrompting, let deadline else { return false }
        return now >= deadline
    }
}
