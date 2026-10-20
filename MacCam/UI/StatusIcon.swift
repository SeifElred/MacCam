import AppKit
import SwiftUI

enum MenuBarIconState: Equatable {
    case locked
    case unlocked
    case alert
}

enum StatusIcon {
    /// SF Symbol names chosen to read like Control Center glyphs (simple, monochrome).
    static func symbolName(for state: MenuBarIconState) -> String {
        switch state {
        case .locked: return "web.camera.fill"
        case .unlocked: return "web.camera"
        case .alert: return "exclamationmark.triangle.fill"
        }
    }

    static func accessibilityLabel(for state: MenuBarIconState) -> String {
        switch state {
        case .locked: return "MacCam — camera locked"
        case .unlocked: return "MacCam — camera unlocked"
        case .alert: return "MacCam — attention needed"
        }
    }

    /// Template NSImage for AppKit hosts (same look as Battery / Wi‑Fi).
    static func image(for state: MenuBarIconState) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName(for: state), accessibilityDescription: accessibilityLabel(for: state))?
            .withSymbolConfiguration(config)
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }
}
