import SwiftUI

struct SettingsSection: View {
    @ObservedObject var loginItems: LoginItemService
    @ObservedObject var guardService: CameraGuard
    @ObservedObject var policy: PolicyStore
    var onOpenAllowlist: () -> Void
    var onOpenBlocklist: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toggleRow(
                title: "Launch at Login",
                systemImage: "power",
                isOn: Binding(
                    get: { loginItems.isEnabled },
                    set: { loginItems.setEnabled($0) }
                )
            )

            if let error = loginItems.lastError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.warning)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            toggleRow(
                title: "Notify on attempt",
                systemImage: "bell",
                isOn: $guardService.notifyOnAttempt
            )

            HStack(spacing: 8) {
                listChip("Allow", count: policy.allowlist.count, action: onOpenAllowlist)
                listChip("Block", count: policy.blocklist.count, action: onOpenBlocklist)
            }
        }
    }

    private func toggleRow(title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.mint)
                    .frame(width: 16)
            }
        }
        .toggleStyle(.switch)
        .tint(DesignTokens.mint)
        .frame(height: DesignTokens.rowHeight)
        .padding(.horizontal, 10)
        .background(GlassRowBackground())
    }

    private func listChip(_ title: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: DesignTokens.rowHeight)
            .frame(maxWidth: .infinity)
            .background(GlassRowBackground())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
