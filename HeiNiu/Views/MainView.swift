/// 主窗口侧栏导航与模块路由。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// 侧栏一级模块。
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    /// 节点式工作流。
    case workflows
    /// 剧本。
    case scripts
    /// 分镜。
    case storyboards
    /// 知识库。
    case knowledge
    /// 设置。
    case settings

    /// 唯一标识符。
    var id: String { rawValue }

    /// 标题。
    var title: String {
        switch self {
        case .workflows: "工作流"
        case .scripts: "剧本"
        case .storyboards: "分镜"
        case .knowledge: "知识库"
        case .settings: "设置"
        }
    }

    /// 用于 UI 的 SF Symbol。
    var systemImage: String {
        switch self {
        case .workflows: "point.3.connected.trianglepath.dotted"
        case .scripts: "doc.text"
        case .storyboards: "rectangle.split.3x1"
        case .knowledge: "books.vertical"
        case .settings: "gearshape"
        }
    }

    /// 工作台模块。
    static let workspaceItems: [SidebarItem] = [.knowledge, .workflows, .scripts, .storyboards]
}

/// 主窗口：工作台导航与详情。
struct MainView: View {
    @State private var selection: SidebarItem? = .knowledge

    /// 导航标题。
    private var currentTitle: String {
        selection?.title ?? "黑妞短剧"
    }

    /// SwiftUI 视图内容。
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: 200,
                    ideal: AppTheme.sidebarWidth,
                    max: 280
                )
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.bgBase)
                .navigationTitle(currentTitle)
        }
        .background(AppTheme.bgBase)
        .navigationTitle(currentTitle)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.accentSoft)
                        .frame(width: 28, height: 28)
                    Image(systemName: "film.stack")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("黑妞短剧")
                        .font(.headline)
                    Text("短剧创作工作台")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            List(selection: $selection) {
                Section {
                    ForEach(SidebarItem.workspaceItems) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                            .font(.body)
                    }
                } header: {
                    Text("工作台")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Section {
                    Label(SidebarItem.settings.title, systemImage: SidebarItem.settings.systemImage)
                        .tag(SidebarItem.settings)
                        .font(.body)
                } header: {
                    Text("配置")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)
        }
        .background(AppTheme.bgSidebar)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .workflows:
            WorkflowHomeView()
        case .scripts:
            PlaceholderView(
                title: "剧本",
                systemImage: "doc.text",
                message: "根据简报或源文本生成短剧剧本。",
                badge: "即将推出"
            )
        case .storyboards:
            PlaceholderView(
                title: "分镜",
                systemImage: "rectangle.split.3x1",
                message: "将剧本拆成镜头，并生成视频提示词。",
                badge: "即将推出"
            )
        case .knowledge:
            KnowledgeHomeView()
        case .settings:
            SettingsView()
        case .none:
            KnowledgeHomeView()
        }
    }
}

#Preview {
    MainView()
        .environment(SettingsStore())
        .environment(KnowledgeStore())
        .environment(WorkflowStore())
        .frame(width: 1180, height: 760)
}
