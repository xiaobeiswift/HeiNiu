/// 创作工作室视觉令牌与防抖辅助。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// AppTheme
///
/// `AppTheme` 类型定义。
enum AppTheme {
    // MARK: - Colors

    static let accent = Color(red: 0.93, green: 0.62, blue: 0.28) // warm amber
    static let accentSoft = accent.opacity(0.16)
    static let success = Color(red: 0.35, green: 0.78, blue: 0.52)
    static let danger = Color(red: 0.95, green: 0.38, blue: 0.38)

    static let bgBase = Color(nsColor: .windowBackgroundColor)
    static let bgSidebar = Color(nsColor: .controlBackgroundColor)
    static let bgCard = Color(nsColor: .controlBackgroundColor)
    static let bgElevated = Color.primary.opacity(0.06)
    static let stroke = Color.primary.opacity(0.08)
    static let strokeStrong = Color.primary.opacity(0.14)

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary.opacity(0.7)

    // MARK: - Metrics

    /// contentMaxWidth。
    static let contentMaxWidth: CGFloat = 760
    /// cardRadius。
    static let cardRadius: CGFloat = 14
    /// chipRadius。
    static let chipRadius: CGFloat = 8
    /// cardPadding。
    static let cardPadding: CGFloat = 18
    /// sectionSpacing。
    static let sectionSpacing: CGFloat = 14
    /// sidebarWidth。
    static let sidebarWidth: CGFloat = 210

    // MARK: - Shadows

    /// cardShadow
    ///
    /// 执行 `cardShadow` 相关逻辑。
    static func cardShadow() -> some View {
        Color.clear
    }
}

// MARK: - Auto-save helper

/// DebouncedAction
///
/// `DebouncedAction` 类型定义。
@MainActor
final class DebouncedAction {
    /// task。
    private var task: Task<Void, Never>?
    /// delayMs。
    private let delayMs: UInt64

    /// 初始化方法
    ///
    /// 初始化方法。
    init(delayMs: UInt64 = 400) {
        self.delayMs = delayMs
    }

    /// schedule
    ///
    /// 执行 `schedule` 相关逻辑。
    func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    /// cancel
    ///
    /// 执行 `cancel` 相关逻辑。
    func cancel() {
        task?.cancel()
        task = nil
    }

    /// flush
    ///
    /// 执行 `flush` 相关逻辑。
    func flush(_ action: @MainActor () -> Void) {
        task?.cancel()
        task = nil
        action()
    }
}

// MARK: - View helpers

extension View {
    /// studioContentWidth
    ///
    /// 执行 `studioContentWidth` 相关逻辑。
    func studioContentWidth() -> some View {
        frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
    }

    /// studioField
    ///
    /// 执行 `studioField` 相关逻辑。
    func studioField() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            )
    }
}
