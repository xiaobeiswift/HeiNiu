/// 空状态组件。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// EmptyStateView
///
/// `EmptyStateView` 类型定义。
struct EmptyStateView: View {
    /// 标题。
    let title: String
    /// message。
    let message: String
    /// 用于 UI 的 SF Symbol。
    var systemImage: String = "tray"
    /// badge。
    var badge: String? = nil
    /// actionTitle。
    var actionTitle: String? = nil
    /// action。
    var action: (() -> Void)? = nil

    /// SwiftUI 视图内容。
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 88, height: 88)
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(spacing: 8) {
                if let badge {
                    StatusBadge(text: badge, style: .accent)
                }
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(AppTheme.accent, in: Capsule())
                        .foregroundStyle(.black.opacity(0.85))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
