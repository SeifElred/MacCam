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
            return "Password needed — tap below"
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
    @Published private(set) var lastFailureHint: String = ""
    @Published private(set) var didCopyFixCommand: Bool = false

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
    private var lastTriggerPulse: Date = .distantPast
    private var holdSuppressUntil: Date = .distantPast
    private var didAutoPromptInstall = false
    private var tickTimer: Timer?
    private let lockedTick: TimeInterval = 0.10
    private let unlockedTick: TimeInterval = 0.40
    private let disableCooldown: TimeInterval = 0.25
    private let maxVerifyAttempts = 16

    init(
        policy: PolicyStore = PolicyStore(),
        activityLog: ActivityLog = ActivityLog(),
        monitor: CameraMonitor = CameraMonitor(pollInterval: 0.08),
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

        guard mode == .locked else { return }

        // Minimize “forgot to click setup”: prompt install automatically once per launch.
        if !helperInstalled, !didAutoPromptInstall {
            didAutoPromptInstall = true
            installHelperAndDisable()
        } else {
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
            lastFailureHint = ""
            if !helperInstalled {
                installHelperAndDisable()
            } else {
                ensureCameraOff(reason: "Privacy lock on")
            }
        } else {
            needsAdminAuthorization = false
            isBusyDisabling = false
            holdSuppressUntil = .distantPast
            lastFailureHint = ""
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
        lastFailureHint = ""

        Task { @MainActor in
            let ok = await Task.detached(priority: .userInitiated) {
                CameraDisableHelper.install()
            }.value

            helperInstalled = CameraDisableHelper.isInstalled
            if ok || helperInstalled {
                await forceDisableUntilOff(reason: "Helper installed", useAdminFallback: true)
            } else {
                // Install cancelled / blocked — still try a direct admin multi-pulse clear.
                let cleared = await Task.detached(priority: .userInitiated) {
                    CameraDisableHelper.privilegedKillDaemons()
                }.value
                try? await Task.sleep(nanoseconds: 250_000_000)
                monitor.refresh()
                if !monitor.isCameraOn {
                    needsAdminAuthorization = false
                    lastFailureHint = ""
                    beginHoldSuppress()
                } else {
                    needsAdminAuthorization = true
                    lastFailureHint = cleared
                        ? "Camera still on. Tap again, or copy the Terminal fix."
                        : "Password cancelled or blocked. Tap again, or copy the Terminal fix."
                    status = .needsAdmin
                }
                isBusyDisabling = false
            }
            refreshStatus()
        }
    }

    func authorizeAdminDisable() {
        guard mode == .locked else { return }
        if !helperInstalled || !CameraDisableHelper.isHealthy {
            installHelperAndDisable()
        } else {
            Task { @MainActor in
                await forceDisableUntilOff(reason: "Manual clear", useAdminFallback: true)
            }
        }
    }

    func copyTerminalFixCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(CameraDisableHelper.terminalFixCommand, forType: .string)
        didCopyFixCommand = true
        lastFailureHint = "Copied. Paste in Terminal, press Return, enter password."
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.didCopyFixCommand = false
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

        guard mode == .locked else { return }

        // After a successful clear, keep pulsing briefly so apps can't instantly re-grab.
        if Date() < holdSuppressUntil, helperInstalled {
            pulseHelperIfDue()
        }

        enforceDisabledCamera()
        refreshStatus()
    }

    private func enforceDisabledCamera() {
        guard mode == .locked, !isBusyDisabling else { return }

        let allowlistedLikely: Bool = {
            guard let candidate = identifier.identifyLikelyCameraUser() else { return false }
            return policy.decision(for: candidate.app) == .allowlisted
        }()

        // Fast path: camera on → pulse helper every 150ms without waiting for full async job.
        if monitor.isCameraOn, helperInstalled, allowlistedLikely == false {
            pulseHelperIfDue()
        }

        let action = GuardDecisionEngine.action(
            mode: mode,
            cameraOn: monitor.isCameraOn,
            allowlistedUserLikely: allowlistedLikely
        )

        switch action {
        case .ignore, .allowSilently:
            return
        case .disableHardware:
            ensureCameraOff(reason: "Camera on while locked")
        }
    }

    private func pulseHelperIfDue() {
        let now = Date()
        guard now.timeIntervalSince(lastTriggerPulse) >= 0.15 else { return }
        lastTriggerPulse = now
        _ = CameraDisableHelper.requestDisable()
        CameraDisableHelper.unprivilegedKillDaemons { [processController] pid in
            processController.forceKill(pid: pid)
        }
    }

    private func ensureCameraOff(reason: String) {
        let now = Date()
        if isBusyDisabling { return }
        if now.timeIntervalSince(lastDisable) < disableCooldown { return }
        lastDisable = now

        if !helperInstalled {
            needsAdminAuthorization = true
            status = .needsSetup
            iconState = .alert
            // Don't only wait for a click — escalate automatically once.
            if !didAutoPromptInstall {
                didAutoPromptInstall = true
                installHelperAndDisable()
            }
            return
        }

        Task { @MainActor in
            await forceDisableUntilOff(reason: reason, useAdminFallback: true)
        }
    }

    private func forceDisableUntilOff(reason: String, useAdminFallback: Bool) async {
        isBusyDisabling = true
        status = .disabling
        iconState = .alert
        lastFailureHint = ""

        let killFn: (pid_t) -> Bool = { [processController] pid in
            processController.forceKill(pid: pid)
        }

        var off = false
        for attempt in 1...maxVerifyAttempts {
            await Task.detached(priority: .userInitiated) {
                CameraDisableHelper.unprivilegedKillDaemons(using: killFn)
                _ = CameraDisableHelper.requestDisable()
            }.value

            try? await Task.sleep(nanoseconds: 120_000_000)
            monitor.refresh()
            if !monitor.isCameraOn {
                off = true
                break
            }

            // Escalate early and often — cached admin auth avoids repeat prompts.
            if useAdminFallback, attempt == 1 || attempt == 2 || attempt % 3 == 0 {
                await Task.detached(priority: .userInitiated) {
                    _ = CameraDisableHelper.privilegedKillDaemons()
                }.value
                try? await Task.sleep(nanoseconds: 180_000_000)
                monitor.refresh()
                if !monitor.isCameraOn {
                    off = true
                    break
                }
            }
        }

        isBusyDisabling = false
        needsAdminAuthorization = !off && mode == .locked

        if off {
            lastFailureHint = ""
            beginHoldSuppress()
        } else {
            lastFailureHint = "Still on after retries. Tap below again, or copy the Terminal fix."
        }

        let system = AppIdentity(bundleID: "com.maccam.camera", processName: "Camera", displayName: "Camera")
        if Date() >= notifyCooldownUntil {
            notifyCooldownUntil = Date().addingTimeInterval(8)
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
                    body: "Green LED should be off. Apps were not quit."
                )
            } else {
                notify(
                    title: "Action needed",
                    body: "Enter your password when asked, or use the copied Terminal command."
                )
            }
        }
        refreshStatus()
    }

    private func beginHoldSuppress() {
        // Keep clearing for a few seconds so a client can't instantly reopen the sensor.
        holdSuppressUntil = Date().addingTimeInterval(5)
    }

    private func refreshStatus() {
        helperInstalled = CameraDisableHelper.isInstalled
        switch mode {
        case .locked:
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
