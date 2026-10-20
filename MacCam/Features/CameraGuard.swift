import AppKit
import Foundation
import UserNotifications

enum GuardMode: String, Codable {
    case locked
    case unlocked
}

enum GuardStatus: Equatable {
    case protected
    case unlocked
    case handling(appName: String)
    case cameraActive(appName: String)

    var label: String {
        switch self {
        case .protected:
            return "Protected — camera locked"
        case .unlocked:
            return "Camera unlocked"
        case .handling(let name):
            return "Blocked \(name)"
        case .cameraActive(let name):
            return "\(name) is using the camera"
        }
    }
}

enum UserDecision {
    case allowOnce
    case alwaysAllow
    case blockOnce
    case alwaysBlock
}

protocol ProcessController {
    func suspend(pid: pid_t) -> Bool
    func resume(pid: pid_t) -> Bool
    func terminate(pid: pid_t) -> Bool
}

struct POSIXProcessController: ProcessController {
    func suspend(pid: pid_t) -> Bool { kill(pid, SIGSTOP) == 0 }
    func resume(pid: pid_t) -> Bool { kill(pid, SIGCONT) == 0 }
    func terminate(pid: pid_t) -> Bool { kill(pid, SIGTERM) == 0 }
}

@MainActor
final class CameraGuard: ObservableObject {
    @Published var mode: GuardMode {
        didSet { defaults.set(mode.rawValue, forKey: modeKey) }
    }
    @Published var notifyOnAttempt: Bool {
        didSet { defaults.set(notifyOnAttempt, forKey: notifyKey) }
    }
    @Published private(set) var status: GuardStatus = .protected
    @Published private(set) var iconState: MenuBarIconState = .locked
    @Published private(set) var pendingApp: AppIdentity?
    @Published var showDecisionSheet: Bool = false

    let policy: PolicyStore
    let activityLog: ActivityLog
    let monitor: CameraMonitor
    let identifier: ProcessIdentifier
    let processController: ProcessController

    private let defaults: UserDefaults
    private let modeKey = "macCam.mode"
    private let notifyKey = "macCam.notifyOnAttempt"
    private let promptTimeout: TimeInterval = 30

    private var pendingPID: pid_t?
    private var promptDeadline: Date?
    private var handledSessionKey: String?
    private var allowOnceSession: Set<String> = []
    private var tickTimer: Timer?

    init(
        policy: PolicyStore = PolicyStore(),
        activityLog: ActivityLog = ActivityLog(),
        monitor: CameraMonitor = CameraMonitor(),
        identifier: ProcessIdentifier = ProcessIdentifier(),
        processController: ProcessController = POSIXProcessController(),
        defaults: UserDefaults = .standard
    ) {
        self.policy = policy
        self.activityLog = activityLog
        self.monitor = monitor
        self.identifier = identifier
        self.processController = processController
        self.defaults = defaults

        if let raw = defaults.string(forKey: modeKey), let saved = GuardMode(rawValue: raw) {
            self.mode = saved
        } else {
            self.mode = .locked
        }
        self.notifyOnAttempt = defaults.object(forKey: notifyKey) as? Bool ?? true
        refreshStatus()
    }

    func start() {
        monitor.start()
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        requestNotificationPermissionIfNeeded()
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        monitor.stop()
        // Resume any process we left frozen so we don't strand the user.
        if let pid = pendingPID {
            _ = processController.resume(pid: pid)
            pendingPID = nil
        }
    }

    func setLocked(_ locked: Bool) {
        mode = locked ? .locked : .unlocked
        if locked {
            allowOnceSession.removeAll()
            handledSessionKey = nil
        } else if let pid = pendingPID {
            _ = processController.resume(pid: pid)
            pendingPID = nil
            showDecisionSheet = false
            pendingApp = nil
        }
        refreshStatus()
    }

    func applyUserDecision(_ decision: UserDecision) {
        guard let app = pendingApp, let pid = pendingPID else {
            showDecisionSheet = false
            return
        }

        switch decision {
        case .allowOnce:
            allowOnceSession.insert(sessionKey(for: app))
            _ = processController.resume(pid: pid)
            activityLog.record(ActivityEvent(app: app, action: .allowed, detail: "Allowed once"))
            handledSessionKey = sessionKey(for: app)
        case .alwaysAllow:
            policy.addToAllowlist(app)
            _ = processController.resume(pid: pid)
            activityLog.record(ActivityEvent(app: app, action: .allowed, detail: "Always allow"))
            handledSessionKey = sessionKey(for: app)
        case .blockOnce:
            _ = processController.terminate(pid: pid)
            activityLog.record(ActivityEvent(app: app, action: .blocked, detail: "Blocked once"))
            handledSessionKey = sessionKey(for: app)
        case .alwaysBlock:
            policy.addToBlocklist(app)
            _ = processController.terminate(pid: pid)
            activityLog.record(ActivityEvent(app: app, action: .blocked, detail: "Always block"))
            handledSessionKey = sessionKey(for: app)
        }

        pendingPID = nil
        pendingApp = nil
        showDecisionSheet = false
        promptDeadline = nil
        refreshStatus()
    }

