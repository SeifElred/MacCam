import AppKit
import SwiftUI

/// Native macOS vibrancy / glass behind SwiftUI content.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct GlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(width: DesignTokens.popoverWidth)
            .background(VisualEffectBackground(material: .hudWindow))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                    .strokeBorder(DesignTokens.glassStroke, lineWidth: 1)
            )
            .compositingGroup()
            .background(ClearMenuBarWindowBackground())
    }
}

/// Clears the MenuBarExtra host window so vibrancy/glass can show through.
private struct ClearMenuBarWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}

struct GlassRowBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
            .fill(DesignTokens.glassFill)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
                    .strokeBorder(DesignTokens.glassStroke, lineWidth: 1)
            )
    }
}
