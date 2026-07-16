/// 主窗口侧栏导航与模块路由。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// 侧栏一级模块。
///
/// 「黑妞」不再作为工作台首项，而是在「配置」上方以可展开列表展示具体角色。
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    /// 项目。
    case projects
    /// 剧本。
    case scripts
    /// 分镜。
    case storyboards
    /// 资产库。
    case assets
    /// 设置。
    case settings
    /// 技能。
    case skills
    /// MCP。
    case mcp

    /// 唯一标识符。
    var id: String { rawValue }

    /// 标题。
    var title: String {
        switch self {
        case .projects: "项目"
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
        case .projects: "folder"
        case .scripts: "doc.text"
        case .storyboards: "rectangle.split.3x1"
        case .assets: "square.grid.2x2"
        case .settings: "gearshape"
        case .skills: "bolt.fill"
        case .mcp: "server.rack"
        }
    }

    /// 工作台（不含黑妞）。
    static let workspaceItems: [SidebarItem] = [.projects, .scripts, .storyboards, .assets]
    /// 配置。
    static let configItems: [SidebarItem] = [.settings, .skills, .mcp]
}

/// 侧栏选中目标：模块 或 某位黑妞。
private enum SidebarSelection: Hashable {
    case module(SidebarItem)
    case agent(UUID)
}

/// MainView
///
/// 主窗口：侧栏（工作台 / 黑妞下拉 / 配置）+ 详情。
struct MainView: View {
    @Environment(HeiNiuAgentStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    @State private var selection: SidebarSelection? = nil
    @State private var heiniuExpanded = true
    @State private var selectedConversationID: UUID?
    @State private var editingAgent: HeiNiuAgent?
    @State private var pendingDelete: HeiNiuAgent?

    /// 当前侧栏选中的黑妞。
    private var selectedAgent: HeiNiuAgent? {
        if case .agent(let id) = selection {
            return store.agent(id: id)
        }
        return nil
    }

    /// 导航标题。
    private var currentTitle: String {
        if let agent = selectedAgent {
            return agent.name
        }
        if case .module(let item) = selection {
            return item.title
        }
        return "黑妞短剧"
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
        .onAppear {
            // 默认打开第一位黑妞
            if selection == nil {
                if let first = store.sortedAgents.first {
                    selection = .agent(first.id)
                    restoreConversation(for: first.id)
                } else {
                    selection = .module(.settings)
                }
            }
        }
        .onChange(of: store.sortedAgents.map(\.id)) { _, ids in
            // 当前选中的黑妞被删掉时，落到列表第一位
            if case .agent(let id) = selection, !ids.contains(id) {
                if let first = ids.first {
                    selection = .agent(first)
                    restoreConversation(for: first)
                } else {
                    selection = .module(.settings)
                    selectedConversationID = nil
                }
            }
        }
        .sheet(item: $editingAgent) { agent in
            HeiNiuAgentEditorView(agent: agent) { updated in
                store.updateAgent(updated)
            }
            .environment(settings)
            .environment(store)
            .frame(width: 900, height: 640)
        }
        .confirmationDialog(
            "删除「\(pendingDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = pendingDelete?.id {
                    store.deleteAgent(id: id)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("相关对话也会一并删除。")
        }
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
                            .tag(SidebarSelection.module(item))
                            .font(.body)
                    }
                } header: {
                    Text("工作台")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                // 黑妞：配置上方，可展开列出角色
                Section {
                    DisclosureGroup(isExpanded: $heiniuExpanded) {
                        if store.sortedAgents.isEmpty {
                            Text("还没有黑妞")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textTertiary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(store.sortedAgents) { agent in
                                agentRow(agent)
                                    .tag(SidebarSelection.agent(agent.id))
                            }
                        }

                        Button {
                            createAgent()
                        } label: {
                            Label("新建黑妞", systemImage: "plus")
                                .font(.callout)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                        .padding(.vertical, 2)
                    } label: {
                        HStack(spacing: 8) {
                            Label("黑妞", systemImage: "sparkles")
                                .font(.body)
                            Spacer(minLength: 4)
                            Text("\(store.sortedAgents.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(AppTheme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(AppTheme.bgElevated, in: Capsule())
                        }
                    }
                }

                Section {
                    ForEach(SidebarItem.configItems) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(SidebarSelection.module(item))
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
            .onChange(of: selection) { _, newValue in
                if case .agent(let id) = newValue {
                    restoreConversation(for: id)
                }
            }

            Spacer(minLength: 0)
        }
        .background(AppTheme.bgSidebar)
    }

    /// 侧栏中的单个黑妞行。
    private func agentRow(_ agent: HeiNiuAgent) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(agent.accentColor.opacity(0.18))
                    .frame(width: 22, height: 22)
                Image(systemName: agent.iconSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(agent.accentColor)
            }
            Text(agent.name)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button("编辑") { editingAgent = store.agent(id: agent.id) ?? agent }
            Button("复制") {
                if let copy = store.duplicateAgent(id: agent.id) {
                    heiniuExpanded = true
                    selection = .agent(copy.id)
                    selectedConversationID = nil
                }
            }
            Divider()
            Button("删除", role: .destructive) { pendingDelete = agent }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .agent(let id):
            if let agent = store.agent(id: id) {
                HeiNiuChatView(
                    agent: agent,
                    conversationID: $selectedConversationID,
                    onEdit: {
                        editingAgent = store.agent(id: agent.id) ?? agent
                    }
                )
                .id(agent.id)
            } else {
                EmptyStateView(
                    title: "黑妞不存在",
                    message: "该角色可能已被删除。",
                    systemImage: "sparkles",
                    actionTitle: "新建黑妞",
                    action: createAgent
                )
            }

        case .module(let item):
            moduleDetail(item)

        case .none:
            EmptyStateView(
                title: "创建你的第一位黑妞",
                message: "黑妞类似 Gemini 的 Gem 或 OpenAI 的 Custom GPT：自定义人设、指令与模型，随时开聊。",
                systemImage: "sparkles",
                actionTitle: "新建黑妞",
                action: createAgent
            )
        }
    }

    @ViewBuilder
    private func moduleDetail(_ item: SidebarItem) -> some View {
        switch item {
        case .projects:
            ProjectsHomeView { agentID in
                heiniuExpanded = true
                selection = .agent(agentID)
                restoreConversation(for: agentID)
            }
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

    // MARK: - Actions

    private func createAgent() {
        heiniuExpanded = true
        let agent = store.addAgent()
        selection = .agent(agent.id)
        selectedConversationID = nil
        editingAgent = agent
    }

    /// 恢复该黑妞最近会话（优先有消息的）。
    private func restoreConversation(for agentID: UUID) {
        let list = store.conversations(for: agentID)
        selectedConversationID = list.first(where: { !$0.messages.isEmpty })?.id ?? list.first?.id
    }
}

#Preview {
    MainView()
        .environment(SettingsStore())
        .environment(HeiNiuAgentStore())
        .environment(ProjectStore())
        .frame(width: 1180, height: 760)
}
