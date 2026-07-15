/// 状态徽章与圆点。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// StatusBadge
///
/// `StatusBadge` 类型定义。
struct StatusBadge: View {
    /// Style
    ///
    /// `Style` 类型定义。
    enum Style {
        /// neutral。
        case neutral
        /// accent。
        case accent
        /// success。
        case success
        /// danger。
        case danger
    }

    /// text。
    let text: String
    /// style。
    var style: Style = .neutral
    /// 用于 UI 的 SF Symbol。
    var systemImage: String?

    /// SwiftUI 视图内容。
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

    /// foreground。
    private var foreground: Color {
        switch style {
        case .neutral: AppTheme.textSecondary
        case .accent: AppTheme.accent
        case .success: AppTheme.success
        case .danger: AppTheme.danger
        }
    }

    /// background。
    private var background: Color {
        switch style {
        case .neutral: AppTheme.bgElevated
        case .accent: AppTheme.accentSoft
        case .success: AppTheme.success.opacity(0.15)
        case .danger: AppTheme.danger.opacity(0.15)
        }
    }
}

/// StatusDot
///
/// `StatusDot` 类型定义。
struct StatusDot: View {
    /// active。
    var active: Bool
    /// activeColor。
    var activeColor: Color = AppTheme.success

    /// SwiftUI 视图内容。
    var body: some View {
        Circle()
            .fill(active ? activeColor : AppTheme.textTertiary)
            .frame(width: 7, height: 7)
    }
}
