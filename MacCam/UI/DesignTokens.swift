import SwiftUI

enum DesignTokens {
    /// Adaptive labels that stay readable on vibrancy / glass.
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let mint = Color(red: 0.20, green: 0.72, blue: 0.58)
    static let mintDim = Color(red: 0.20, green: 0.72, blue: 0.58).opacity(0.22)
    static let alert = Color(red: 0.90, green: 0.30, blue: 0.28)
    static let warning = Color(red: 0.92, green: 0.62, blue: 0.18)

    static let glassFill = Color.primary.opacity(0.06)
    static let glassStroke = Color.primary.opacity(0.12)
    static let glassFillStrong = Color.primary.opacity(0.10)

    static let popoverWidth: CGFloat = 300
    static let cornerRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let rowHeight: CGFloat = 36
}
