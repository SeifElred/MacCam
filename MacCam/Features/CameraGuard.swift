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
    case blocked(appName: String)
    case cameraActive(appName: String)

    var label: String {
        switch self {
        case .protected:
            return "Protected — camera locked"
        case .unlocked:
            return "Camera unlocked"
        case .blocked(let name):
            return "Blocked \(name)"
        case .cameraActive(let name):
            return "\(name) is using the camera"
        }
    }
}

protocol ProcessController {
    /// Ask the process to quit (releases camera cleanly when possible).
    func terminate(pid: pid_t) -> Bool
    /// Force-kill so a stuck camera hold is released (never SIGSTOP).
    func forceKill(pid: pid_t) -> Bool
}

struct POSIXProcessController: ProcessController {
    func terminate(pid: pid_t) -> Bool { kill(pid, SIGTERM) == 0 }
    func forceKill(pid: pid_t) -> Bool { kill(pid, SIGKILL) == 0 }
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
    @Published private(set) var lastBlockedName: String?

    let policy: PolicyStore
    let activityLog: ActivityLog
    let monitor: CameraMonitor
    let identifier: ProcessIdentifier
    let processController: ProcessController

    private let defaults: UserDefaults
    private let modeKey = "macCam.mode"
    private let notifyKey = "macCam.notifyOnAttempt"

    private var handledSessionKey: String?
    private var allowOnceSession: Set<String> = []
    private var forceKillPIDs: Set<pid_t> = []
    private var statusClearWork: DispatchWorkItem?
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
        forceKillPIDs.removeAll()
    }

    func setLocked(_ locked: Bool) {
        mode = locked ? .locked : .unlocked
        if locked {
            allowOnceSession.removeAll()
            handledSessionKey = nil
            forceKillPIDs.removeAll()
        }
        lastBlockedName = nil
        refreshStatus()
    }

    /// Allow an app for this MacCam session without adding to the permanent allow list.
    func allowOnce(_ app: AppIdentity) {
        allowOnceSession.insert(sessionKey(for: app))
    }

    // MARK: - Internals

    private func tick() {
        monitor.refresh()
        enforceIfNeeded()
        refreshStatus()
    }

    private func enforceIfNeeded() {
        if mode == .locked, !monitor.isCameraOn {
            handledSessionKey = nil
            forceKillPIDs.removeAll()
            return
        }

        guard let candidate = identifier.identifyLikelyCameraUser() else { return }
        let key = sessionKey(for: candidate.app)
        let decision = policy.decision(for: candidate.app)
        let action = GuardDecisionEngine.action(
            mode: mode,
            cameraOn: monitor.isCameraOn,
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
        case .blockNow:
            blockCameraUser(candidate, key: key, detail: decision == .blocklisted ? "Blocklist" : "Locked")
        }
    }

    private func blockCameraUser(_ candidate: ProcessCandidate, key: String, detail: String) {
        // Never SIGSTOP — freezing keeps the camera open and the green LED stuck on.
        // First try a normal quit; if the LED/camera is still held next tick, force-kill.
        if forceKillPIDs.contains(candidate.pid) {
            _ = processController.forceKill(pid: candidate.pid)
            handledSessionKey = key
            return
        }

        _ = processController.terminate(pid: candidate.pid)
        forceKillPIDs.insert(candidate.pid)
        lastBlockedName = candidate.app.displayName
        activityLog.record(ActivityEvent(app: candidate.app, action: .blocked, detail: detail))
        notify(
            title: "Camera blocked",
            body: "\(candidate.app.displayName) was stopped. Unlock MacCam (or allow the app) to use the camera."
        )
        iconState = .alert
        scheduleStatusClear()
    }

    private func scheduleStatusClear() {
        statusClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.lastBlockedName = nil
                self?.refreshStatus()
            }
        }
        statusClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func refreshStatus() {
        switch mode {
        case .locked:
            if let name = lastBlockedName {
                iconState = .alert
                status = .blocked(appName: name)
            } else {
                iconState = .locked
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
