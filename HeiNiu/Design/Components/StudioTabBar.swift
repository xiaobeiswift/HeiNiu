import SwiftUI

struct StudioTabItem: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
}

struct StudioTabBar: View {
    let items: [StudioTabItem]
    @Binding var selection: String

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

struct TaskChipBar<T: Hashable & Identifiable>: View where T: CaseIterable {
    let tasks: [T]
    @Binding var selection: T
    let title: (T) -> String
    let systemImage: (T) -> String

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

struct AutoSaveIndicator: View {
    var visible: Bool

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
