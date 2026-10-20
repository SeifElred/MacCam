import AppKit
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
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
        nsView.isEmphasized = true
    }
}

/// Control Center–style host: frosted menu material, soft round rect, no nested chrome.
struct GlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(10)
            .frame(width: DesignTokens.popoverWidth, alignment: .leading)
            .background {
                VisualEffectBackground(material: .menu, blendingMode: .behindWindow)
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            .background(ClearHostWindow())
    }
}

private struct ClearHostWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.clear(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.clear(nsView.window) }
    }

    private static func clear(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
    }
}

/// Single CC module tile.
struct CCModule<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.moduleRadius, style: .continuous)
                .fill(DesignTokens.moduleFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.moduleRadius, style: .continuous))
    }
}

struct GlassRowBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
            .fill(DesignTokens.moduleFill)
    }
}

struct CCDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, 12)
    }
}
