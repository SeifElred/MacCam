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
            return "Releasing camera (\(name))…"
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
    private var ticksWhileCameraOn: Int = 0
    private var lastDaemonReset: Date = .distantPast
    private let lockedTick: TimeInterval = 0.10
    private let unlockedTick: TimeInterval = 0.35
    private let daemonResetCooldown: TimeInterval = 2.0

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
            enforceHardLock()
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
            allowOnceSession.removeAll()
            loggedAllowKeys.removeAll()
            ticksWhileCameraOn = 0
            lastDaemonReset = .distantPast
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
        } else {
            ticksWhileCameraOn = 0
        }
        refreshStatus()
    }

    /// While locked: kill holders + reset camera stack until CoreMediaIO says camera (LED) is off.
    private func enforceHardLock() {
        guard mode == .locked else { return }

        guard monitor.isCameraOn else {
            ticksWhileCameraOn = 0
            notifyCooldown = notifyCooldown.filter { _, date in
                Date().timeIntervalSince(date) < 30
            }
            return
        }

        ticksWhileCameraOn += 1
        var killedNames: [String] = []

        // 1) Known apps / frontmost heuristics
        let candidates = identifier.scoreCandidates(
            runningApps: NSWorkspace.shared.runningApplications,
            frontmost: NSWorkspace.shared.frontmostApplication
        )
        for candidate in candidates.prefix(20) {
            if shouldProtect(candidate.app) { continue }
            if processController.forceKill(pid: candidate.pid) {
                killedNames.append(candidate.app.displayName)
                recordBlockIfNeeded(candidate.app)
            }
        }

        // 2) Browser helpers / capture helpers by process name
        for pid in CameraStackReset.helperPIDs() {
            if processController.forceKill(pid: pid) {
                let name = ProcessEnumerator.processName(pid: pid) ?? "helper"
                killedNames.append(name)
            }
        }

        // 3) If still on for a few ticks, reset camera daemons (releases hardware LED)
        monitor.refresh()
        let shouldResetDaemons = monitor.isCameraOn
            && (ticksWhileCameraOn >= 2 || killedNames.isEmpty)
            && Date().timeIntervalSince(lastDaemonReset) >= daemonResetCooldown

        if shouldResetDaemons {
            lastDaemonReset = Date()
            let daemons = CameraStackReset.killDaemons { pid in
                processController.forceKill(pid: pid)
            }
            if !daemons.isEmpty {
                killedNames.append(contentsOf: daemons)
                let app = AppIdentity(bundleID: "", processName: "CameraStack", displayName: "Camera system")
                recordBlockIfNeeded(app, detail: "Reset camera stack")
            }
        }

        // 4) Last resort: stop every known camera app (never Finder / random apps)
        monitor.refresh()
        if monitor.isCameraOn, ticksWhileCameraOn >= 4 {
            for app in NSWorkspace.shared.runningApplications {
                guard let bundle = app.bundleIdentifier,
                      ProcessIdentifier.knownCameraApps[bundle] != nil else { continue }
                let identity = AppIdentity(
                    bundleID: bundle,
                    processName: app.localizedName ?? bundle,
                    displayName: app.localizedName
                )
                if shouldProtect(identity) { continue }
                _ = processController.forceKill(pid: app.processIdentifier)
                killedNames.append(identity.displayName)
                recordBlockIfNeeded(identity, detail: "Force clear")
            }
            // Daemon reset again if still lit
            if Date().timeIntervalSince(lastDaemonReset) >= daemonResetCooldown {
                lastDaemonReset = Date()
                _ = CameraStackReset.killDaemons { pid in
                    processController.forceKill(pid: pid)
                }
            }
        }

        monitor.refresh()
        lastBlockedName = killedNames.first ?? lastBlockedName ?? "camera"
        iconState = .alert
        scheduleStatusClear()
    }

    private func shouldProtect(_ app: AppIdentity) -> Bool {
        let key = sessionKey(for: app)
        if allowOnceSession.contains(key) { return true }
        return policy.decision(for: app) == .allowlisted
    }

    private func recordBlockIfNeeded(_ app: AppIdentity, detail: String = "Locked") {
        let key = sessionKey(for: app)
        let now = Date()
        if let last = notifyCooldown[key], now.timeIntervalSince(last) < 8 {
            return
        }
        notifyCooldown[key] = now
        activityLog.record(ActivityEvent(app: app, action: .blocked, detail: detail))
        notify(
            title: "Camera blocked",
            body: "Stopped \(app.displayName) to turn the camera LED off. Unlock MacCam to use the camera."
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
                status = .clearing(appName: lastBlockedName ?? "camera")
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
