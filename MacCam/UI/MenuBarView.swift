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
            Divider().overlay(DesignTokens.border).padding(.vertical, 12)
            lockControl
            statusLine
                .padding(.top, 10)
            Divider().overlay(DesignTokens.border).padding(.vertical, 12)
            activitySection
            Divider().overlay(DesignTokens.border).padding(.vertical, 12)
            SettingsSection(
                loginItems: loginItems,
                guardService: guardService,
                policy: policy,
                showAllowlist: $showAllowlist,
                showBlocklist: $showBlocklist
            )
            Divider().overlay(DesignTokens.border).padding(.vertical, 12)
            quitRow
        }
        .padding(16)
        .frame(width: DesignTokens.popoverWidth)
        .background(DesignTokens.background)
        .sheet(isPresented: $guardService.showDecisionSheet) {
            if let app = guardService.pendingApp {
                DecisionSheet(app: app) { decision in
                    guardService.applyUserDecision(decision)
                }
            }
        }
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
                    .frame(width: 36, height: 36)
                Image(systemName: isLocked ? "lock.shield.fill" : "lock.open.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isLocked ? DesignTokens.mint : DesignTokens.textSecondary)
                    .symbolEffect(.bounce, value: isLocked)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("MacCam")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("Camera privacy guard")
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
                    Text(isLocked ? "Camera access is blocked" : "Apps may use the camera")
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
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var statusColor: Color {
        switch guardService.status {
        case .protected: return DesignTokens.mint
        case .unlocked: return DesignTokens.textSecondary
        case .handling: return DesignTokens.alert
        case .cameraActive: return DesignTokens.warning
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent activity")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary)
                .textCase(.uppercase)
                .tracking(0.4)

            let recent = activityLog.recent(6)
            if recent.isEmpty {
                Text("No camera events yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(recent) { event in
                    ActivityRow(event: event)
                }
            }
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

struct DecisionSheet: View {
    let app: AppIdentity
    let onDecision: (UserDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DesignTokens.alertDim)
                        .frame(width: 40, height: 40)
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(DesignTokens.alert)
                        .font(.system(size: 18, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Camera access blocked")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("\(app.displayName) tried to open the camera.")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !app.bundleID.isEmpty {
                Text(app.bundleID)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            VStack(spacing: 8) {
                decisionButton("Allow once", tint: DesignTokens.mint) {
                    onDecision(.allowOnce)
                }
                decisionButton("Always allow", tint: DesignTokens.mint.opacity(0.85)) {
                    onDecision(.alwaysAllow)
                }
                decisionButton("Block", tint: DesignTokens.alert) {
                    onDecision(.blockOnce)
                }
                decisionButton("Always block", tint: DesignTokens.alert.opacity(0.85)) {
                    onDecision(.alwaysBlock)
                }
            }

            Text("No response in 30s auto-blocks this app.")
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(18)
        .frame(width: 320)
        .background(DesignTokens.background)
    }

    private func decisionButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(DesignTokens.textPrimary)
                .background(tint.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
