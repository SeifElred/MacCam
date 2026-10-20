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
    case stuckLED
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
        case .stuckLED:
            return "Stuck LED — restart Mac"
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
    @Published private(set) var restrictionActive: Bool = false
    @Published private(set) var needsAdminAuthorization: Bool = false
    @Published private(set) var isBusyDisabling: Bool = false
    @Published private(set) var suggestRestartForStuckLED: Bool = false
    @Published private(set) var lastFailureHint: String = ""
    @Published private(set) var didCopyFixCommand: Bool = false
    @Published private(set) var lastActionDetail: String = ""

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
    private var consecutiveOffWhileRestricted = 0
    private var tickTimer: Timer?
    private let lockedTick: TimeInterval = 0.10
    private let unlockedTick: TimeInterval = 0.40
    private let disableCooldown: TimeInterval = 0.30
    private let maxVerifyAttempts = 14

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
        self.restrictionActive = CameraDisableHelper.isRestrictionActive
        refreshStatus()
    }

    func start() {
        monitor.start()
        restartTickTimer()
        requestNotificationPermissionIfNeeded()
        helperInstalled = CameraDisableHelper.isInstalled
        restrictionActive = CameraDisableHelper.isRestrictionActive

        guard mode == .locked else { return }

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
            suggestRestartForStuckLED = false
            lastFailureHint = ""
            if !helperInstalled {
                installHelperAndDisable()
            } else {
                ensureCameraOff(reason: "Privacy lock on")
            }
        } else {
            Task { @MainActor in
                await restoreCameraAccess(reason: "Privacy lock off")
            }
        }
        restartTickTimer()
        refreshStatus()
    }

    func installHelperAndDisable() {
        guard mode == .locked else { return }
        isBusyDisabling = true
        status = .disabling
        iconState = .alert
        lastFailureHint = ""
        suggestRestartForStuckLED = false

        Task { @MainActor in
            _ = CameraRestrictionProfile.writeToSupportDirectory()
            let ok = await Task.detached(priority: .userInitiated) {
                CameraDisableHelper.install()
            }.value

            helperInstalled = CameraDisableHelper.isInstalled
            if ok || helperInstalled {
                await forceDisableUntilOff(reason: "Helper + restriction installed", useAdminFallback: true)
            } else {
                let cleared = await Task.detached(priority: .userInitiated) {
                    CameraDisableHelper.privilegedLockFull()
                }.value
                try? await Task.sleep(nanoseconds: 300_000_000)
                monitor.refresh()
                restrictionActive = CameraDisableHelper.isRestrictionActive
                if !monitor.isCameraOn {
                    needsAdminAuthorization = false
                    lastFailureHint = ""
                    beginHoldSuppress()
                    lastActionDetail = "Locked via admin fallback"
                } else {
                    needsAdminAuthorization = true
                    lastFailureHint = cleared
                        ? "Still on. Tap again, copy Terminal fix, or restart Mac if LED is stuck."
                        : "Password cancelled. Tap again to enable protection."
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
                await forceDisableUntilOff(reason: "Manual lock", useAdminFallback: true)
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

    func requestRestartMac() {
        // Opens restart confirmation via AppleScript (user still confirms).
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"System Events\" to restart"
        ]
        try? process.run()
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
        restrictionActive = CameraDisableHelper.isRestrictionActive

        if mode == .unlocked {
            refreshStatus()
            return
        }

        if Date() < holdSuppressUntil, helperInstalled {
            pulseLockIfDue()
        }

        // Stuck LED heuristic: restriction on, CMIO off, but we previously failed visually.
        if restrictionActive, !monitor.isCameraOn {
            consecutiveOffWhileRestricted += 1
        } else {
            consecutiveOffWhileRestricted = 0
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

        if monitor.isCameraOn, helperInstalled, !allowlistedLikely {
            pulseLockIfDue()
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

    private func pulseLockIfDue() {
        let now = Date()
        guard now.timeIntervalSince(lastTriggerPulse) >= 0.18 else { return }
        lastTriggerPulse = now
        _ = CameraDisableHelper.requestLock()
        CameraDisableHelper.unprivilegedKillDaemons { [processController] pid in
            processController.forceKill(pid: pid)
        }
    }

    private func ensureCameraOff(reason: String) {
        if isBusyDisabling { return }
        let now = Date()
        if now.timeIntervalSince(lastDisable) < disableCooldown { return }
        lastDisable = now

        if !helperInstalled {
            needsAdminAuthorization = true
            status = .needsSetup
            iconState = .alert
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

    /// Primary: restriction profile. Secondary: bootout/kill. Success only when CMIO reports off.
    private func forceDisableUntilOff(reason: String, useAdminFallback: Bool) async {
        isBusyDisabling = true
        status = .disabling
        iconState = .alert
        lastFailureHint = ""
        suggestRestartForStuckLED = false
        lastActionDetail = reason

        let killFn: (pid_t) -> Bool = { [processController] pid in
            processController.forceKill(pid: pid)
        }

        var off = false
        for attempt in 1...maxVerifyAttempts {
            await Task.detached(priority: .userInitiated) {
                CameraDisableHelper.unprivilegedKillDaemons(using: killFn)
                _ = CameraDisableHelper.requestLock()
            }.value

            try? await Task.sleep(nanoseconds: 150_000_000)
            monitor.refresh()
            restrictionActive = CameraDisableHelper.isRestrictionActive
            if !monitor.isCameraOn {
                off = true
                break
            }

            if useAdminFallback, attempt == 1 || attempt == 2 || attempt % 3 == 0 {
                await Task.detached(priority: .userInitiated) {
                    _ = CameraDisableHelper.privilegedLockFull()
                }.value
                try? await Task.sleep(nanoseconds: 200_000_000)
                monitor.refresh()
                restrictionActive = CameraDisableHelper.isRestrictionActive
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
            suggestRestartForStuckLED = false
            beginHoldSuppress()
            lastActionDetail = "\(reason) — verified off"
        } else {
            // If profile is active but CMIO still on, or profile active and we can't clear LED path:
            if restrictionActive {
                suggestRestartForStuckLED = true
                lastFailureHint = "OS camera ban is on, but LED may be stuck. Restart Mac to clear hardware state."
                lastActionDetail = "\(reason) — restriction on, sensor still reported"
            } else {
                lastFailureHint = "Still on. Tap below, copy Terminal fix, or restart if LED is stuck."
                lastActionDetail = "\(reason) — still on"
            }
        }

        let system = AppIdentity(bundleID: "com.maccam.camera", processName: "Camera", displayName: "Camera")
        if Date() >= notifyCooldownUntil {
            notifyCooldownUntil = Date().addingTimeInterval(8)
            activityLog.record(
                ActivityEvent(
                    app: system,
                    action: .blocked,
                    detail: lastActionDetail
                )
            )
            if off {
                notify(title: "Camera disabled", body: "Policy applied. Green LED should be off. Apps were not quit.")
            } else if suggestRestartForStuckLED {
                notify(title: "Stuck LED?", body: "Restart your Mac — this clears a known macOS camera LED glitch.")
            } else {
                notify(title: "Action needed", body: "Enter your password when asked, or use the Terminal fix.")
            }
        }
        refreshStatus()
    }

    /// Public so the menu can force a restore if apps still cannot see the camera.
    func restoreCameraNow() {
        Task { @MainActor in
            await restoreCameraAccess(reason: "Manual restore")
        }
    }

    func copyTerminalRestoreCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(CameraDisableHelper.terminalRestoreCommand, forType: .string)
        didCopyFixCommand = true
        lastFailureHint = "Copied restore command. Paste in Terminal, press Return, enter password."
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.didCopyFixCommand = false
        }
    }

    private func restoreCameraAccess(reason: String) async {
        isBusyDisabling = true
        status = .disabling
        needsAdminAuthorization = false
        suggestRestartForStuckLED = false
        holdSuppressUntil = .distantPast
        lastFailureHint = ""
        lastActionDetail = "Restoring camera…"

        // 1) Ask root helper to unlock (remove profile + enable/kickstart daemon).
        if helperInstalled {
            await Task.detached(priority: .userInitiated) {
                _ = CameraDisableHelper.requestUnlock()
            }.value
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        restrictionActive = CameraDisableHelper.isRestrictionActive

        // 2) Always run privileged unlock too — helper WatchPaths can miss; disable may have stuck.
        //    macOS often caches the password briefly after earlier prompts.
        await Task.detached(priority: .userInitiated) {
            _ = CameraDisableHelper.privilegedUnlockFull()
        }.value
        try? await Task.sleep(nanoseconds: 500_000_000)

        restrictionActive = CameraDisableHelper.isRestrictionActive
        isBusyDisabling = false

        if restrictionActive {
            lastFailureHint = "OS camera ban still on. Tap Restore camera, or copy the restore Terminal command."
            lastActionDetail = "\(reason) — ban still active"
        } else {
            lastFailureHint = ""
            lastActionDetail = "\(reason) — camera restored"
        }

        activityLog.record(
            ActivityEvent(
                app: AppIdentity(bundleID: "com.maccam.camera", processName: "Camera", displayName: "Camera"),
                action: .allowed,
                detail: lastActionDetail
            )
        )
        notify(
            title: restrictionActive ? "Camera still blocked" : "Camera restored",
            body: restrictionActive
                ? "Enter your password if asked, or run the restore Terminal command."
                : "Apps should see the camera again. Quit/reopen Photo Booth or FaceTime if needed."
        )
        refreshStatus()
    }

    private func beginHoldSuppress() {
        holdSuppressUntil = Date().addingTimeInterval(5)
    }

    private func refreshStatus() {
        helperInstalled = CameraDisableHelper.isInstalled
        restrictionActive = CameraDisableHelper.isRestrictionActive

        switch mode {
        case .locked:
            if !monitor.isCameraOn && !isBusyDisabling {
                iconState = .locked
                status = .protected
                needsAdminAuthorization = false
            } else if isBusyDisabling {
                iconState = .alert
                status = .disabling
            } else if suggestRestartForStuckLED {
                iconState = .alert
                status = .stuckLED
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
            suggestRestartForStuckLED = false
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
