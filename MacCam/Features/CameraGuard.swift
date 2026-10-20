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
    case cameraActive(appName: String)

    var label: String {
        switch self {
        case .protected:
            return "Camera disabled — LED off"
        case .unlocked:
            return "Camera available"
        case .disabling:
            return "Turning camera off…"
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
    private var statusClearWork: DispatchWorkItem?
    private var tickTimer: Timer?
    private let lockedTick: TimeInterval = 0.15
    private let unlockedTick: TimeInterval = 0.40
    /// How often we may bounce the camera stack while something keeps turning it back on.
    private let disableCooldown: TimeInterval = 0.75

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
        // Opening MacCam while locked must clear the LED immediately.
        if mode == .locked {
            disableCameraNow(reason: "MacCam started", force: true)
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
            disableCameraNow(reason: "Privacy lock on", force: true)
        }
        restartTickTimer()
        refreshStatus()
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

    /// Keep the camera hardware off while locked. Never quits user apps.
    private func enforceDisabledCamera() {
        guard mode == .locked else { return }

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
        case .ignore:
            return
        case .allowSilently:
            return
        case .disableHardware:
            disableCameraNow(reason: "Locked — camera disabled", force: false)
        }
    }

    private func disableCameraNow(reason: String, force: Bool) {
        let now = Date()
        if !force, now.timeIntervalSince(lastDisable) < disableCooldown {
            // Still show “turning off” if LED/sensor still reports on.
            if monitor.isCameraOn {
                iconState = .alert
                status = .disabling
            }
            return
        }
        lastDisable = now
        iconState = .alert
        status = .disabling

        _ = CameraStackReset.disableCameraHardware { pid in
            processController.forceKill(pid: pid)
        }

        // Re-check quickly; bounce again once if hardware is still claimed.
        monitor.refresh()
        if monitor.isCameraOn {
            _ = CameraStackReset.disableCameraHardware { pid in
                processController.forceKill(pid: pid)
            }
            monitor.refresh()
        }

        let system = AppIdentity(bundleID: "com.maccam.camera", processName: "Camera", displayName: "Camera")
        if now >= notifyCooldownUntil {
            notifyCooldownUntil = now.addingTimeInterval(10)
            activityLog.record(ActivityEvent(app: system, action: .blocked, detail: reason))
            notify(
                title: "Camera disabled",
                body: "MacCam turned the camera off. Apps stay open — unlock to use the camera again."
            )
        }

        scheduleStatusRefresh()
    }

    private func scheduleStatusRefresh() {
        statusClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.monitor.refresh()
                self?.refreshStatus()
                // If something turned the camera back on, disable again immediately.
                if self?.mode == .locked, self?.monitor.isCameraOn == true {
                    self?.disableCameraNow(reason: "Camera re-enabled by system", force: true)
                }
            }
        }
        statusClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func refreshStatus() {
        switch mode {
        case .locked:
            if monitor.isCameraOn {
                iconState = .alert
                status = .disabling
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
