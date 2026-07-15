/// 黑妞编辑：左侧导航 + 右侧详情。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 左侧分类导航 + 右侧详情（参考图布局）
struct HeiNiuAgentEditorView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(HeiNiuAgentStore.self) private var agentStore
    @Environment(\.dismiss) private var dismiss

    /// onSave。
    @State private var draft: HeiNiuAgent
    let onSave: (HeiNiuAgent) -> Void

    @State private var pane: AgentEditorPane = .model
    @State private var newStarter = ""
    @State private var noteTitle = ""
    @State private var noteBody = ""
    @State private var showNoteEditor = false

    /// 初始化方法
    ///
    /// 初始化方法。
    init(agent: HeiNiuAgent, onSave: @escaping (HeiNiuAgent) -> Void) {
        _draft = State(initialValue: agent)
        self.onSave = onSave
    }

    /// 知识库条目索引。
    private var knowledgeItems: [KnowledgeItem] {
        agentStore.knowledge(for: draft.id)
    }

    /// selectedProvider。
    private var selectedProvider: LLMProvider? {
        settings.provider(id: draft.providerID)
    }

    /// allSkillsEnabled。
    private var allSkillsEnabled: Bool {
        draft.enabledSkillIDs.isEmpty
    }

    /// SwiftUI 视图内容。
    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                leftNav
                    .frame(width: 200)
                    .background(AppTheme.bgSidebar)

                Divider().opacity(0.4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Text(pane.title)
                                .font(.title2.weight(.semibold))
                            if pane == .mcp {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(AppTheme.textTertiary)
                                    .help("服务器清单在「配置 → MCP」管理；此处只选本黑妞策略。")
                            }
                            Spacer()
                        }
                        detailBody
                    }
                    .padding(24)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(AppTheme.bgBase)
            }
            .navigationTitle("编辑黑妞")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onChange(of: draft.providerID) { _, newValue in
            if let provider = settings.provider(id: newValue) {
                if draft.model.isEmpty || !provider.models.contains(draft.model) {
                    draft.model = provider.models.first ?? ""
                }
            }
        }
    }

    /// leftNav。
    private var leftNav: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.name.isEmpty ? "编辑黑妞" : draft.name)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ForEach(AgentEditorPane.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) { pane = item }
                } label: {
                    Text(item.title)
                        .font(.body.weight(pane == item ? .semibold : .regular))
                        .foregroundStyle(pane == item ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(pane == item ? Color.primary.opacity(0.10) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
            }
            Spacer()
        }
    }

    /// detailBody。
    @ViewBuilder
    private var detailBody: some View {
        switch pane {
        case .model: modelPane
        case .prompt: promptPane
        case .knowledge: knowledgePane
        case .mcp: mcpPane
        case .phrases: phrasesPane
        case .profile: profilePane
        }
    }

    // MARK: - Model

    /// modelPane。
    private var modelPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioCard(title: "服务商与模型") {
                VStack(alignment: .leading, spacing: 12) {
                    labeledPicker("服务商") {
                        Picker("服务商", selection: $draft.providerID) {
                            Text("未选择").tag(Optional<UUID>.none)
                            ForEach(settings.providers) { p in
                                Text(p.name).tag(Optional(p.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    if let provider = selectedProvider, !provider.models.isEmpty {
                        labeledPicker("模型") {
                            Picker("模型", selection: $draft.model) {
                                ForEach(provider.models, id: \.self) { m in
                                    Text(m).tag(m)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    } else {
                        StudioTextField(title: "模型 ID", text: $draft.model, placeholder: "手动填写", monospaced: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("温度")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                            Spacer()
                            Text(String(format: "%.2f", draft.temperature))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(AppTheme.accent)
                        }
                        Slider(value: $draft.temperature, in: 0...2, step: 0.05)
                            .tint(AppTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("思考等级")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        Picker("思考等级", selection: $draft.reasoningEffort) {
                            ForEach(ReasoningEffort.allCases) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(draft.reasoningEffort.subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                        Text("对支持 reasoning 的模型生效（如部分 OpenAI Responses / o 系列）；选「默认」则不发送该参数。")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("上下文容量")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                            Spacer()
                            Text(draft.contextLimitDisplayText)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(AppTheme.accent)
                        }

                        labeledPicker("预设") {
                            Picker("上下文容量", selection: contextLimitSelection) {
                                ForEach(HeiNiuAgent.contextLimitPresets, id: \.self) { limit in
                                    Text(HeiNiuAgent.formatContextLimit(limit)).tag(Optional(limit))
                                }
                                Text("自定义").tag(Optional<Int>.none)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        if !HeiNiuAgent.contextLimitPresets.contains(draft.contextCharacterLimit) {
                            HStack(spacing: 8) {
                                TextField("字符数", value: $draft.contextCharacterLimit, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 160)
                                Text("字符")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                        }

                        Text("按字符近似估算占用（中文场景更直观），用于聊天区容量环；不是 API 的真实 token 窗口。百万级模型可调到 100 万 / 200 万。")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    if settings.providers.isEmpty {
                        Text("请先到「配置 → 设置 → 服务商」添加。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.danger)
                    }
                }
            }

            StudioCard(
                title: "可调用技能",
                subtitle: "这里是能力包，不是 /goal /plan 等工作模式。技能库在「配置 → 技能」维护。"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if agentStore.sortedSkills.isEmpty {
                        Text("还没有技能。请到「配置 → 技能」添加，例如写大纲、润色对白。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    } else {
                        Toggle(isOn: Binding(
                            get: { allSkillsEnabled },
                            set: { on in
                                draft.enabledSkillIDs = on ? [] : agentStore.sortedSkills.map(\.id)
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("允许全部技能")
                                Text("关闭后可逐项勾选")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                        }
                        .toggleStyle(.switch)

                        ForEach(agentStore.sortedSkills) { skill in
                            let on = allSkillsEnabled || draft.enabledSkillIDs.contains(skill.id)
                            HStack(spacing: 10) {
                                Button { toggleSkill(skill) } label: {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(on ? AppTheme.accent : AppTheme.textTertiary)
                                }
                                .buttonStyle(.plain)
                                .disabled(allSkillsEnabled)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(skill.name).font(.subheadline.weight(.medium))
                                        Text(skill.slash)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                    Text(skill.summary)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textTertiary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    /// promptPane。
    private var promptPane: some View {
        StudioCard(title: "系统指令") {
            TextEditor(text: $draft.instructions)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 360)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.bgElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.stroke, lineWidth: 1)
                )
        }
    }

    /// knowledgePane。
    private var knowledgePane: some View {
        StudioCard(title: "知识库", subtitle: "仅属于本黑妞") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        importKnowledgeFiles()
                    } label: {
                        Label("导入文件", systemImage: "doc.badge.plus")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppTheme.accentSoft, in: Capsule())
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)

                    Button { showNoteEditor.toggle() } label: {
                        Label("添加笔记", systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppTheme.bgElevated, in: Capsule())
                            .overlay(Capsule().stroke(AppTheme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("\(knowledgeItems.count) 项")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }

                if showNoteEditor {
                    VStack(alignment: .leading, spacing: 8) {
                        StudioTextField(title: "标题", text: $noteTitle, placeholder: "人物小传…")
                        TextEditor(text: $noteBody)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 100)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppTheme.bgElevated)
                            )
                        Button("保存到知识库") {
                            agentStore.addKnowledgeNote(agentID: draft.id, title: noteTitle, body: noteBody)
                            noteTitle = ""; noteBody = ""; showNoteEditor = false
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                        .disabled(noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if knowledgeItems.isEmpty {
                    Text("还没有知识库内容。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                } else {
                    ForEach(knowledgeItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.subheadline.weight(.medium))
                                Text("\(item.charCount) 字符")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                            Spacer()
                            Toggle("启用", isOn: Binding(
                                get: { item.enabled },
                                set: { v in
                                    var u = item; u.enabled = v
                                    agentStore.updateKnowledge(u)
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            Button(role: .destructive) {
                                agentStore.deleteKnowledge(id: item.id)
                            } label: {
                                Image(systemName: "trash").foregroundStyle(AppTheme.danger)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    /// mcpPane。
    private var mcpPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择本黑妞如何使用 MCP。服务器请到「配置 → MCP」添加。")
                .font(.callout)
                .foregroundStyle(AppTheme.textSecondary)

            ForEach(AgentMCPMode.allCases) { mode in
                let selected = draft.mcpMode == mode
                Button { draft.mcpMode = mode } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mode.title)
                            .font(.headline)
                            .foregroundStyle(selected ? AppTheme.success : AppTheme.textPrimary)
                        Text(mode.subtitle)
                            .font(.callout)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.bgCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                selected ? AppTheme.success.opacity(0.85) : AppTheme.stroke,
                                lineWidth: selected ? 1.5 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            if draft.mcpMode == .manual {
                StudioCard(title: "选择服务器") {
                    if settings.mcpServers.isEmpty {
                        Text("还没有全局 MCP，请先到「配置 → MCP」添加。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    } else {
                        ForEach(settings.sortedMCPServers) { server in
                            let on = draft.enabledMCPServerIDs.contains(server.id)
                            HStack {
                                Button { toggleMCP(server.id) } label: {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(on ? AppTheme.accent : AppTheme.textTertiary)
                                }
                                .buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name).font(.subheadline.weight(.medium))
                                    Text(server.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    /// phrasesPane。
    private var phrasesPane: some View {
        StudioCard(title: "常用短语 / 开场建议") {
            VStack(alignment: .leading, spacing: 10) {
                if draft.conversationStarters.isEmpty {
                    Text("进入聊天时展示的快捷提问")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                } else {
                    ForEach(draft.conversationStarters, id: \.self) { starter in
                        HStack {
                            Text(starter).font(.callout)
                            Spacer()
                            Button {
                                draft.conversationStarters.removeAll { $0 == starter }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                HStack {
                    TextField("添加短语", text: $newStarter)
                        .textFieldStyle(.plain)
                        .studioField()
                        .onSubmit { addStarter() }
                    Button("添加") { addStarter() }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                        .disabled(newStarter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    /// profilePane。
    private var profilePane: some View {
        StudioCard(title: "基本资料") {
            VStack(alignment: .leading, spacing: 12) {
                StudioTextField(title: "名称", text: $draft.name, placeholder: "例如：编剧黑妞")
                StudioTextField(title: "简介", text: $draft.subtitle, placeholder: "一句话说明")
                VStack(alignment: .leading, spacing: 8) {
                    Text("图标")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    FlowLayout(spacing: 8) {
                        ForEach(HeiNiuAgent.iconChoices, id: \.self) { symbol in
                            let selected = draft.iconSymbol == symbol
                            Button { draft.iconSymbol = symbol } label: {
                                Image(systemName: symbol)
                                    .frame(width: 36, height: 36)
                                    .foregroundStyle(selected ? draft.accentColor : AppTheme.textSecondary)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(selected ? draft.accentColor.opacity(0.16) : AppTheme.bgElevated)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(selected ? draft.accentColor.opacity(0.4) : AppTheme.stroke, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// labeledPicker
    ///
    /// 执行 `labeledPicker` 相关逻辑。
    private func labeledPicker<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            content()
        }
    }

    /// toggleSkill
    ///
    /// 执行 `toggleSkill` 相关逻辑。
    private func toggleSkill(_ skill: HeiNiuSkill) {
        if allSkillsEnabled {
            draft.enabledSkillIDs = agentStore.sortedSkills.map(\.id).filter { $0 != skill.id }
            return
        }
        if draft.enabledSkillIDs.contains(skill.id) {
            draft.enabledSkillIDs.removeAll { $0 == skill.id }
        } else {
            draft.enabledSkillIDs.append(skill.id)
        }
        if Set(draft.enabledSkillIDs) == Set(agentStore.sortedSkills.map(\.id)) {
            draft.enabledSkillIDs = []
        }
    }

    /// toggleMCP
    ///
    /// 执行 `toggleMCP` 相关逻辑。
    private func toggleMCP(_ id: UUID) {
        if draft.enabledMCPServerIDs.contains(id) {
            draft.enabledMCPServerIDs.removeAll { $0 == id }
        } else {
            draft.enabledMCPServerIDs.append(id)
        }
    }

    /// addStarter
    ///
    /// 执行 `addStarter` 相关逻辑。
    private func addStarter() {
        let text = newStarter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !draft.conversationStarters.contains(text) {
            draft.conversationStarters.append(text)
        }
        newStarter = ""
    }

    /// importKnowledgeFiles
    ///
    /// 执行 `importKnowledgeFiles` 相关逻辑。
    private func importKnowledgeFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .plainText, .utf8PlainText, .sourceCode, .json, .xml, .html,
            .commaSeparatedText, .pdf, .data,
        ]
        guard panel.runModal() == .OK else { return }
        _ = agentStore.importKnowledge(from: panel.urls, agentID: draft.id)
    }

    /// 将当前状态写入磁盘
    ///
    /// 将当前状态写入磁盘。
    private func save() {
        var cleaned = draft
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.name.isEmpty { cleaned.name = "未命名黑妞" }
        cleaned.subtitle = cleaned.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.model = cleaned.model.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.contextCharacterLimit = max(1_000, cleaned.contextCharacterLimit)
        let skillIDs = Set(agentStore.skills.map(\.id))
        cleaned.enabledSkillIDs.removeAll { !skillIDs.contains($0) }
        let mcpIDs = Set(settings.mcpServers.map(\.id))
        cleaned.enabledMCPServerIDs.removeAll { !mcpIDs.contains($0) }
        onSave(cleaned)
        dismiss()
    }

    /// 上下文容量预设选择：命中预设则绑定具体值，否则进入「自定义」。
    private var contextLimitSelection: Binding<Int?> {
        Binding(
            get: {
                HeiNiuAgent.contextLimitPresets.contains(draft.contextCharacterLimit)
                    ? draft.contextCharacterLimit
                    : nil
            },
            set: { newValue in
                if let newValue {
                    draft.contextCharacterLimit = newValue
                } else if HeiNiuAgent.contextLimitPresets.contains(draft.contextCharacterLimit) {
                    // 从预设切到自定义时给一个可改的起点
                    draft.contextCharacterLimit = 1_000_000
                }
            }
        )
    }
}

/// AgentEditorPane
///
/// `AgentEditorPane` 类型定义。
private enum AgentEditorPane: String, CaseIterable, Identifiable {
    /// 模型 ID。
    case model, prompt, knowledge, mcp, phrases, profile
    /// 唯一标识符。
    var id: String { rawValue }
    /// 标题。
    var title: String {
        switch self {
        case .model: "模型设置"
        case .prompt: "提示词设置"
        case .knowledge: "知识库设置"
        case .mcp: "MCP 服务器"
        case .phrases: "常用短语"
        case .profile: "基本资料"
        }
    }
}
