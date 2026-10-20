import SwiftUI

enum DesignTokens {
    static let background = Color(red: 0.11, green: 0.12, blue: 0.13)
    static let surface = Color(red: 0.16, green: 0.17, blue: 0.19)
    static let surfaceElevated = Color(red: 0.20, green: 0.21, blue: 0.23)
    static let border = Color.white.opacity(0.08)
    static let textPrimary = Color(red: 0.95, green: 0.96, blue: 0.97)
    static let textSecondary = Color(red: 0.62, green: 0.65, blue: 0.68)
    static let mint = Color(red: 0.45, green: 0.82, blue: 0.72)
    static let mintDim = Color(red: 0.45, green: 0.82, blue: 0.72).opacity(0.18)
    static let alert = Color(red: 0.95, green: 0.42, blue: 0.38)
    static let alertDim = Color(red: 0.95, green: 0.42, blue: 0.38).opacity(0.18)
    static let warning = Color(red: 0.96, green: 0.72, blue: 0.35)

    static let popoverWidth: CGFloat = 320
    static let cornerRadius: CGFloat = 12
    static let controlRadius: CGFloat = 10
}
