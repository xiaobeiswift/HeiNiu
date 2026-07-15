/// 上下文占用进度条与明细面板。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// ContextUsageBar
///
/// `ContextUsageBar` 类型定义。
struct ContextUsageBar: View {
    /// usage。
    let usage: ContextUsage
    /// compact。
    var compact: Bool = true

    /// SwiftUI 视图内容。
    var body: some View {
        if compact {
            compactBar
        } else {
            detailedPanel
        }
    }

    /// compactBar。
    private var compactBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.bgElevated)
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(4, geo.size.width * usage.ratio))
                }
            }
            .frame(height: 6)
            Text(usage.percentText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    /// detailedPanel。
    private var detailedPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("上下文容量")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(usage.headline)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.bgElevated)
                    HStack(spacing: 0) {
                        ForEach(usage.buckets) { bucket in
                            let w = usage.totalCharacters > 0
                                ? geo.size.width * CGFloat(bucket.characters) / CGFloat(max(usage.limitCharacters, usage.totalCharacters))
                                : 0
                            Rectangle()
                                .fill(Color(hue: bucket.colorHue, saturation: 0.65, brightness: 0.85))
                                .frame(width: max(bucket.characters > 0 ? 2 : 0, w))
                        }
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 8)

            VStack(spacing: 6) {
                ForEach(usage.buckets) { bucket in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hue: bucket.colorHue, saturation: 0.65, brightness: 0.85))
                            .frame(width: 8, height: 8)
                        Text(bucket.name)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Text(bucketPercent(bucket))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }

    /// barColor。
    private var barColor: Color {
        if usage.ratio > 0.9 { return AppTheme.danger }
        if usage.ratio > 0.7 { return AppTheme.accent }
        return Color(hue: 0.58, saturation: 0.7, brightness: 0.9)
    }

    /// bucketPercent
    ///
    /// 执行 `bucketPercent` 相关逻辑。
    private func bucketPercent(_ bucket: ContextBucket) -> String {
        guard usage.totalCharacters > 0 else { return "0%" }
        let p = Double(bucket.characters) / Double(usage.totalCharacters) * 100
        return String(format: "%.1f%%", p)
    }
}
