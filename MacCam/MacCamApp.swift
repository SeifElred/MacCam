import AppKit
import SwiftUI
import UserNotifications

@main
struct MacCamApp: App {
    @StateObject private var guardService: CameraGuard
    @StateObject private var loginItems: LoginItemService
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let policy = PolicyStore()
        let log = ActivityLog()
        let guardService = CameraGuard(policy: policy, activityLog: log)
        let loginItems = LoginItemService()
        _guardService = StateObject(wrappedValue: guardService)
        _loginItems = StateObject(wrappedValue: loginItems)
        AppDelegate.sharedGuard = guardService
        AppDelegate.sharedLoginItems = loginItems
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    static weak var sharedGuard: CameraGuard?
    static var sharedLoginItems: LoginItemService?
    static var userRequestedQuit = false

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var iconTimer: Timer?
    private var cameraWatchTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("MacCam menu bar")
        ProcessInfo.processInfo.disableSuddenTermination()

        MacCamNotifications.register()
        UNUserNotificationCenter.current().delegate = self

        installStatusItem()
        AppDelegate.sharedGuard?.start()
        startIconUpdates()
        watchCameraApps()
    }

    /// Instant Allow / Deny when Photo Booth, FaceTime, Zoom, etc. come to the front.
    private func watchCameraApps() {
        let center = NSWorkspace.shared.notificationCenter
        let launchNames = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]
        for name in launchNames {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo
                let app = (info?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                    ?? (info?["NSWorkspaceApplicationKey"] as? NSRunningApplication)
                guard let app else { return }
                DispatchQueue.main.async {
                    self?.handleCameraAppActivity(app)
                }
            }
            workspaceObservers.append(token)
        }
        let quitToken = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            let info = note.userInfo
            let app = (info?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                ?? (info?["NSWorkspaceApplicationKey"] as? NSRunningApplication)
            let bid = app?.bundleIdentifier
            DispatchQueue.main.async {
                // Only care about known camera apps quitting.
                if let bid, ProcessIdentifier.knownCameraApps[bid] != nil {
                    AppDelegate.sharedGuard?.handleCameraAppTerminated(bundleID: bid)
                } else if bid == nil {
                    // Some terminations omit the app object — still check if any camera app remains.
                    AppDelegate.sharedGuard?.handleCameraAppTerminated(bundleID: nil)
                }
            }
        }
        workspaceObservers.append(quitToken)
        // Poll frontmost camera app — notifications are easy to miss for already-open apps.
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                if let front = NSWorkspace.shared.frontmostApplication {
                    self?.handleCameraAppActivity(front)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cameraWatchTimer = timer
    }

    private func handleCameraAppActivity(_ app: NSRunningApplication) {
        guard let guardService = AppDelegate.sharedGuard else { return }
        guard guardService.mode == .locked else { return }
        guard let bid = app.bundleIdentifier,
              ProcessIdentifier.knownCameraApps[bid] != nil else { return }
        let name = app.localizedName ?? "This app"
        // Pass the running app's bundleURL — resolve bundle ID inside Guard (don't open Contents/MacOS).
        guardService.promptAccessIfNeeded(appName: name, bundleURL: app.bundleURL)
    }

    // MARK: - Notification actions (fast allow)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let guardService = AppDelegate.sharedGuard else { return }
        switch response.actionIdentifier {
        case MacCamNotifications.allowNow:
            guardService.useCameraNow(relaunchFrontApp: true)
        case MacCamNotifications.allow15m:
            guardService.useCameraForMinutes(15)
        case MacCamNotifications.keepLocked:
            break
        case UNNotificationDefaultActionIdentifier:
            Self.showQuickAllow(appName: nil)
        default:
            break
        }
    }

    static func showQuickAllow(appName: String?) {
        Task { @MainActor in
            let name = (appName?.isEmpty == false) ? appName! : "An app"
            AppDelegate.sharedGuard?.promptAccessIfNeeded(appName: name, bundleURL: nil)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func applicationWillTerminate(_ notification: Notification) {
        iconTimer?.invalidate()
        cameraWatchTimer?.invalidate()
        removeEventMonitor()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers = []
        AppDelegate.sharedGuard?.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppDelegate.userRequestedQuit ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        togglePanel()
        return false
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "MacCamStatus"
        item.isVisible = true

        if let button = item.button {
            let image = StatusIcon.image(for: AppDelegate.sharedGuard?.iconState ?? .locked)
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "MacCam"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let cc = UserDefaults(suiteName: "com.apple.controlcenter")
        let battery = cc?.double(forKey: "NSStatusItem Preferred Position Battery") ?? 269
        let wifi = cc?.double(forKey: "NSStatusItem Preferred Position WiFi") ?? 231
        let target = max(wifi + 10, battery - 18)
        UserDefaults.standard.set(target, forKey: "NSStatusItem Preferred Position MacCamStatus")
        UserDefaults.standard.set(true, forKey: "NSStatusItem Visible MacCamStatus")

        statusItem = item
    }

    private func startIconUpdates() {
        iconTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateIcon()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let state = AppDelegate.sharedGuard?.iconState ?? .locked
        let image = StatusIcon.image(for: state)
        image.isTemplate = true
        button.image = image
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        togglePanel()
    }

    private func togglePanel() {
        if let panel, panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    fileprivate func openPanel() {
        let loginItems = AppDelegate.sharedLoginItems ?? LoginItemService()
        AppDelegate.sharedLoginItems = loginItems
        guard let guardService = AppDelegate.sharedGuard else { return }
        loginItems.refresh()

        let root = MenuBarView(
            guardService: guardService,
            loginItems: loginItems,
            activityLog: guardService.activityLog,
            policy: guardService.policy
        )

        let controller = NSHostingController(rootView: root)
        let fitting = controller.sizeThatFits(in: NSSize(width: DesignTokens.popoverWidth, height: 900))
        let size = NSSize(width: DesignTokens.popoverWidth, height: max(fitting.height, 120))

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = controller
        panel.setContentSize(size)
        positionPanel(panel, size: size)
        panel.orderFrontRegardless()
        // Delay so the opening click doesn't immediately dismiss.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.installEventMonitor()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: DesignTokens.popoverWidth, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        return panel
    }

    private func positionPanel(_ panel: NSPanel, size: NSSize) {
        guard let button = statusItem?.button,
              let buttonWindow = button.window else {
            panel.center()
            return
        }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        let x = screenRect.midX - size.width / 2
        let y = screenRect.minY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func closePanel() {
        panel?.orderOut(nil)
        removeEventMonitor()
    }

    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePanel()
            }
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

}
