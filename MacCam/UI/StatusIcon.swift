import AppKit
import SwiftUI

enum MenuBarIconState: Equatable {
    case locked
    case unlocked
    case alert
}

enum StatusIcon {
    static func image(for state: MenuBarIconState) -> NSImage {
        let name: String
        switch state {
        case .locked:
            name = "lock.shield.fill"
        case .unlocked:
            name = "lock.open.fill"
        case .alert:
            name = "exclamationmark.shield.fill"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "MacCam")?
            .withSymbolConfiguration(config)
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }
}
