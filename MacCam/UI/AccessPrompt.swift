import AppKit

/// Crash-safe Allow / Deny dialog (AppKit only — SwiftUI panel was SIGSEGV on macOS 26).
@MainActor
enum AccessPrompt {
    private static var isShowing = false

    static func present(
        appName: String,
        onAllow: @escaping () -> Void,
        onAllowTimed: @escaping () -> Void,
        onDeny: @escaping () -> Void
    ) {
        guard !isShowing else { return }
        isShowing = true

        let alert = NSAlert()
        alert.messageText = "\(appName) wants the camera"
        alert.informativeText = "Allow to unlock the camera and open the app. Deny keeps the camera locked."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Allow 15 min")
        alert.addButton(withTitle: "Deny")

        // Activate so the dialog is visible even as a menu-bar app.
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        isShowing = false

        switch response {
        case .alertFirstButtonReturn:
            onAllow()
        case .alertSecondButtonReturn:
            onAllowTimed()
        default:
            onDeny()
        }
    }

    static func dismiss() {
        isShowing = false
    }
}
