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
            return "Apps blocked from camera"
        case .unlocked:
            return "Camera available"
        case .disabling:
            return "Applying camera ban…"
        case .needsSetup:
            return "One-time setup needed"
        case .needsAdmin:
            return "Enter password once to enable"
        case .stuckLED:
            return "Apps blocked (LED follows ISP)"
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
    /// When set, lock will auto-return after this time (quick allow window).
    @Published private(set) var temporaryUnlockUntil: Date?

    let policy: PolicyStore
    let activityLog: ActivityLog
    let monitor: CameraMonitor
    let identifier: ProcessIdentifier
    let processController: ProcessController

    private let defaults: UserDefaults
    private let modeKey = "macCam.mode"
    private let notifyKey = "macCam.notifyOnAttempt"

    private var notifyCooldownUntil: Date = .distantPast
    private var accessPromptCooldownUntil: Date = .distantPast
    private var lastDisable: Date = .distantPast
    private var lastTriggerPulse: Date = .distantPast
    private var lastLEDChill: Date = .distantPast
    private var ledWarmSince: Date?
    private var holdSuppressUntil: Date = .distantPast
    /// After Allow, ignore re-lock / prompts briefly so the helper can finish unlocking.
    private var unlockGraceUntil: Date = .distantPast
    /// While we quit+reopen Photo Booth after Allow, ignore terminate notifications (else we re-lock instantly).
    private var ignoreCameraTerminationsUntil: Date = .distantPast
    /// True after user tapped Allow — re-lock automatically when camera apps quit.
    private var sessionAllowActive = false
    private var didAutoPromptInstall = false
    private var consecutiveOffWhileRestricted = 0
    private var tickTimer: Timer?
    private var temporaryUnlockTimer: Timer?
    /// Locked: poll often enough to catch ISP re-warm, but never CMIO-enumerate.
    private let lockedTick: TimeInterval = 2.0
    /// Unlocked: check quickly so quitting Photo Booth re-locks without a long wait.
    private let unlockedTick: TimeInterval = 1.5
    private let disableCooldown: TimeInterval = 2.0
    /// Soft-kill cooldown must exceed ~4s DeferredPowerOff or kill loops keep the LED on.
    private let ledChillCooldown: TimeInterval = 5.0
    private let maxVerifyAttempts = 3
    private var didPresentRestrictionProfile = false
    private var didHeavyStartThisSession = false

    init(
        policy: PolicyStore = PolicyStore(),
        activityLog: ActivityLog = ActivityLog(),
        monitor: CameraMonitor = CameraMonitor(pollInterval: 10.0),
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
        requestNotificationPermissionIfNeeded()
        helperInstalled = CameraDisableHelper.isInstalled
        CameraDisableHelper.invalidateRestrictionCache()
        restrictionActive = CameraDisableHelper.isRestrictionActive

        // Helper lock_state wins — never leave UI "unlocked" while the OS ban is on
        // (that made MacCam CMIO-poll and re-light the LED).
        if restrictionActive, mode != .locked {
            mode = .locked
        }

        // Suspend CMIO BEFORE any refresh — enumeration = ConnectClient = LED on.
        syncHardwarePollingWithRestriction()
        monitor.start()
        restartTickTimer()
        refreshStatus()

        guard mode == .locked else { return }

        if !CameraDisableHelper.isHelperCurrent {
            lastFailureHint = "One-time update: tap Enable Camera Lock and enter your password once (faster Allow + LED fix)."
            needsAdminAuthorization = true
        }

        if restrictionActive {
            lastActionDetail = "Locked — CMIO poll paused (keeps LED cold)"
            suggestRestartForStuckLED = false
            if CameraDisableHelper.isHelperCurrent {
                lastFailureHint = ""
            }
            Task { @MainActor in
                await chillLEDUntilCold(reason: "MacCam started locked")
            }
            return
        }

        guard !didHeavyStartThisSession else { return }
        didHeavyStartThisSession = true
        Task { @MainActor in
            await forceDisableUntilOff(reason: "MacCam started", useAdminFallback: false)
        }
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        clearTemporaryUnlock()
        monitor.stop()
    }

    func setLocked(_ locked: Bool) {
        if locked, Date() < unlockGraceUntil {
            // Don't slam the door while Allow is still unlocking.
            return
        }
        mode = locked ? .locked : .unlocked
        if locked {
            clearTemporaryUnlock()
            sessionAllowActive = false
            needsAdminAuthorization = false
            suggestRestartForStuckLED = false
            didPresentRestrictionProfile = false
            lastFailureHint = ""
            ledWarmSince = nil
            // Quit camera apps immediately — any CMIO client keeps the green LED on.
            terminateKnownCameraApps()
            restrictionActive = CameraDisableHelper.isRestrictionActive
            syncHardwarePollingWithRestriction()
            if !CameraDisableHelper.isInstalled {
                lastFailureHint = "One-time setup: tap Enable Camera Lock and enter your Mac password once."
                installHelperAndDisable()
            } else {
                lastActionDetail = "Camera locked"
                lastFailureHint = ""
                Task { @MainActor in
                    _ = await Task.detached(priority: .userInitiated) {
                        CameraDisableHelper.lockPasswordless()
                    }.value
                    restrictionActive = CameraDisableHelper.isRestrictionActive
                    syncHardwarePollingWithRestriction()
                    await chillLEDUntilCold(reason: "Camera locked")
                    suggestRestartForStuckLED = false
                    lastFailureHint = restrictionActive ? "" : "Lock didn’t apply — try the toggle again."
                    refreshStatus()
                }
            }
        } else {
            didPresentRestrictionProfile = false
            if unlockGraceUntil < Date() {
                unlockGraceUntil = Date().addingTimeInterval(5)
            }
            accessPromptCooldownUntil = Date().addingTimeInterval(8)
            ignoreCameraTerminationsUntil = max(ignoreCameraTerminationsUntil, Date().addingTimeInterval(4))
            Task { @MainActor in
                await restoreCameraAccess(reason: "Privacy lock off")
            }
        }
        restartTickTimer()
        refreshStatus()
    }

    /// Bundle URL of the app that should be relaunched after a successful unlock.
    private var pendingRelaunchURL: URL?
    private var pendingRelaunchBundleID: String?

    /// One-tap: remove the OS ban so FaceTime / Zoom / etc. can open the camera now.
    /// Does **not** quit the user's app — unlock + refresh CMIO so the same process keeps running.
    func useCameraNow(relaunchFrontApp: Bool = true) {
        clearTemporaryUnlock()
        sessionAllowActive = true
        if relaunchFrontApp {
            if pendingRelaunchBundleID == nil, let app = Self.cameraAppToRelaunch() {
                pendingRelaunchBundleID = app.bundleIdentifier
                pendingRelaunchURL = app.bundleURL
            }
            if pendingRelaunchBundleID == nil {
                pendingRelaunchBundleID = "com.apple.PhotoBooth"
            }
        }
        // No intentional quit — do not ignore terminations (auto re-lock must work).
        ignoreCameraTerminationsUntil = .distantPast
        unlockGraceUntil = Date().addingTimeInterval(4)
        setLocked(false)
    }

    /// Call when a camera app quits — if we Allowed this session, lock again.
    func handleCameraAppTerminated(bundleID: String?) {
        guard sessionAllowActive || mode == .unlocked else { return }
        // Relaunch after Allow terminates the old Photo Booth — do NOT treat that as "user quit".
        if Date() < ignoreCameraTerminationsUntil { return }
        // Still another known camera app running? Keep unlocked.
        if Self.anyKnownCameraAppRunning() { return }
        sessionAllowActive = false
        unlockGraceUntil = .distantPast
        setLocked(true)
        notify(title: "Camera locked", body: "Camera apps closed — locking and turning the LED off.")
    }

    private static func anyKnownCameraAppRunning() -> Bool {
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier,
                  ProcessIdentifier.knownCameraApps[bid] != nil,
                  app.activationPolicy == .regular else { continue }
            return true
        }
        return false
    }

    private static func cameraAppToRelaunch() -> NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, let bid = front.bundleIdentifier,
           ProcessIdentifier.knownCameraApps[bid] != nil {
            return front
        }
        // Photo Booth / FaceTime running but not frontmost
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier,
                  ProcessIdentifier.knownCameraApps[bid] != nil,
                  app.activationPolicy == .regular else { continue }
            if bid.contains("PhotoBooth") || bid.contains("FaceTime") || bid.contains("zoom") {
                return app
            }
        }
        return front
    }

    /// Unlock for a short window, then automatically re-lock (reinstall ban).
    func useCameraForMinutes(_ minutes: Int) {
        let mins = max(1, minutes)
        useCameraNow(relaunchFrontApp: true)
        let until = Date().addingTimeInterval(TimeInterval(mins * 60))
        temporaryUnlockUntil = until
        temporaryUnlockTimer?.invalidate()
        temporaryUnlockTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(mins * 60), repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.temporaryUnlockUntil = nil
                self.temporaryUnlockTimer = nil
                self.sessionAllowActive = false
                if self.mode == .unlocked {
                    self.setLocked(true)
                    self.notify(title: "Camera locked again", body: "15-minute access ended.")
                }
            }
        }
        if let temporaryUnlockTimer {
            RunLoop.main.add(temporaryUnlockTimer, forMode: .common)
        }
        notify(title: "Camera allowed", body: "Locks again when you quit the app, or in \(mins) min.")
    }

    private func clearTemporaryUnlock() {
        temporaryUnlockTimer?.invalidate()
        temporaryUnlockTimer = nil
        temporaryUnlockUntil = nil
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
        // File-exists only (cheap). Restriction uses an 8s cache — never spawn profiles every tick.
        helperInstalled = CameraDisableHelper.isInstalled
        restrictionActive = CameraDisableHelper.isRestrictionActive
        syncHardwarePollingWithRestriction()

        // Ban active: never CMIO-poll / never kill appleh13camerad (both re-light LED).
        // Watch ISP power via ioreg and force it cold if anything wakes the sensor.
        if mode == .locked, restrictionActive {
            consecutiveOffWhileRestricted += 1
            monitor.refresh() // no-op while suspended; keeps isCameraOn false
            offerQuickAllowIfCameraAppActive()
            enforceLEDColdIfNeeded()
            refreshStatus()
            return
        }

        monitor.refresh()

        if mode == .unlocked {
            consecutiveOffWhileRestricted = 0
            // Safety net: if Allow session and no camera app left, re-lock.
            // Skip during Allow relaunch window (we briefly kill Photo Booth on purpose).
            if sessionAllowActive,
               Date() >= ignoreCameraTerminationsUntil,
               Date() >= unlockGraceUntil,
               !Self.anyKnownCameraAppRunning() {
                sessionAllowActive = false
                setLocked(true)
                notify(title: "Camera locked", body: "Camera apps closed — MacCam locked again.")
                return
            }
            refreshStatus()
            return
        }

        // Only pulse when CMIO still reports on AND ban is not yet active.
        if monitor.isCameraOn, helperInstalled, !restrictionActive {
            pulseLockIfDue()
        }

        consecutiveOffWhileRestricted = 0
        enforceDisabledCamera()
        refreshStatus()
    }

    /// Never CMIO-poll from MacCam — ConnectClient re-lights the green LED every time.
    private func syncHardwarePollingWithRestriction() {
        monitor.setHardwarePollingSuspended(true)
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
        // Slower than ~4s DeferredPowerOff — sub-second killall loops keep the LED on forever.
        guard now.timeIntervalSince(lastTriggerPulse) >= 5.0 else { return }
        lastTriggerPulse = now
        // Quiet only — opening .mobileconfig on a timer causes endless loading / dialogs.
        _ = CameraDisableHelper.requestLockQuiet()
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

    /// Soft kill + optional one-time profile install. Stops as soon as CMIO reports off (no dialog spam).
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

        monitor.refresh()
        restrictionActive = CameraDisableHelper.isRestrictionActive

        // Already restricted or sensor off — finish immediately (no dialogs / no killall loop).
        if restrictionActive || !monitor.isCameraOn {
            isBusyDisabling = false
            needsAdminAuthorization = false
            syncHardwarePollingWithRestriction()
            if restrictionActive {
                suggestRestartForStuckLED = false
                lastFailureHint = "Ban on — apps blocked. Leave idle ~4s so ISP can power off (same path as closing Photo Booth)."
                lastActionDetail = "\(reason) — ban active, CMIO poll paused"
            } else {
                lastActionDetail = "\(reason) — sensor off"
            }
            refreshStatus()
            return
        }

        // One-time helper install if missing (password once in lifetime).
        if !CameraDisableHelper.isInstalled, useAdminFallback || !didPresentRestrictionProfile {
            didPresentRestrictionProfile = true
            lastFailureHint = "Enter your Mac password once to install the MacCam helper."
            await Task.detached(priority: .userInitiated) {
                _ = CameraDisableHelper.install()
            }.value
            helperInstalled = CameraDisableHelper.isInstalled
        }

        var off = false
        for attempt in 1...maxVerifyAttempts {
            await Task.detached(priority: .userInitiated) {
                CameraDisableHelper.unprivilegedKillDaemons(using: killFn)
                _ = CameraDisableHelper.requestLockQuiet()
            }.value

            try? await Task.sleep(nanoseconds: 200_000_000)
            monitor.refresh()
            restrictionActive = CameraDisableHelper.isRestrictionActive
            if restrictionActive || !monitor.isCameraOn {
                off = true
                break
            }
            _ = attempt
        }

        isBusyDisabling = false
        needsAdminAuthorization = !off && mode == .locked

        syncHardwarePollingWithRestriction()

        if off {
            beginHoldSuppress()
            lastActionDetail = "\(reason) — verified off"
            if restrictionActive {
                lastFailureHint = "Apps blocked. LED should go dark ~4s after the last CMIO client (closing Photo Booth uses this same path)."
                suggestRestartForStuckLED = false
            } else {
                lastFailureHint = "Tap Enable Camera Lock once and enter your password — only once ever."
            }
        } else if restrictionActive {
            // Ban on but CMIO still reported on before we paused — offer restart once.
            suggestRestartForStuckLED = true
            lastFailureHint = "Ban on; ISP may be stuck warm. Wait ~10s, then restart once. If still green: cover / Apple Care."
            lastActionDetail = "\(reason) — restriction on"
        } else {
            lastFailureHint = "Still on. Tap Enable Camera Lock once if asked for a password, then wait a few seconds."
            lastActionDetail = "\(reason) — still on"
        }

        let system = AppIdentity(bundleID: "com.maccam.camera", processName: "Camera", displayName: "Camera")
        if Date() >= notifyCooldownUntil {
            notifyCooldownUntil = Date().addingTimeInterval(12)
            activityLog.record(
                ActivityEvent(
                    app: system,
                    action: .blocked,
                    detail: lastActionDetail
                )
            )
            if off, restrictionActive {
                notify(title: "Camera ban on", body: "Apps blocked. LED should idle off in ~4s if nothing else opens the camera.")
            } else if suggestRestartForStuckLED {
                notify(title: "ISP may be stuck", body: "Wait ~10s, then restart once. If LED stays green with ban on: cover / Apple Care.")
            } else if !restrictionActive {
                notify(title: "One-time setup", body: "Enter your Mac password once to install the MacCam helper. Never again after that.")
            } else {
                notify(title: "Camera locked", body: "Apps are blocked from the camera.")
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
        needsAdminAuthorization = false
        suggestRestartForStuckLED = false
        holdSuppressUntil = .distantPast
        lastFailureHint = ""
        lastActionDetail = "Unlocking…"
        syncHardwarePollingWithRestriction()

        if !CameraDisableHelper.isInstalled || !CameraDisableHelper.isHelperCurrent {
            lastActionDetail = "\(reason) — one-time helper update"
            _ = await Task.detached(priority: .userInitiated) {
                CameraDisableHelper.install()
            }.value
        }

        let unlocked = await Task.detached(priority: .userInitiated) {
            CameraDisableHelper.unlockPasswordless()
        }.value

        CameraDisableHelper.invalidateRestrictionCache()
        restrictionActive = CameraDisableHelper.isRestrictionActive
        let ready = unlocked || !restrictionActive

        if !ready {
            lastFailureHint = "Unlock failed — enter password once to repair, then Allow again."
            lastActionDetail = "\(reason) — unlock failed"
            notify(title: "Unlock failed", body: "Tap Enable Camera Lock once, then Allow again.")
        } else {
            lastFailureHint = ""
            lastActionDetail = "\(reason) — camera ready"
            // Keep the app open: bounce capture helpers so CMIO reappears (no quit/reopen).
            await refreshCameraForAllowedApp()
        }

        activityLog.record(
            ActivityEvent(
                app: AppIdentity(bundleID: "com.maccam.camera", processName: "Camera", displayName: "Camera"),
                action: .allowed,
                detail: lastActionDetail
            )
        )
        syncHardwarePollingWithRestriction()
        refreshStatus()
    }

    /// After Allow: unlock is done. Open the camera app once on an unlocked stack.
    /// (macOS will not reliably re-bind the camera inside an app that opened while banned —
    /// so we close it before the prompt and open it here. That is a deferred open, not a mid-use restart.)
    private func refreshCameraForAllowedApp() async {
        let bundleID = pendingRelaunchBundleID
            ?? pendingRelaunchURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
            ?? "com.apple.PhotoBooth"
        pendingRelaunchURL = nil
        pendingRelaunchBundleID = nil
        sessionAllowActive = true
        unlockGraceUntil = Date().addingTimeInterval(8)
        ignoreCameraTerminationsUntil = Date().addingTimeInterval(5)

        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            ?? URL(fileURLWithPath: "/System/Applications/Photo Booth.app", isDirectory: true)

        // Prefer open by bundle id — avoids "not an application" on stub paths.
        do {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            lastActionDetail = "Camera unlocked — opening \(bundleID)"
        } catch {
            _ = await Task.detached {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-b", bundleID]
                try? p.run()
                p.waitUntilExit()
                return p.terminationStatus == 0
            }.value
            lastActionDetail = "Camera unlocked"
        }

        // Brief confirm stream; do not quit/reopen again.
        for _ in 1...10 {
            if ISPPowerProbe.isFrontCameraStreaming { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func beginHoldSuppress() {
        holdSuppressUntil = Date().addingTimeInterval(5)
    }

    private func refreshStatus() {
        helperInstalled = CameraDisableHelper.isInstalled
        restrictionActive = CameraDisableHelper.isRestrictionActive

        switch mode {
        case .locked:
            if isBusyDisabling {
                iconState = .alert
                status = .disabling
            } else if restrictionActive {
                // Ban is the success state. Restart is optional, not the default status.
                iconState = .locked
                status = .protected
                needsAdminAuthorization = false
            } else if !monitor.isCameraOn {
                iconState = .locked
                status = .needsSetup
                needsAdminAuthorization = true
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

    /// Called from workspace observers + tick — shows Allow / Deny popup (no menu hunting).
    func promptAccessIfNeeded(appName: String, bundleURL: URL?) {
        guard mode == .locked else { return }
        guard Date() >= accessPromptCooldownUntil else { return }
        accessPromptCooldownUntil = Date().addingTimeInterval(12)
        if let bundleURL {
            pendingRelaunchURL = bundleURL
            if let match = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == bundleURL }) {
                pendingRelaunchBundleID = match.bundleIdentifier
            } else {
                pendingRelaunchBundleID = Bundle(url: bundleURL)?.bundleIdentifier
            }
        }
        if pendingRelaunchBundleID == nil,
           let front = NSWorkspace.shared.frontmostApplication,
           let bid = front.bundleIdentifier,
           ProcessIdentifier.knownCameraApps[bid] != nil {
            pendingRelaunchBundleID = bid
            pendingRelaunchURL = front.bundleURL
        }
        if pendingRelaunchBundleID == nil {
            pendingRelaunchBundleID = "com.apple.PhotoBooth"
        }
        let bundleID = pendingRelaunchBundleID ?? "com.apple.PhotoBooth"

        // Close the app before the dialog. Opening while banned leaves a dead camera session;
        // macOS won't reliably recover it. Allow then opens it once on an unlocked stack.
        ignoreCameraTerminationsUntil = Date().addingTimeInterval(60)
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == bundleID {
            app.terminate()
        }

        activityLog.record(
            ActivityEvent(
                app: AppIdentity(bundleID: bundleID, processName: appName, displayName: appName),
                action: .prompted,
                detail: "Access prompt"
            )
        )

        DispatchQueue.main.async { [weak self] in
            guard let self, self.mode == .locked else { return }
            AccessPrompt.present(
                appName: appName,
                onAllow: { [weak self] in
                    self?.useCameraNow(relaunchFrontApp: true)
                },
                onAllowTimed: { [weak self] in
                    self?.useCameraForMinutes(15)
                },
                onDeny: { [weak self] in
                    self?.ignoreCameraTerminationsUntil = .distantPast
                    self?.denyCameraAccess(appName: appName)
                }
            )
        }
    }

    private func denyCameraAccess(appName: String) {
        // Stay locked; quit the app + soft-kill capture helpers so ISP can DeferredPowerOff.
        terminateKnownCameraApps()
        _ = CameraDisableHelper.requestLockQuiet()
        CameraDisableHelper.unprivilegedKillDaemons { pid in kill(pid, SIGKILL) == 0 }
        lastLEDChill = Date()
        lastActionDetail = "Denied \(appName)"
        Task { @MainActor in
            await chillLEDUntilCold(reason: "Denied \(appName)")
        }
        notify(title: "Camera denied", body: "\(appName) quit — LED turning off.")
        refreshStatus()
    }

    /// Force-quit Photo Booth / FaceTime / Zoom / etc. so they cannot hold ConnectClient.
    private func terminateKnownCameraApps() {
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier,
                  ProcessIdentifier.knownCameraApps[bid] != nil,
                  app.activationPolicy == .regular else { continue }
            app.forceTerminate()
        }
    }

    /// While locked: if ISP power comes back, drop clients once (spaced ≥5s) so LED goes dark.
    private func enforceLEDColdIfNeeded() {
        guard mode == .locked else {
            ledWarmSince = nil
            return
        }
        let warm = ISPPowerProbe.isSensorWarm || ISPPowerProbe.isFrontCameraStreaming
        if !warm {
            ledWarmSince = nil
            return
        }
        if ledWarmSince == nil {
            ledWarmSince = Date()
            // Brief window for Allow/Deny before we force-quit whatever is holding the ISP.
            offerQuickAllowIfCameraAppActive()
            return
        }
        // Allow a short window for the Allow/Deny alert before force-quitting.
        guard let since = ledWarmSince, Date().timeIntervalSince(since) >= 12.0 else { return }
        guard Date().timeIntervalSince(lastLEDChill) >= ledChillCooldown else { return }
        lastLEDChill = Date()
        ledWarmSince = nil
        // Still locked after the prompt window → drop every CMIO client so LED goes dark.
        terminateKnownCameraApps()
        CameraDisableHelper.unprivilegedKillDaemons { [processController] pid in
            processController.forceKill(pid: pid)
        }
        _ = CameraDisableHelper.requestLockQuiet()
        lastActionDetail = "Forced LED cold (ISP re-powered while locked)"
        suggestRestartForStuckLED = false
    }

    /// One soft-kill then wait for DeferredPowerOff — never loop-kill faster than ~5s.
    private func chillLEDUntilCold(reason: String) async {
        guard mode == .locked else { return }
        syncHardwarePollingWithRestriction()
        terminateKnownCameraApps()
        await Task.detached(priority: .userInitiated) {
            CameraDisableHelper.unprivilegedKillDaemons { pid in kill(pid, SIGKILL) == 0 }
            _ = CameraDisableHelper.lockPasswordless()
        }.value
        lastLEDChill = Date()

        for attempt in 1...16 {
            if mode != .locked { return }
            if !ISPPowerProbe.isSensorWarm, !ISPPowerProbe.isFrontCameraStreaming {
                lastActionDetail = "\(reason) — LED cold (ISP power 0)"
                suggestRestartForStuckLED = false
                lastFailureHint = ""
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            // One spaced retry if still warm after ~4s (matches DeferredPowerOff).
            if attempt == 9, Date().timeIntervalSince(lastLEDChill) >= ledChillCooldown {
                lastLEDChill = Date()
                terminateKnownCameraApps()
                CameraDisableHelper.unprivilegedKillDaemons { pid in kill(pid, SIGKILL) == 0 }
            }
        }

        if ISPPowerProbe.isSensorWarm {
            suggestRestartForStuckLED = true
            lastFailureHint = "ISP still powered. Wait ~10s. If LED stays green with lock on: cover / Apple Care."
            lastActionDetail = "\(reason) — ISP still warm"
        }
    }

    private func offerQuickAllowIfCameraAppActive() {
        guard mode == .locked else { return }
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bid = front.bundleIdentifier,
              ProcessIdentifier.knownCameraApps[bid] != nil else { return }
        promptAccessIfNeeded(appName: front.localizedName ?? "App", bundleURL: front.bundleURL)
    }

    private func requestNotificationPermissionIfNeeded() {
        guard notifyOnAttempt else { return }
        MacCamNotifications.register()
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

    private func notifyAccessRequest(appName: String) {
        guard notifyOnAttempt else { return }
        MacCamNotifications.register()
        let content = UNMutableNotificationContent()
        content.title = "\(appName) wants the camera"
        content.body = "Allow now, or for 15 minutes — then MacCam locks again."
        content.sound = .default
        content.categoryIdentifier = MacCamNotifications.accessCategory
        let request = UNNotificationRequest(
            identifier: "maccam.access.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

enum MacCamNotifications {
    static let accessCategory = "maccam.access"
    static let allowNow = "maccam.allowNow"
    static let allow15m = "maccam.allow15m"
    static let keepLocked = "maccam.keepLocked"

    static func register() {
        let allow = UNNotificationAction(
            identifier: allowNow,
            title: "Allow Now",
            options: [.foreground]
        )
        let allowTimed = UNNotificationAction(
            identifier: allow15m,
            title: "Allow 15 min",
            options: [.foreground]
        )
        let keep = UNNotificationAction(
            identifier: keepLocked,
            title: "Keep Locked",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: accessCategory,
            actions: [allow, allowTimed, keep],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
