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
    case needsSetup
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
        case .needsSetup:
            return "One-time setup required"
        case .needsAdmin:
            return "Password needed to finish"
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
    @Published private(set) var helperInstalled: Bool = CameraDisableHelper.isInstalled
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
    private var tickTimer: Timer?
    private let lockedTick: TimeInterval = 0.20
    private let unlockedTick: TimeInterval = 0.40
    private let disableCooldown: TimeInterval = 0.60
    private let maxVerifyAttempts = 12

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
        self.helperInstalled = CameraDisableHelper.isInstalled
        refreshStatus()
    }

    func start() {
        monitor.start()
        restartTickTimer()
        requestNotificationPermissionIfNeeded()
        helperInstalled = CameraDisableHelper.isInstalled
        if mode == .locked {
            ensureCameraOff(reason: "MacCam started")
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
            needsAdminAuthorization = false
            ensureCameraOff(reason: "Privacy lock on")
        } else {
            needsAdminAuthorization = false
            isBusyDisabling = false
        }
        restartTickTimer()
        refreshStatus()
    }

    /// One-time: install root helper (password once), then force LED off.
    func installHelperAndDisable() {
        guard mode == .locked else { return }
        isBusyDisabling = true
        status = .disabling
        iconState = .alert

        Task { @MainActor in
            let ok = await Task.detached(priority: .userInitiated) {
                CameraDisableHelper.install()
            }.value

            helperInstalled = CameraDisableHelper.isInstalled || ok
            if helperInstalled {
                await forceDisableUntilOff(reason: "Helper installed", useAdminFallback: true)
            } else {
                needsAdminAuthorization = true
                isBusyDisabling = false
                status = .needsAdmin
                notify(title: "Setup incomplete", body: "Password was cancelled. Try again to enable LED protection.")
            }
            refreshStatus()
        }
    }

    /// Retry disable (uses helper if installed, otherwise admin prompt).
    func authorizeAdminDisable() {
        guard mode == .locked else { return }
        if !helperInstalled {
            installHelperAndDisable()
        } else {
            ensureCameraOff(reason: "Authorize retry")
        }
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
        helperInstalled = CameraDisableHelper.isInstalled
        if mode == .locked {
            enforceDisabledCamera()
        }
        refreshStatus()
    }

    private func enforceDisabledCamera() {
        guard mode == .locked, !isBusyDisabling else { return }

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
            ensureCameraOff(reason: "Camera turned on while locked")
        }
    }

    private func ensureCameraOff(reason: String) {
        let now = Date()
        if now.timeIntervalSince(lastDisable) < disableCooldown, isBusyDisabling { return }
        lastDisable = now

        if !helperInstalled {
            // Cannot guarantee LED off without root helper on M1 Pro.
            needsAdminAuthorization = true
            status = .needsSetup
            iconState = .alert
            return
        }

        Task { @MainActor in
            await forceDisableUntilOff(reason: reason, useAdminFallback: true)
        }
    }

    /// Keep disabling until CoreMediaIO reports the camera (LED) is off, or attempts exhausted.
    private func forceDisableUntilOff(reason: String, useAdminFallback: Bool) async {
        isBusyDisabling = true
        status = .disabling
        iconState = .alert

        let killFn: (pid_t) -> Bool = { [processController] pid in
            processController.forceKill(pid: pid)
        }

        var off = false
        for attempt in 1...maxVerifyAttempts {
            await Task.detached(priority: .userInitiated) {
                _ = CameraStackReset.disableCameraHardware(using: killFn, strategy: .helperOnly)
            }.value

            try? await Task.sleep(nanoseconds: 200_000_000)
            monitor.refresh()
            if !monitor.isCameraOn {
                off = true
                break
            }

            // Every few failed attempts, escalate with admin kill (M1 appleh13camerad is root).
            if useAdminFallback, attempt == 3 || attempt == 7 {
                await Task.detached(priority: .userInitiated) {
                    _ = CameraDisableHelper.privilegedKillDaemons()
                }.value
                try? await Task.sleep(nanoseconds: 300_000_000)
                monitor.refresh()
                if !monitor.isCameraOn {
                    off = true
                    break
                }
            }
        }

        isBusyDisabling = false
        needsAdminAuthorization = !off && mode == .locked

        let system = AppIdentity(bundleID: "com.maccam.camera", processName: "Camera", displayName: "Camera")
        if Date() >= notifyCooldownUntil {
            notifyCooldownUntil = Date().addingTimeInterval(10)
            activityLog.record(
                ActivityEvent(
                    app: system,
                    action: .blocked,
                    detail: off ? "\(reason) — LED off verified" : "\(reason) — still on"
                )
            )
            if off {
                notify(
                    title: "Camera disabled",
                    body: "Green LED should be off. Apps were not quit — unlock to use the camera."
                )
            } else {
                notify(
                    title: "Still need authorization",
                    body: "Tap “Enable LED protection” and enter your Mac password."
                )
            }
        }
        refreshStatus()
    }

    private func refreshStatus() {
        helperInstalled = CameraDisableHelper.isInstalled
        switch mode {
        case .locked:
            // Success is ONLY when hardware reports off.
            if !monitor.isCameraOn && !isBusyDisabling {
                iconState = .locked
                status = .protected
                needsAdminAuthorization = false
            } else if isBusyDisabling {
                iconState = .alert
                status = .disabling
            } else if !helperInstalled {
                iconState = .alert
                status = .needsSetup
                needsAdminAuthorization = true
            } else {
                iconState = .alert
                status = needsAdminAuthorization ? .needsAdmin : .disabling
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
