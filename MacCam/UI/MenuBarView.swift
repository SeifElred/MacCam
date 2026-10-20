import AppKit
import SwiftUI

private enum MenuPanel: Equatable {
    case main
    case allowlist
    case blocklist
}

struct MenuBarView: View {
    @ObservedObject var guardService: CameraGuard
    @ObservedObject var loginItems: LoginItemService
    @ObservedObject var activityLog: ActivityLog
    @ObservedObject var policy: PolicyStore

    @State private var panel: MenuPanel = .main

    private var isLocked: Bool { guardService.mode == .locked }

    var body: some View {
        GlassPanel {
            Group {
                switch panel {
                case .main:
                    mainPanel
                case .allowlist:
                    listPanel(
                        title: "Allow list",
                        apps: policy.allowlist,
                        emptyText: "No allowed apps",
                        onRemove: { policy.removeFromAllowlist($0) },
                        onClear: { policy.clearAllowlist() }
                    )
                case .blocklist:
                    listPanel(
                        title: "Block list",
                        apps: policy.blocklist,
                        emptyText: "No blocked apps",
                        onRemove: { policy.removeFromBlocklist($0) },
                        onClear: { policy.clearBlocklist() }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { loginItems.refresh() }
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            lockControl
            statusChip
            if isLocked && (!guardService.helperInstalled || guardService.needsAdminAuthorization || guardService.monitor.isCameraOn) {
                setupButton
                if !guardService.lastFailureHint.isEmpty {
                    Text(guardService.lastFailureHint)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if guardService.needsAdminAuthorization || guardService.monitor.isCameraOn {
                    copyFixButton
                }
            }
            if let latest = activityLog.recent(1).first {
                latestLine(latest)
            }
            Divider().opacity(0.35)
            SettingsSection(
                loginItems: loginItems,
                guardService: guardService,
                policy: policy,
                onOpenAllowlist: { panel = .allowlist },
                onOpenBlocklist: { panel = .blocklist }
            )
            Divider().opacity(0.35)
            quitRow
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isLocked ? DesignTokens.mintDim : DesignTokens.glassFillStrong)
                    .frame(width: 34, height: 34)
                Image(systemName: isLocked ? "lock.shield.fill" : "lock.open.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isLocked ? DesignTokens.mint : DesignTokens.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("MacCam")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                Text(isLocked ? "Camera disabled" : "Camera available")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 36)
    }

    private var lockControl: some View {
        Button {
            guardService.setLocked(!isLocked)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isLocked ? "Privacy Lock On" : "Privacy Lock Off")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)
                    Text(isLocked ? "Camera off for every app · LED off" : "Apps can use the camera")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(isLocked ? "Unlock" : "Lock")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isLocked ? Color.black.opacity(0.85) : DesignTokens.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(isLocked ? DesignTokens.mint : DesignTokens.glassFillStrong)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(GlassRowBackground())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusChip: some View {
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
        .frame(height: 18)
    }

    private var statusColor: Color {
        switch guardService.status {
        case .protected: return DesignTokens.mint
        case .unlocked: return DesignTokens.textSecondary
        case .disabling, .needsAdmin, .needsSetup: return DesignTokens.alert
        case .cameraActive: return DesignTokens.warning
        }
    }

    private var setupButton: some View {
        Button {
            if guardService.helperInstalled {
                guardService.authorizeAdminDisable()
            } else {
                guardService.installHelperAndDisable()
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "key.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(setupButtonTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text("M1 Pro needs a one-time password so MacCam can turn the camera hardware off. Apps are not quit.")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(12)
            .background(DesignTokens.alert.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
                    .strokeBorder(DesignTokens.alert.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(guardService.isBusyDisabling)
    }

    private var setupButtonTitle: String {
        if guardService.isBusyDisabling { return "Working… enter password if asked" }
        if guardService.helperInstalled { return "Turn LED off now" }
        return "Enable LED protection (one-time)"
    }

    private var copyFixButton: some View {
        Button {
            guardService.copyTerminalFixCommand()
        } label: {
            HStack {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                Text(guardService.didCopyFixCommand ? "Copied — paste in Terminal" : "Copy Terminal fix command")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(GlassRowBackground())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func latestLine(_ event: ActivityEvent) -> some View {
        HStack(spacing: 6) {
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
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: 16)
    }

    private func shortAction(_ action: ActivityAction) -> String {
        switch action {
        case .allowed: return "· allowed"
        case .blocked, .autoBlocked: return "· disabled"
        case .prompted: return "· prompted"
        case .unlockedUse: return "· used"
        }
    }

    private func listPanel(
        title: String,
        apps: [AppIdentity],
        emptyText: String,
        onRemove: @escaping (AppIdentity) -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    panel = .main
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.mint)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
            }
            .frame(height: 24)

            if apps.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(apps.prefix(6))) { app in
                        HStack(spacing: 8) {
                            Text(app.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Button {
                                onRemove(app)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(DesignTokens.alert)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 22, height: 22)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: DesignTokens.rowHeight)
                        .background(GlassRowBackground())
                    }
                }
                .frame(maxHeight: 6 * (DesignTokens.rowHeight + 6))

                if apps.count > 6 {
                    Text("+\(apps.count - 6) more stored")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                Button("Clear all", action: onClear)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.alert)
                    .buttonStyle(.plain)
                    .frame(height: 24)
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
                Spacer(minLength: 0)
                Text("⌘Q")
                    .font(.system(size: 10, weight: .medium).monospaced())
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .foregroundStyle(DesignTokens.textSecondary)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
