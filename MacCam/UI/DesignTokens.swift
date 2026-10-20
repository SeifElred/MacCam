import SwiftUI

/// Control Center–aligned tokens: system type, one accent, quiet fills.
enum DesignTokens {
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    /// Single accent — lock switch + live state only (like CC green toggles).
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let mint = accent
    static let mintDim = accent.opacity(0.18)
    static let alert = Color(nsColor: .systemOrange)
    static let warning = Color(nsColor: .systemOrange)

    static let moduleFill = Color.primary.opacity(0.06)
    static let moduleStroke = Color.primary.opacity(0.06)
    static let glassFill = moduleFill
    static let glassStroke = moduleStroke
    static let glassFillStrong = Color.primary.opacity(0.09)

    static let popoverWidth: CGFloat = 260
    static let cornerRadius: CGFloat = 14
    static let moduleRadius: CGFloat = 10
    static let controlRadius: CGFloat = 10
    static let rowHeight: CGFloat = 36
    static let moduleGap: CGFloat = 8
}
