import SwiftUI

struct ActivityRow: View {
    let event: ActivityEvent

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(color(for: event.action))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.app.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(DesignTokens.textSecondary.opacity(0.8))
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        switch event.action {
        case .allowed: return event.detail.isEmpty ? "Allowed" : event.detail
        case .blocked: return event.detail.isEmpty ? "Blocked" : event.detail
        case .prompted: return "Asked for permission"
        case .autoBlocked: return "Auto-blocked"
        case .unlockedUse: return "Used while unlocked"
        }
    }

    private func color(for action: ActivityAction) -> Color {
        switch action {
        case .allowed, .unlockedUse: return DesignTokens.mint
        case .blocked, .autoBlocked: return DesignTokens.alert
        case .prompted: return DesignTokens.warning
        }
    }
}
