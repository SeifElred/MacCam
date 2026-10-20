import Foundation
import ServiceManagement

@MainActor
final class LoginItemService: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var lastError: String?

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
        // macOS may require approval in System Settings → Login Items.
        if enabled && SMAppService.mainApp.status == .requiresApproval {
            lastError = "Approve MacCam in System Settings → General → Login Items."
        }
    }
}
