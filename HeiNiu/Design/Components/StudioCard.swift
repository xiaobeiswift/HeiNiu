/// 设置卡片与分区标题。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// StudioCard
///
/// `StudioCard` 类型定义。
struct StudioCard<Content: View>: View {
    /// 标题。
    var title: String?
    /// 副标题或说明文案。
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    /// SwiftUI 视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            content()
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }
}

/// SectionHeader
///
/// `SectionHeader` 类型定义。
struct SectionHeader: View {
    /// 标题。
    let title: String
    /// trailing。
    var trailing: AnyView?

    /// 初始化方法
    ///
    /// 初始化方法。
    init(_ title: String, trailing: AnyView? = nil) {
        self.title = title
        self.trailing = trailing
    }

    /// SwiftUI 视图内容。
    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            if let trailing {
                trailing
            }
        }
    }
}
