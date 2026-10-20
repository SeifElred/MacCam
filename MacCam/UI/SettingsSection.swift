import SwiftUI

struct SettingsSection: View {
    @ObservedObject var loginItems: LoginItemService
    @ObservedObject var guardService: CameraGuard
    @ObservedObject var policy: PolicyStore
    @Binding var showAllowlist: Bool
    @Binding var showBlocklist: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { loginItems.isEnabled },
                set: { loginItems.setEnabled($0) }
            )) {
                labeled("Launch at Login", systemImage: "power")
            }
            .toggleStyle(.switch)
            .tint(DesignTokens.mint)

            if let error = loginItems.lastError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $guardService.notifyOnAttempt) {
                labeled("Notify on attempt", systemImage: "bell")
            }
            .toggleStyle(.switch)
            .tint(DesignTokens.mint)

            HStack(spacing: 8) {
                listButton("Allow list", count: policy.allowlist.count) {
                    showAllowlist = true
                }
                listButton("Block list", count: policy.blocklist.count) {
                    showBlocklist = true
                }
            }
        }
        .onAppear { loginItems.refresh() }
    }

    private func labeled(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.mint)
                .frame(width: 16)
        }
    }

    private func listButton(_ title: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DesignTokens.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AppListSheet: View {
    let title: String
    let apps: [AppIdentity]
    let onRemove: (AppIdentity) -> Void
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.mint)
            }

            if apps.isEmpty {
                Text("No apps yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(apps) { app in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                    Text(app.bundleID.isEmpty ? app.processName : app.bundleID)
                                        .font(.system(size: 10))
                                        .foregroundStyle(DesignTokens.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    onRemove(app)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(DesignTokens.alert)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(DesignTokens.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 220)

                Button("Clear all", role: .destructive, action: onClear)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.alert)
                    .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(DesignTokens.background)
    }
}
