import SwiftUI

struct StatusBadge: View {
    enum Style {
        case neutral
        case accent
        case success
        case danger
    }

    let text: String
    var style: Style = .neutral
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch style {
        case .neutral: AppTheme.textSecondary
        case .accent: AppTheme.accent
        case .success: AppTheme.success
        case .danger: AppTheme.danger
        }
    }

    private var background: Color {
        switch style {
        case .neutral: AppTheme.bgElevated
        case .accent: AppTheme.accentSoft
        case .success: AppTheme.success.opacity(0.15)
        case .danger: AppTheme.danger.opacity(0.15)
        }
    }
}

struct StatusDot: View {
    var active: Bool
    var activeColor: Color = AppTheme.success

    var body: some View {
        Circle()
            .fill(active ? activeColor : AppTheme.textTertiary)
            .frame(width: 7, height: 7)
    }
}