    // MARK: - Internals

    private func tick() {
        monitor.refresh()
        enforceIfNeeded()
        checkPromptTimeout()
        refreshStatus()
    }

    private func enforceIfNeeded() {
        if mode == .locked, !monitor.isCameraOn, pendingPID == nil {
            handledSessionKey = nil
        }

        guard let candidate = identifier.identifyLikelyCameraUser() else { return }
        let key = sessionKey(for: candidate.app)
        let decision = policy.decision(for: candidate.app)
        let action = GuardDecisionEngine.action(
            mode: mode,
            cameraOn: monitor.isCameraOn,
            alreadyPrompting: showDecisionSheet && pendingPID != nil,
            sessionAlreadyHandled: handledSessionKey == key,
            allowOnceActive: allowOnceSession.contains(key),
            policy: decision
        )

        switch action {
        case .ignore:
            return
        case .allowSilently:
            activityLog.record(ActivityEvent(app: candidate.app, action: .allowed, detail: "Allowlist"))
            handledSessionKey = key
        case .blockSilently:
            _ = processController.suspend(pid: candidate.pid)
            _ = processController.terminate(pid: candidate.pid)
            activityLog.record(ActivityEvent(app: candidate.app, action: .blocked, detail: "Blocklist"))
            handledSessionKey = key
            notify(title: "Camera blocked", body: "\(candidate.app.displayName) was blocked automatically.")
        case .freezeAndPrompt:
            let suspended = processController.suspend(pid: candidate.pid)
            guard suspended else {
                activityLog.record(
                    ActivityEvent(
                        app: candidate.app,
                        action: .prompted,
                        detail: "Could not suspend process (permission or ownership)"
                    )
                )
                return
            }
            pendingPID = candidate.pid
            pendingApp = candidate.app
            showDecisionSheet = true
            promptDeadline = Date().addingTimeInterval(promptTimeout)
            activityLog.record(ActivityEvent(app: candidate.app, action: .prompted, detail: "Awaiting decision"))
            notify(title: "Camera access blocked", body: "\(candidate.app.displayName) tried to use the camera.")
            pulseAlertIcon()
        }
    }

    private func checkPromptTimeout() {
        guard GuardDecisionEngine.timedOut(
            isPrompting: showDecisionSheet,
            deadline: promptDeadline,
            now: Date()
        ) else { return }
        guard let app = pendingApp, let pid = pendingPID else { return }

        _ = processController.terminate(pid: pid)
        activityLog.record(ActivityEvent(app: app, action: .autoBlocked, detail: "Timed out after 30s"))
        handledSessionKey = sessionKey(for: app)
        pendingPID = nil
        pendingApp = nil
        showDecisionSheet = false
        promptDeadline = nil
        notify(title: "Camera auto-blocked", body: "\(app.displayName) was blocked after no response.")
    }

    private func refreshStatus() {
        switch mode {
        case .locked:
            iconState = showDecisionSheet ? .alert : .locked
            if let app = pendingApp {
                status = .handling(appName: app.displayName)
            } else {
                status = .protected
            }
        case .unlocked:
            iconState = .unlocked
            if monitor.isCameraOn, let candidate = identifier.identifyLikelyCameraUser() {
                status = .cameraActive(appName: candidate.app.displayName)
                if handledSessionKey != sessionKey(for: candidate.app) {
                    activityLog.record(
                        ActivityEvent(app: candidate.app, action: .unlockedUse, detail: "Observed while unlocked")
                    )
                    handledSessionKey = sessionKey(for: candidate.app)
                }
            } else {
                status = .unlocked
                if !monitor.isCameraOn {
                    handledSessionKey = nil
                }
            }
        }
    }

    private func sessionKey(for app: AppIdentity) -> String {
        if !app.bundleID.isEmpty { return app.bundleID.lowercased() }
        return app.processName.lowercased()
    }

    private func pulseAlertIcon() {
        iconState = .alert
    }

    private func requestNotificationPermissionIfNeeded() {
        guard notifyOnAttempt else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard notifyOnAttempt else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
