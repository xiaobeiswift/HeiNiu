/// 上下文占用进度环与明细面板。
///
/// 紧凑环用于输入区按钮；点开后在图标上方弹出固定宽度明细（避免撑破布局）。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// 上下文容量指示器。
///
/// - `compact`：小环形进度 + 百分比（固定不抢布局）
/// - 明细：固定约 280pt 宽的气泡面板，顶部为环形总览
struct ContextUsageBar: View {
    /// 占用数据。
    let usage: ContextUsage
    /// 是否紧凑模式。
    var compact: Bool = true

    /// 明细面板建议宽度。
    static let detailWidth: CGFloat = 280

    var body: some View {
        if compact {
            compactBar
        } else {
            detailedPanel
        }
    }

    /// 输入区用的短指示：仅环形进度，不带百分比与外框。
    private var compactBar: some View {
        ContextUsageRing(
            ratio: usage.ratio,
            lineWidth: 2.5,
            tint: barColor,
            track: AppTheme.stroke.opacity(0.9)
        )
        .frame(width: 16, height: 16)
        .accessibilityLabel("上下文容量")
        .accessibilityValue(Text(usage.percentText))
    }

    /// 弹出明细：对齐常见「上下文容量」面板样式。
    private var detailedPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ContextUsageRing(
                    ratio: min(1, usage.ratio),
                    lineWidth: 7,
                    tint: barColor,
                    track: AppTheme.stroke.opacity(0.85)
                )
                .frame(width: 56, height: 56)
                .overlay {
                    Text(usage.percentText)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.textPrimary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("上下文容量")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(usage.headline)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                ForEach(displayBuckets) { bucket in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hue: bucket.colorHue, saturation: 0.65, brightness: 0.85))
                            .frame(width: 8, height: 8)
                        Text(bucket.name)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer(minLength: 8)
                        Text(bucketPercent(bucket))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }

            Divider().opacity(0.5)

            HStack {
                Text("已用字符")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                Spacer()
                Text("\(usage.displayCount(usage.totalCharacters)) / \(usage.displayCount(usage.limitCharacters))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(14)
        .frame(width: Self.detailWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.strokeStrong, lineWidth: 1)
        )
    }

    /// 展示用分桶：没有数据的也补 0，面板更稳定。
    private var displayBuckets: [ContextBucket] {
        let names = ["消息", "知识库", "附件", "技能", "系统提示词", "插入会话"]
        let hues: [Double] = [0.58, 0.12, 0.75, 0.85, 0.45, 0.33]
        let map = Dictionary(uniqueKeysWithValues: usage.buckets.map { ($0.name, $0) })
        return zip(names, hues).map { name, hue in
            map[name] ?? ContextBucket(name: name, characters: 0, colorHue: hue)
        }
    }

    private var barColor: Color {
        if usage.ratio > 0.9 { return AppTheme.danger }
        if usage.ratio > 0.7 { return AppTheme.accent }
        return Color(hue: 0.58, saturation: 0.75, brightness: 0.95)
    }

    private func bucketPercent(_ bucket: ContextBucket) -> String {
        guard usage.totalCharacters > 0 else { return "0%" }
        let p = Double(bucket.characters) / Double(usage.totalCharacters) * 100
        return String(format: "%.1f%%", p)
    }
}

/// 上下文占用环形进度。
///
/// 用 `trim` 画轨与进度弧，比系统线性条更适合紧凑按钮与弹出总览。
struct ContextUsageRing: View {
    /// 0...1 占用比例；超过 1 会按满环绘制。
    let ratio: Double
    /// 环线宽。
    var lineWidth: CGFloat = 4
    /// 进度色。
    var tint: Color
    /// 底轨色。
    var track: Color = Color.secondary.opacity(0.25)

    var body: some View {
        let clamped = min(1, max(0, ratio))
        ZStack {
            Circle()
                .stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: clamped)
        }
        .accessibilityValue(Text(String(format: "%.0f%%", clamped * 100)))
    }
}
