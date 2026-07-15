/// 胶囊分段 Tab 与任务芯片条。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// StudioTabItem
///
/// `StudioTabItem` 类型定义。
struct StudioTabItem: Identifiable, Hashable {
    /// 唯一标识符。
    let id: String
    /// 标题。
    let title: String
    /// 用于 UI 的 SF Symbol。
    let systemImage: String
}

/// StudioTabBar
///
/// `StudioTabBar` 类型定义。
struct StudioTabBar: View {
    /// items。
    let items: [StudioTabItem]
    @Binding var selection: String

    /// SwiftUI 视图内容。
    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                let selected = selection == item.id
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = item.id
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.caption.weight(.semibold))
                        Text(item.title)
                            .font(.subheadline.weight(selected ? .semibold : .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(selected ? AppTheme.accent : AppTheme.textSecondary)
                    .background(
                        Capsule()
                            .fill(selected ? AppTheme.accentSoft : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(AppTheme.bgElevated)
        )
        .overlay(
            Capsule()
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }
}

/// TaskChipBar
///
/// `TaskChipBar` 类型定义。
struct TaskChipBar<T: Hashable & Identifiable>: View where T: CaseIterable {
    /// tasks。
    let tasks: [T]
    /// 标题。
    @Binding var selection: T
    let title: (T) -> String
    /// 用于 UI 的 SF Symbol。
    let systemImage: (T) -> String

    /// SwiftUI 视图内容。
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tasks) { task in
                    let selected = selection.id == task.id
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection = task
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: systemImage(task))
                                .font(.caption)
                            Text(title(task))
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(selected ? AppTheme.accent : AppTheme.textSecondary)
                        .background(
                            Capsule().fill(selected ? AppTheme.accentSoft : AppTheme.bgElevated)
                        )
                        .overlay(
                            Capsule().stroke(
                                selected ? AppTheme.accent.opacity(0.35) : AppTheme.stroke,
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

/// AutoSaveIndicator
///
/// `AutoSaveIndicator` 类型定义。
struct AutoSaveIndicator: View {
    /// visible。
    var visible: Bool

    /// SwiftUI 视图内容。
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
            Text("已自动保存")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(AppTheme.success)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: visible)
    }
}
