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

    private var needsSetup: Bool {
        isLocked && (!guardService.helperInstalled || guardService.needsAdminAuthorization
            || guardService.monitor.isCameraOn || !guardService.restrictionActive)
    }

    private var needsRestore: Bool {
        !isLocked && (guardService.restrictionActive || !guardService.lastFailureHint.isEmpty)
    }

    var body: some View {
        GlassPanel {
            Group {
                switch panel {
                case .main:
                    mainPanel
                case .allowlist:
                    listPanel(
                        title: "Allow List",
                        apps: policy.allowlist,
                        emptyText: "No Allowed Apps",
                        onRemove: { policy.removeFromAllowlist($0) },
                        onClear: { policy.clearAllowlist() }
                    )
                case .blocklist:
                    listPanel(
                        title: "Block List",
                        apps: policy.blocklist,
                        emptyText: "No Blocked Apps",
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
        VStack(alignment: .leading, spacing: DesignTokens.moduleGap) {
            // Primary Control Center module
            CCModule {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(isLocked ? DesignTokens.accent : Color.primary.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "web.camera.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isLocked ? Color.white : DesignTokens.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Camera Lock")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignTokens.textPrimary)
                        Text(statusCaption)
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Toggle("", isOn: Binding(
                        get: { isLocked },
                        set: { guardService.setLocked($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(DesignTokens.accent)
                    .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            // One-time helper install (password once in lifetime).
            if isLocked && !guardService.helperInstalled {
                CCModule {
                    ccActionButton(title: "Enable Camera Lock (once)", systemImage: "key.fill") {
                        guardService.installHelperAndDisable()
                    }
                    .disabled(guardService.isBusyDisabling)
                }
                Text("Enter your Mac password one time. After that, lock and Use Camera never ask again.")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            if isLocked && guardService.helperInstalled {
                Text("When Photo Booth / FaceTime opens, MacCam asks Allow or Deny.")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            if needsSetup {
                CCModule {
                    ccActionButton(
                        title: setupTitle,
                        systemImage: "key.fill"
                    ) {
                        if guardService.helperInstalled {
                            guardService.authorizeAdminDisable()
                        } else {
                            guardService.installHelperAndDisable()
                        }
                    }
                    .disabled(guardService.isBusyDisabling)

                    if guardService.needsAdminAuthorization || guardService.monitor.isCameraOn {
                        CCDivider()
                        ccActionButton(
                            title: guardService.didCopyFixCommand ? "Copied" : "Copy Terminal Fix",
                            systemImage: "terminal",
                            secondary: true
                        ) {
                            guardService.copyTerminalFixCommand()
                        }
                    }
                }
            }

            if isLocked && guardService.restrictionActive && guardService.suggestRestartForStuckLED {
                Text(guardService.lastFailureHint.isEmpty
                     ? "LED may be stuck — ISP power is already off."
                     : guardService.lastFailureHint)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                CCModule {
                    ccActionButton(title: "Restart Mac…", systemImage: "arrow.clockwise") {
                        guardService.requestRestartMac()
                    }
                }
            }

            if needsRestore {
                CCModule {
                    ccActionButton(
                        title: guardService.isBusyDisabling ? "Restoring…" : "Restore Camera",
                        systemImage: "camera.fill"
                    ) {
                        guardService.restoreCameraNow()
                    }
                    .disabled(guardService.isBusyDisabling)

                    CCDivider()
                    ccActionButton(
                        title: guardService.didCopyFixCommand ? "Copied" : "Copy Restore Command",
                        systemImage: "terminal",
                        secondary: true
                    ) {
                        guardService.copyTerminalRestoreCommand()
                    }
                }
            }

            if !guardService.lastFailureHint.isEmpty && (needsSetup || needsRestore) {
                Text(guardService.lastFailureHint)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            SettingsSection(
                loginItems: loginItems,
                guardService: guardService,
                policy: policy,
                onOpenAllowlist: { panel = .allowlist },
                onOpenBlocklist: { panel = .blocklist }
            )

            Button {
                AppDelegate.userRequestedQuit = true
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit MacCam")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var statusCaption: String {
        switch guardService.status {
        case .protected:
            if guardService.monitor.hardwarePollingSuspended {
                return "Locked · Idle"
            }
            return guardService.monitor.isCameraOn ? "Locked · Sensor On" : "Locked · Blocked"
        case .unlocked:
            return "Unlocked"
        case .disabling:
            return "Working…"
        case .needsAdmin, .needsSetup:
            return "Setup Required"
        case .stuckLED:
            return "LED May Be Stuck"
        case .cameraActive:
            return "Camera In Use"
        }
    }

    private var setupTitle: String {
        if guardService.isBusyDisabling { return "Working…" }
        if !guardService.helperInstalled { return "Enable Camera Lock (once)" }
        return "Retry Lock"
    }

    private func ccActionButton(
        title: String,
        systemImage: String,
        secondary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondary ? DesignTokens.textSecondary : DesignTokens.textPrimary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: secondary ? .regular : .medium))
                    .foregroundStyle(secondary ? DesignTokens.textSecondary : DesignTokens.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: DesignTokens.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func listPanel(
        title: String,
        apps: [AppIdentity],
        emptyText: String,
        onRemove: @escaping (AppIdentity) -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.moduleGap) {
            HStack(spacing: 8) {
                Button { panel = .main } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.accent)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)

                Spacer(minLength: 0)

                if !apps.isEmpty {
                    Button("Clear", action: onClear)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.alert)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)

            CCModule {
                if apps.isEmpty {
                    Text(emptyText)
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                } else {
                    ForEach(Array(apps.prefix(6).enumerated()), id: \.element.id) { index, app in
                        if index > 0 { CCDivider() }
                        HStack {
                            Text(app.displayName)
                                .font(.system(size: 13))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Button { onRemove(app) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 16))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: DesignTokens.rowHeight)
                    }

                    if apps.count > 6 {
                        CCDivider()
                        Text("+\(apps.count - 6) More")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}
