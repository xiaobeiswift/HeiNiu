/// 黑妞首页：角色列表 + 聊天区。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// HeiNiuHomeView
///
/// `HeiNiuHomeView` 类型定义。
struct HeiNiuHomeView: View {
    @Environment(HeiNiuAgentStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    @State private var selectedAgentID: UUID?
    @State private var selectedConversationID: UUID?
    @State private var editingAgent: HeiNiuAgent?
    @State private var pendingDelete: HeiNiuAgent?

    /// selectedAgent。
    private var selectedAgent: HeiNiuAgent? {
        store.agent(id: selectedAgentID) ?? store.sortedAgents.first
    }

    /// SwiftUI 视图内容。
    var body: some View {
        HStack(spacing: 0) {
            agentRail
                .frame(width: 280)
                .background(AppTheme.bgSidebar)

            Divider().opacity(0.5)

            if let agent = selectedAgent {
                HeiNiuChatView(
                    agent: agent,
                    conversationID: $selectedConversationID,
                    onEdit: {
                        // 直接塞完整模型，避免 sheet 时序导致空内容
                        editingAgent = store.agent(id: agent.id) ?? agent
                    }
                )
                .id(agent.id)
            } else {
                EmptyStateView(
                    title: "创建你的第一位黑妞",
                    message: "黑妞类似 Gemini 的 Gem 或 OpenAI 的 Custom GPT：自定义人设、指令与模型，随时开聊。",
                    systemImage: "sparkles",
                    actionTitle: "新建黑妞",
                    action: createAgent
                )
            }
        }
        .background(AppTheme.bgBase)
        .onAppear {
            if selectedAgentID == nil {
                selectedAgentID = store.sortedAgents.first?.id
            }
            // 打开工作台时回到该黑妞最近会话，不要每次新建
            restoreSelectedConversationIfNeeded()
        }
        .onChange(of: selectedAgentID) { _, _ in
            restoreSelectedConversationIfNeeded(force: true)
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
                    if selectedAgentID == id {
                        selectedAgentID = store.sortedAgents.first?.id
                        selectedConversationID = nil
                    }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("相关对话也会一并删除。")
        }
    }

    /// agentRail。
    private var agentRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("黑妞")
                        .font(.title3.weight(.semibold))
                    Text("自定义 AI 角色")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }
                Spacer()
                Button(action: createAgent) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(AppTheme.accentSoft, in: Circle())
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .help("新建黑妞")
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            if store.sortedAgents.isEmpty {
                Text("还没有黑妞")
                    .font(.callout)
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.sortedAgents) { agent in
                            AgentRailRow(
                                agent: agent,
                                isSelected: selectedAgent?.id == agent.id,
                                providerName: settings.provider(id: agent.providerID)?.name,
                                onSelect: {
                                    selectedAgentID = agent.id
                                },
                                onEdit: {
                                    editingAgent = agent
                                },
                                onDuplicate: {
                                    if let copy = store.duplicateAgent(id: agent.id) {
                                        selectedAgentID = copy.id
                                        // onChange(selectedAgentID) 会恢复会话；新副本通常无历史
                                    }
                                },
                                onDelete: {
                                    pendingDelete = agent
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    /// createAgent
    ///
    /// 执行 `createAgent` 相关逻辑。
    private func createAgent() {
        let agent = store.addAgent()
        selectedAgentID = agent.id
        selectedConversationID = nil
        editingAgent = agent
    }

    /// 为当前选中黑妞恢复最近会话（优先有消息的）。
    private func restoreSelectedConversationIfNeeded(force: Bool = false) {
        guard let agentID = selectedAgentID ?? store.sortedAgents.first?.id else {
            selectedConversationID = nil
            return
        }

        if !force,
           let selectedConversationID,
           let existing = store.conversation(id: selectedConversationID),
           existing.agentID == agentID {
            return
        }

        let list = store.conversations(for: agentID)
        selectedConversationID = list.first(where: { !$0.messages.isEmpty })?.id ?? list.first?.id
    }
}

/// AgentRailRow
///
/// `AgentRailRow` 类型定义。
private struct AgentRailRow: View {
    /// 按 ID 查找黑妞。
    let agent: HeiNiuAgent
    /// isSelected。
    let isSelected: Bool
    /// providerName。
    let providerName: String?
    /// onSelect。
    let onSelect: () -> Void
    /// onEdit。
    let onEdit: () -> Void
    /// onDuplicate。
    let onDuplicate: () -> Void
    /// onDelete。
    let onDelete: () -> Void

    /// SwiftUI 视图内容。
    var body: some View {
        // 整行可点选；右侧菜单单独扩大热区，避免抢点击
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(agent.accentColor.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: agent.iconSymbol)
                            .foregroundStyle(agent.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(agent.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(1)
                            if agent.isBuiltIn {
                                Text("预置")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(AppTheme.accentSoft, in: Capsule())
                            }
                        }
                        Text(agent.subtitle.isEmpty ? (providerName ?? "未绑定模型") : agent.subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 36)
                }
                .padding(.leading, 12)
                .padding(.trailing, 40)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? AppTheme.accentSoft : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? AppTheme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Menu {
                Button("编辑", action: onEdit)
                Button("复制", action: onDuplicate)
                Divider()
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .padding(.trailing, 6)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
