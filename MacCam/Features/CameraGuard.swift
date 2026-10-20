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
    case disabling
    case needsAdmin
    case cameraActive(appName: String)

    var label: String {
        switch self {
        case .protected:
            return "Camera disabled — LED off"
        case .unlocked:
            return "Camera available"
        case .disabling:
            return "Turning camera off…"
        case .needsAdmin:
            return "Password needed to turn LED off"
        case .cameraActive(let name):
            return "\(name) is using the camera"
        }
    }
}

protocol ProcessController {
    func forceKill(pid: pid_t) -> Bool
}

struct POSIXProcessController: ProcessController {
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
    /// True when user-level disable failed and admin password is required.
    @Published private(set) var needsAdminAuthorization: Bool = false
    @Published private(set) var isBusyDisabling: Bool = false

    let policy: PolicyStore
    let activityLog: ActivityLog
    let monitor: CameraMonitor
    let identifier: ProcessIdentifier
    let processController: ProcessController

    private let defaults: UserDefaults
    private let modeKey = "macCam.mode"
    private let notifyKey = "macCam.notifyOnAttempt"

    private var notifyCooldownUntil: Date = .distantPast
    private var lastDisable: Date = .distantPast
    private var adminAttemptedThisLockSession = false
    private var statusClearWork: DispatchWorkItem?
    private var tickTimer: Timer?
    private let lockedTick: TimeInterval = 0.20
    private let unlockedTick: TimeInterval = 0.40
    private let disableCooldown: TimeInterval = 0.90

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
        if mode == .locked {
            disableCameraNow(reason: "MacCam started", force: true, preferAdminIfNeeded: true)
        }
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        monitor.stop()
    }

    func setLocked(_ locked: Bool) {
        mode = locked ? .locked : .unlocked
        if locked {
            adminAttemptedThisLockSession = false
            needsAdminAuthorization = false
            disableCameraNow(reason: "Privacy lock on", force: true, preferAdminIfNeeded: true)
        } else {
            needsAdminAuthorization = false
            isBusyDisabling = false
        }
        restartTickTimer()
        refreshStatus()
    }

    /// User tapped “Authorize to turn LED off” — shows the macOS password dialog.
    func authorizeAdminDisable() {
        guard mode == .locked else { return }
        adminAttemptedThisLockSession = false
        disableCameraNow(reason: "Admin authorize", force: true, preferAdminIfNeeded: true)
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
            enforceDisabledCamera()
        }
        refreshStatus()
    }

    private func enforceDisabledCamera() {
        guard mode == .locked else { return }
        guard !isBusyDisabling else { return }

        let allowlistedLikely: Bool = {
            guard let candidate = identifier.identifyLikelyCameraUser() else { return false }
            return policy.decision(for: candidate.app) == .allowlisted
        }()

        let action = GuardDecisionEngine.action(
            mode: mode,
            cameraOn: monitor.isCameraOn,
            allowlistedUserLikely: allowlistedLikely
        )

        switch action {
        case .ignore, .allowSilently:
            return
        case .disableHardware:
            // Keep trying unprivileged; escalate to admin only once per lock session unless user taps Authorize.
            disableCameraNow(
                reason: "Locked — camera disabled",
                force: false,
                preferAdminIfNeeded: !adminAttemptedThisLockSession
            )
        }
    }

    private func disableCameraNow(reason: String, force: Bool, preferAdminIfNeeded: Bool) {
        let now = Date()
        if !force, now.timeIntervalSince(lastDisable) < disableCooldown {
            if monitor.isCameraOn {
                iconState = .alert
                status = needsAdminAuthorization ? .needsAdmin : .disabling
            }
            return
        }
        lastDisable = now
        isBusyDisabling = true
        iconState = .alert
        status = .disabling

        let controller = processController
        let shouldEscalate = preferAdminIfNeeded

        Task { @MainActor [weak self] in
            guard let self else { return }

            let killFn: (pid_t) -> Bool = { pid in
                controller.forceKill(pid: pid)
            }

            // Pass 1: user-level (no password) on a background thread.
            await Task.detached(priority: .userInitiated) {
                _ = CameraStackReset.disableCameraHardware(using: killFn, allowAdminEscalation: false)
            }.value

            try? await Task.sleep(nanoseconds: 250_000_000)
            self.monitor.refresh()

            var usedAdmin = false
            if self.monitor.isCameraOn && shouldEscalate {
                self.adminAttemptedThisLockSession = true
                self.status = .needsAdmin
                // Pass 2: macOS password dialog — camera daemons are usually root-owned.
                await Task.detached(priority: .userInitiated) {
                    _ = CameraStackReset.disableCameraHardware(using: killFn, allowAdminEscalation: true)
                }.value
                usedAdmin = true
                try? await Task.sleep(nanoseconds: 350_000_000)
                self.monitor.refresh()
            }

            let off = !self.monitor.isCameraOn
            self.needsAdminAuthorization = !off && self.mode == .locked
            self.isBusyDisabling = false

            let system = AppIdentity(
                bundleID: "com.maccam.camera",
                processName: "Camera",
                displayName: "Camera"
            )
            if Date() >= self.notifyCooldownUntil {
                self.notifyCooldownUntil = Date().addingTimeInterval(12)
                let detail = off
                    ? (usedAdmin ? "Disabled (admin)" : "Disabled")
                    : "Still on — admin required"
                self.activityLog.record(ActivityEvent(app: system, action: .blocked, detail: detail))
                if off {
                    self.notify(
                        title: "Camera disabled",
                        body: "The camera LED should be off. Apps stay open — unlock to use the camera."
                    )
                } else {
                    self.notify(
                        title: "Password needed",
                        body: "Click “Authorize to turn LED off” in MacCam and enter your Mac password."
                    )
                }
            }
            self.refreshStatus()
        }
    }

    private func refreshStatus() {
        switch mode {
        case .locked:
            if isBusyDisabling {
                iconState = .alert
                status = .disabling
            } else if monitor.isCameraOn {
                iconState = .alert
                status = needsAdminAuthorization ? .needsAdmin : .disabling
            } else {
                iconState = .locked
                status = .protected
                needsAdminAuthorization = false
            }
        case .unlocked:
            iconState = .unlocked
            needsAdminAuthorization = false
            if monitor.isCameraOn, let candidate = identifier.identifyLikelyCameraUser() {
                status = .cameraActive(appName: candidate.app.displayName)
            } else {
                status = .unlocked
            }
        }
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
