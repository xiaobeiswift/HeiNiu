/// 未实现模块的占位页。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// PlaceholderView
///
/// `PlaceholderView` 类型定义。
struct PlaceholderView: View {
    /// 标题。
    let title: String
    /// 用于 UI 的 SF Symbol。
    let systemImage: String
    /// message。
    let message: String
    /// badge。
    var badge: String? = "即将推出"

    /// SwiftUI 视图内容。
    var body: some View {
        EmptyStateView(
            title: title,
            message: message,
            systemImage: systemImage,
            badge: badge
        )
        .background(AppTheme.bgBase)
    }
}
