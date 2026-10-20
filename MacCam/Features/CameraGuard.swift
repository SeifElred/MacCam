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
    case clearing(appName: String)
    case blocked(appName: String)
    case cameraActive(appName: String)

    var label: String {
        switch self {
        case .protected:
            return "Protected — LED off"
        case .unlocked:
            return "Camera unlocked"
        case .clearing(let name):
            return "Stopping \(name)…"
        case .blocked(let name):
            return "Blocked \(name)"
        case .cameraActive(let name):
            return "\(name) is using the camera"
        }
    }
}

protocol ProcessController {
    func forceKill(pid: pid_t) -> Bool
}

struct POSIXProcessController: ProcessController {
    /// SIGKILL so the process cannot keep the camera (and green LED) held open.
    func forceKill(pid: pid_t) -> Bool { kill(pid, SIGKILL) == 0 }
}

@MainActor
final class CameraGuard: ObservableObject {
    @Published var mode: GuardMode {
        didSet {
            defaults.set(mode.rawValue, forKey: modeKey)
            syncMonitorPace()
        }
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

    private var allowOnceSession: Set<String> = []
    private var notifyCooldown: [String: Date] = [:]
    private var loggedAllowKeys: Set<String> = []
    private var statusClearWork: DispatchWorkItem?
    private var tickTimer: Timer?
    private let lockedTick: TimeInterval = 0.10
    private let unlockedTick: TimeInterval = 0.35

    init(
        policy: PolicyStore = PolicyStore(),
        activityLog: ActivityLog = ActivityLog(),
        monitor: CameraMonitor = CameraMonitor(pollInterval: 0.10),
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
        restartTickTimer()
        requestNotificationPermissionIfNeeded()
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        monitor.stop()
    }

    func setLocked(_ locked: Bool) {
        mode = locked ? .locked : .unlocked
        if locked {
            allowOnceSession.removeAll()
            loggedAllowKeys.removeAll()
            // Immediately clear any active camera hold.
            enforceHardLock()
        }
        lastBlockedName = nil
        restartTickTimer()
        refreshStatus()
    }

    func allowOnce(_ app: AppIdentity) {
        allowOnceSession.insert(sessionKey(for: app))
    }

    // MARK: - Internals

    private func syncMonitorPace() {
        monitor.setPollInterval(mode == .locked ? lockedTick : unlockedTick)
        restartTickTimer()
    }

    private func restartTickTimer() {
        tickTimer?.invalidate()
        let interval = mode == .locked ? lockedTick : unlockedTick
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func tick() {
        monitor.refresh()
        if mode == .locked {
            enforceHardLock()
        }
        refreshStatus()
    }

    /// While locked: keep force-killing non-allowed camera users until CoreMediaIO reports camera off.
    private func enforceHardLock() {
        guard mode == .locked else { return }
        guard monitor.isCameraOn else {
            notifyCooldown = notifyCooldown.filter { _, date in
                Date().timeIntervalSince(date) < 30
            }
            return
        }

        let candidates = identifier.scoreCandidates(
            runningApps: NSWorkspace.shared.runningApplications,
            frontmost: NSWorkspace.shared.frontmostApplication
        )

        var targets: [ProcessCandidate] = []
        for candidate in candidates.prefix(12) {
            let key = sessionKey(for: candidate.app)
            let decision = policy.decision(for: candidate.app)
            let action = GuardDecisionEngine.action(
                mode: mode,
                cameraOn: true,
                allowOnceActive: allowOnceSession.contains(key),
                policy: decision
            )
            switch action {
            case .ignore:
                continue
            case .allowSilently:
                if !loggedAllowKeys.contains(key) {
                    loggedAllowKeys.insert(key)
                    activityLog.record(ActivityEvent(app: candidate.app, action: .allowed, detail: "Allowlist"))
                }
            case .blockNow:
                targets.append(candidate)
            }
        }

        // Camera is on but heuristics found nobody — still stop the frontmost user app.
        if targets.isEmpty,
           let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != getpid(),
           front.activationPolicy == .regular {
            let app = AppIdentity(
                bundleID: front.bundleIdentifier ?? "",
                processName: front.localizedName ?? "App",
                displayName: front.localizedName
            )
            let key = sessionKey(for: app)
            if policy.decision(for: app) != .allowlisted, !allowOnceSession.contains(key) {
                targets.append(
                    ProcessCandidate(
                        pid: front.processIdentifier,
                        app: app,
                        score: 1,
                        confidence: 0.2
                    )
                )
            }
        }

        guard !targets.isEmpty else { return }

        for target in targets {
            _ = processController.forceKill(pid: target.pid)
            recordBlockIfNeeded(target.app)
        }

        // Re-read immediately; if still on, next tick continues killing.
        monitor.refresh()
        lastBlockedName = targets.first?.app.displayName
        iconState = .alert
        scheduleStatusClear()
    }

    private func recordBlockIfNeeded(_ app: AppIdentity) {
        let key = sessionKey(for: app)
        let now = Date()
        if let last = notifyCooldown[key], now.timeIntervalSince(last) < 8 {
            return
        }
        notifyCooldown[key] = now
        activityLog.record(ActivityEvent(app: app, action: .blocked, detail: "Locked"))
        notify(
            title: "Camera blocked",
            body: "\(app.displayName) was stopped so the camera LED stays off. Unlock MacCam to use the camera."
        )
    }

    private func scheduleStatusClear() {
        statusClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if !self.monitor.isCameraOn {
                    self.lastBlockedName = nil
                    self.refreshStatus()
                }
            }
        }
        statusClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func refreshStatus() {
        switch mode {
        case .locked:
            if monitor.isCameraOn {
                iconState = .alert
                status = .clearing(appName: lastBlockedName ?? "camera app")
            } else if let name = lastBlockedName {
                iconState = .locked
                status = .blocked(appName: name)
            } else {
                iconState = .locked
                status = .protected
            }
        case .unlocked:
            iconState = .unlocked
            if monitor.isCameraOn, let candidate = identifier.identifyLikelyCameraUser() {
                status = .cameraActive(appName: candidate.app.displayName)
            } else {
                status = .unlocked
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
