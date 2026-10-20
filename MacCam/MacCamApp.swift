import AppKit
import SwiftUI

@main
struct MacCamApp: App {
    @StateObject private var guardService: CameraGuard
    @StateObject private var loginItems = LoginItemService()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let policy = PolicyStore()
        let log = ActivityLog()
        let guardService = CameraGuard(policy: policy, activityLog: log)
        _guardService = StateObject(wrappedValue: guardService)
        AppDelegate.sharedGuard = guardService
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                guardService: guardService,
                loginItems: loginItems,
                activityLog: guardService.activityLog,
                policy: guardService.policy
            )
            .onAppear {
                loginItems.refresh()
            }
        } label: {
            Image(nsImage: StatusIcon.image(for: guardService.iconState))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var sharedGuard: CameraGuard?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppDelegate.sharedGuard?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.sharedGuard?.stop()
    }
}
