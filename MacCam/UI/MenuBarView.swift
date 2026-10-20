import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var guardService: CameraGuard
    @ObservedObject var loginItems: LoginItemService
    @ObservedObject var activityLog: ActivityLog
    @ObservedObject var policy: PolicyStore

    @State private var showAllowlist = false
    @State private var showBlocklist = false

    private var isLocked: Bool { guardService.mode == .locked }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DesignTokens.border).padding(.vertical, 10)
            lockControl
            statusLine
                .padding(.top, 8)
            if let latest = activityLog.recent(1).first {
                latestActivity(latest)
                    .padding(.top, 8)
            }
            Divider().overlay(DesignTokens.border).padding(.vertical, 10)
            SettingsSection(
                loginItems: loginItems,
                guardService: guardService,
                policy: policy,
                showAllowlist: $showAllowlist,
                showBlocklist: $showBlocklist
            )
            Divider().overlay(DesignTokens.border).padding(.vertical, 10)
            quitRow
        }
        .padding(14)
        .frame(width: DesignTokens.popoverWidth)
        .background(DesignTokens.background)
        .sheet(isPresented: $showAllowlist) {
            AppListSheet(
                title: "Allow list",
                apps: policy.allowlist,
                onRemove: { policy.removeFromAllowlist($0) },
                onClear: { policy.clearAllowlist() }
            )
        }
        .sheet(isPresented: $showBlocklist) {
            AppListSheet(
                title: "Block list",
                apps: policy.blocklist,
                onRemove: { policy.removeFromBlocklist($0) },
                onClear: { policy.clearBlocklist() }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isLocked ? DesignTokens.mintDim : DesignTokens.surfaceElevated)
                    .frame(width: 32, height: 32)
                Image(systemName: isLocked ? "lock.shield.fill" : "lock.open.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isLocked ? DesignTokens.mint : DesignTokens.textSecondary)
                    .symbolEffect(.bounce, value: isLocked)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("MacCam")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(isLocked ? "Camera blocked" : "Camera unlocked")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer()
        }
    }

    private var lockControl: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                guardService.setLocked(!isLocked)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isLocked ? "Privacy Lock On" : "Privacy Lock Off")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(isLocked ? "Apps can’t keep the camera on" : "Apps may use the camera")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer()
                Text(isLocked ? "Unlock" : "Lock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isLocked ? DesignTokens.background : DesignTokens.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isLocked ? DesignTokens.mint : DesignTokens.surfaceElevated)
                    .clipShape(Capsule())
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
                    .fill(DesignTokens.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
                            .strokeBorder(
                                isLocked ? DesignTokens.mint.opacity(0.35) : DesignTokens.border,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(guardService.status.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var statusColor: Color {
        switch guardService.status {
        case .protected: return DesignTokens.mint
        case .unlocked: return DesignTokens.textSecondary
        case .blocked: return DesignTokens.alert
        case .cameraActive: return DesignTokens.warning
        }
    }

    private func latestActivity(_ event: ActivityEvent) -> some View {
        HStack(spacing: 8) {
            Text("Last")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary)
            Text(event.app.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
            Text(shortAction(event.action))
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func shortAction(_ action: ActivityAction) -> String {
        switch action {
        case .allowed: return "· allowed"
        case .blocked, .autoBlocked: return "· blocked"
        case .prompted: return "· prompted"
        case .unlockedUse: return "· used"
        }
    }

    private var quitRow: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            HStack {
                Text("Quit MacCam")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("⌘Q")
                    .font(.system(size: 10, weight: .medium).monospaced())
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .foregroundStyle(DesignTokens.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
