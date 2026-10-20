import SwiftUI

struct SettingsSection: View {
    @ObservedObject var loginItems: LoginItemService
    @ObservedObject var guardService: CameraGuard
    @ObservedObject var policy: PolicyStore
    var onOpenAllowlist: () -> Void
    var onOpenBlocklist: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.moduleGap) {
            CCModule {
                ccToggle("Open at Login", isOn: Binding(
                    get: { loginItems.isEnabled },
                    set: { loginItems.setEnabled($0) }
                ))
                if let error = loginItems.lastError, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                CCDivider()
                ccToggle("Notify on Attempt", isOn: $guardService.notifyOnAttempt)
            }

            CCModule {
                ccLink("Allow List", trailing: "\(policy.allowlist.count)", action: onOpenAllowlist)
                CCDivider()
                ccLink("Block List", trailing: "\(policy.blocklist.count)", action: onOpenBlocklist)
            }
        }
    }

    private func ccToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DesignTokens.textPrimary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(DesignTokens.accent)
        .padding(.horizontal, 12)
        .frame(height: DesignTokens.rowHeight)
    }

    private func ccLink(_ title: String, trailing: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer(minLength: 0)
                Text(trailing)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(DesignTokens.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .frame(height: DesignTokens.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
