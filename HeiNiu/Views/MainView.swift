/// 主窗口侧栏导航与模块路由。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// SidebarItem
///
/// `SidebarItem` 类型定义。
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    /// heiniu。
    case heiniu
    /// learn。
    case learn
    /// scripts。
    case scripts
    /// storyboards。
    case storyboards
    /// assets。
    case assets
    /// 全局设置仓库环境对象。
    case settings
    /// 按范围或插件筛选技能
    ///
    /// 按范围或插件筛选技能。
    case skills
    /// mcp。
    case mcp

    /// 唯一标识符。
    var id: String { rawValue }

    /// 标题。
    var title: String {
        switch self {
        case .heiniu: "黑妞"
        case .learn: "学习"
        case .scripts: "剧本"
        case .storyboards: "分镜"
        case .assets: "资产库"
        case .settings: "设置"
        case .skills: "技能"
        case .mcp: "MCP"
        }
    }

    /// 用于 UI 的 SF Symbol。
    var systemImage: String {
        switch self {
        case .heiniu: "sparkles"
        case .learn: "graduationcap"
        case .scripts: "doc.text"
        case .storyboards: "rectangle.split.3x1"
        case .assets: "square.grid.2x2"
        case .settings: "gearshape"
        case .skills: "bolt.fill"
        case .mcp: "server.rack"
        }
    }

    /// workspaceItems。
    static let workspaceItems: [SidebarItem] = [.heiniu, .learn, .scripts, .storyboards, .assets]
    /// configItems。
    static let configItems: [SidebarItem] = [.settings, .skills, .mcp]
}

/// MainView
///
/// `MainView` 类型定义。
struct MainView: View {
    @State private var selection: SidebarItem? = .heiniu

    /// currentTitle。
    private var currentTitle: String {
        selection?.title ?? "黑妞"
    }

    /// SwiftUI 视图内容。
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: 180,
                    ideal: AppTheme.sidebarWidth,
                    max: 260
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

    /// sidebar。
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
                    ForEach(SidebarItem.configItems) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                            .font(.body)
                    }
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

    /// detailView。
    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .heiniu, .none:
            HeiNiuHomeView()
        case .learn:
            PlaceholderView(
                title: "学习",
                systemImage: "graduationcap",
                message: "从参考视频中提炼产品卖点、拍摄清单与提示词。",
                badge: "即将推出"
            )
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
        case .assets:
            PlaceholderView(
                title: "资产库",
                systemImage: "square.grid.2x2",
                message: "管理角色、场景与道具等可复用资产。",
                badge: "即将推出"
            )
        case .settings:
            SettingsView()
        case .skills:
            ScrollView {
                SkillsSettingsView()
                    .studioContentWidth()
                    .padding(28)
            }
        case .mcp:
            ScrollView {
                MCPSettingsView()
                    .studioContentWidth()
                    .padding(28)
            }
        }
    }
}

#Preview {
    MainView()
        .environment(SettingsStore())
        .environment(HeiNiuAgentStore())
        .frame(width: 1180, height: 760)
}
