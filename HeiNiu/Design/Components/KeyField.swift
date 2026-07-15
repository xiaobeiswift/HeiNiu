/// API Key 与通用文本输入组件。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// KeyField
///
/// `KeyField` 类型定义。
struct KeyField: View {
    /// 标题。
    let title: String
    /// footnote。
    @Binding var text: String
    var footnote: String = "密钥仅保存在本机钥匙串"

    /// SwiftUI 视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)

            SecureField("sk-…", text: $text)
                .textFieldStyle(.plain)
                .font(.body.monospaced())
                .studioField()

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                Text(footnote)
                    .font(.caption)
            }
            .foregroundStyle(AppTheme.textTertiary)
        }
    }
}

/// StudioTextField
///
/// `StudioTextField` 类型定义。
struct StudioTextField: View {
    /// 标题。
    let title: String
    /// placeholder。
    @Binding var text: String
    var placeholder: String = ""
    /// monospaced。
    var monospaced: Bool = false

    /// SwiftUI 视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(monospaced ? .body.monospaced() : .body)
                .studioField()
        }
    }
}
