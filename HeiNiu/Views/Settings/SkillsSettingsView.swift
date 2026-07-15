/// 插件与技能库（内置/个人）配置界面。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// 配置 → 技能：Codex 风格 · 插件 / 技能 × 内置 / 个人
struct SkillsSettingsView: View {
    @Environment(HeiNiuAgentStore.self) private var agents

    @State private var topTab: TopTab = .skills
    @State private var scope: SkillScope = .builtIn

    @State private var editingSkill: HeiNiuSkill?
    @State private var creatingSkill: HeiNiuSkill?
    @State private var pendingDeleteSkill: HeiNiuSkill?

    /// TopTab
    ///
    /// `TopTab` 类型定义。
    @State private var editingPlugin: HeiNiuPlugin?
    @State private var creatingPlugin: HeiNiuPlugin?
    @State private var pendingDeletePlugin: HeiNiuPlugin?
    private enum TopTab: String, CaseIterable, Identifiable {
        /// 按范围筛选插件
        ///
        /// 按范围筛选插件。
        case plugins
        /// 按范围或插件筛选技能
        ///
        /// 按范围或插件筛选技能。
        case skills
        var id: String { rawValue }
        var title: String {
            switch self {
            case .plugins: "插件"
            case .skills: "技能"
            }
        }
    }

    /// SwiftUI 视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            // 插件 | 技能 —— 整块可点，热区更大
            HStack(spacing: 6) {
                ForEach(TopTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { topTab = tab }
                    } label: {
                        Text(tab.title)
                            .font(.body.weight(topTab == tab ? .semibold : .medium))
                            .foregroundStyle(topTab == tab ? AppTheme.accent : AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(topTab == tab ? AppTheme.accentSoft : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())

            // 内置 | 个人
            Picker("范围", selection: $scope) {
                ForEach(SkillScope.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)

            switch topTab {
            case .plugins:
                pluginsList
            case .skills:
                skillsList
            }
        }
        .sheet(item: $editingSkill) { skill in
            SkillEditorSheet(skill: skill, plugins: agents.sortedPlugins) { updated in
                agents.updateSkill(updated)
            }
            .frame(width: 560, height: 560)
        }
        .sheet(item: $creatingSkill) { skill in
            SkillEditorSheet(skill: skill, plugins: agents.sortedPlugins) { updated in
                agents.upsertSkill(updated)
            }
            .frame(width: 560, height: 560)
        }
        .sheet(item: $editingPlugin) { plugin in
            PluginEditorSheet(plugin: plugin) { updated in
                agents.updatePlugin(updated)
            }
            .frame(width: 480, height: 420)
        }
        .sheet(item: $creatingPlugin) { plugin in
            PluginEditorSheet(plugin: plugin) { updated in
                agents.upsertPlugin(updated)
            }
            .frame(width: 480, height: 420)
        }
        .confirmationDialog(
            "删除技能「\(pendingDeleteSkill?.name ?? "")」？",
            isPresented: Binding(
                get: { pendingDeleteSkill != nil },
                set: { if !$0 { pendingDeleteSkill = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = pendingDeleteSkill?.id { agents.deleteSkill(id: id) }
                pendingDeleteSkill = nil
            }
            Button("取消", role: .cancel) { pendingDeleteSkill = nil }
        }
        .confirmationDialog(
            "删除插件「\(pendingDeletePlugin?.name ?? "")」？",
            isPresented: Binding(
                get: { pendingDeletePlugin != nil },
                set: { if !$0 { pendingDeletePlugin = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = pendingDeletePlugin?.id { agents.deletePlugin(id: id) }
                pendingDeletePlugin = nil
            }
            Button("取消", role: .cancel) { pendingDeletePlugin = nil }
        }
    }

    /// header。
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(topTab == .plugins ? "插件" : "技能")
                    .font(.title3.weight(.semibold))
                Text(
                    topTab == .plugins
                    ? "插件是能力包容器，可启用/禁用；内置插件不可删除。"
                    : "技能是可复用能力（$command）。对话模式 /goal /plan 等不在此管理。"
                )
                .font(.callout)
                .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            if scope == .personal {
                Button {
                    if topTab == .plugins {
                        creatingPlugin = HeiNiuPlugin(
                            name: "新插件",
                            summary: "个人插件",
                            scope: .personal
                        )
                    } else {
                        creatingSkill = HeiNiuSkill(
                            name: "新技能",
                            command: "custom",
                            summary: "自定义能力",
                            template: "{{input}}",
                            scope: .personal
                        )
                    }
                } label: {
                    Label(topTab == .plugins ? "添加插件" : "添加技能", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.accent, in: Capsule())
                        .foregroundStyle(.black.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Plugins list

    /// pluginsList。
    private var pluginsList: some View {
        let items = agents.plugins(scope: scope)
        return Group {
            if items.isEmpty {
                emptyCard(
                    title: scope == .builtIn ? "暂无内置插件" : "还没有个人插件",
                    message: scope == .personal ? "添加插件来组织你的技能包。" : "内置插件加载失败时可重启应用。",
                    systemImage: "puzzlepiece.extension",
                    actionTitle: scope == .personal ? "添加插件" : nil,
                    action: scope == .personal ? {
                        creatingPlugin = HeiNiuPlugin(name: "新插件", summary: "个人插件", scope: .personal)
                    } : nil
                )
            } else {
                ForEach(items) { plugin in
                    pluginRow(plugin)
                }
            }
        }
    }

    /// pluginRow
    ///
    /// 执行 `pluginRow` 相关逻辑。
    private func pluginRow(_ plugin: HeiNiuPlugin) -> some View {
        let pluginSkills = agents.skills(inPlugin: plugin)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(plugin.scope == .builtIn ? AppTheme.accentSoft : Color.purple.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "puzzlepiece.extension.fill")
                        .foregroundStyle(plugin.scope == .builtIn ? AppTheme.accent : .purple)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(plugin.name)
                            .font(.headline)
                        StatusBadge(text: plugin.scope.title, style: plugin.scope == .builtIn ? .accent : .neutral)
                        if !plugin.isEnabled {
                            StatusBadge(text: "已禁用", style: .neutral)
                        }
                    }
                    Text(plugin.summary)
                        .font(.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text("v\(plugin.version)")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textTertiary)
                        if !plugin.author.isEmpty {
                            Text("· \(plugin.author)")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        Text("· \(pluginSkills.count) 个技能")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }

                Spacer()

                Toggle("启用", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { on in
                        var p = plugin
                        p.isEnabled = on
                        agents.updatePlugin(p)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)

                Button {
                    editingPlugin = plugin
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                if plugin.scope == .personal {
                    Button(role: .destructive) {
                        pendingDeletePlugin = plugin
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(AppTheme.danger)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 插件内技能只在这里列出
            if !pluginSkills.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("包含技能")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                    ForEach(pluginSkills) { skill in
                        HStack(spacing: 8) {
                            Text(skill.dollar)
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                                .frame(minWidth: 88, alignment: .leading)
                            Text(skill.name)
                                .font(.subheadline.weight(.medium))
                            Text(skill.summary)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textTertiary)
                                .lineLimit(1)
                            Spacer()
                            Button("编辑") {
                                editingSkill = skill
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
        .opacity(plugin.isEnabled ? 1 : 0.6)
    }

    // MARK: - Skills list

    /// skillsList。
    private var skillsList: some View {
        // 归属插件的技能只在「插件」里展示，避免两边重复冲突
        let items = agents.standaloneSkills(scope: scope)
        let hiddenInPlugins = agents.skills(scope: scope).filter { $0.pluginID != nil }.count
        return VStack(alignment: .leading, spacing: 12) {
            if hiddenInPlugins > 0 {
                Text("另有 \(hiddenInPlugins) 个技能归属插件，请到「插件」中查看，避免重复管理。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            if items.isEmpty {
                emptyCard(
                    title: scope == .builtIn ? "暂无独立内置技能" : "还没有个人技能",
                    message: scope == .personal
                        ? "添加独立技能（不归属插件）。聊天中用 $命令 调用。插件内技能请在「插件」管理。"
                        : "内置技能目前都在插件包中，请切换到「插件」查看。",
                    systemImage: "bolt.fill",
                    actionTitle: scope == .personal ? "添加技能" : nil,
                    action: scope == .personal ? {
                        creatingSkill = HeiNiuSkill(
                            name: "新技能",
                            command: "custom",
                            summary: "自定义能力",
                            template: "{{input}}",
                            scope: .personal,
                            pluginID: nil
                        )
                    } : nil
                )
            } else {
                ForEach(items) { skill in
                    skillRow(skill)
                }
            }
        }
    }

    /// skillRow
    ///
    /// 执行 `skillRow` 相关逻辑。
    private func skillRow(_ skill: HeiNiuSkill) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(skill.scope == .builtIn ? AppTheme.accentSoft : Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "bolt.fill")
                    .foregroundStyle(skill.scope == .builtIn ? AppTheme.accent : .orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.headline)
                    Text(skill.dollar)
                        .font(.caption.monospaced())
                        .foregroundStyle(AppTheme.accent)
                    StatusBadge(text: skill.scope.title, style: skill.scope == .builtIn ? .accent : .neutral)
                }
                Text(skill.summary)
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                editingSkill = skill
            } label: {
                Text("编辑")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)

            if skill.scope == .personal {
                Button(role: .destructive) {
                    pendingDeleteSkill = skill
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(AppTheme.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppTheme.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }

    /// emptyCard
    ///
    /// 执行 `emptyCard` 相关逻辑。
    private func emptyCard(
        title: String,
        message: String,
        systemImage: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        StudioCard {
            EmptyStateView(
                title: title,
                message: message,
                systemImage: systemImage,
                actionTitle: actionTitle,
                action: action
            )
            .frame(minHeight: 220)
        }
    }
}

// MARK: - Skill editor

/// SkillEditorSheet
///
/// `SkillEditorSheet` 类型定义。
private struct SkillEditorSheet: View {
    /// 按范围筛选插件
    ///
    /// 按范围筛选插件。
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HeiNiuSkill
    let plugins: [HeiNiuPlugin]
    /// onSave。
    let onSave: (HeiNiuSkill) -> Void

    /// 初始化方法
    ///
    /// 初始化方法。
    init(skill: HeiNiuSkill, plugins: [HeiNiuPlugin], onSave: @escaping (HeiNiuSkill) -> Void) {
        _draft = State(initialValue: skill)
        self.plugins = plugins
        self.onSave = onSave
    }

    /// 是否为系统预置。
    private var isBuiltIn: Bool { draft.scope == .builtIn }

    /// SwiftUI 视图内容。
    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("名称", text: $draft.name)
                    TextField("命令（不含 / 或 $）", text: $draft.command)
                        .disabled(isBuiltIn)
                    TextField("简介", text: $draft.summary)
                    if !isBuiltIn {
                        Picker("归属", selection: $draft.scope) {
                            Text("个人").tag(SkillScope.personal)
                        }
                    } else {
                        LabeledContent("归属", value: "内置")
                    }
                    if BuiltInChatModes.commands.contains(draft.command.lowercased()) {
                        Text("「\(draft.command)」是系统对话模式命令，请换名。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section("插件") {
                    Picker("所属插件", selection: $draft.pluginID) {
                        Text("无（显示在技能列表）").tag(Optional<UUID>.none)
                        ForEach(plugins) { p in
                            Text("\(p.name)（\(p.scope.title)）").tag(Optional(p.id))
                        }
                    }
                    Text(draft.pluginID == nil
                         ? "未归属插件时，会出现在「技能」页。"
                         : "已归属插件时，只在「插件」页展示，避免与技能列表重复。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("模板") {
                    Text("使用 {{input}} 表示用户输入。聊天中用 $命令 调用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $draft.template)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isBuiltIn ? "内置技能" : "编辑技能")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        draft.command = draft.command
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "/$¥"))
                            .lowercased()
                        if draft.command.isEmpty { draft.command = "skill" }
                        if BuiltInChatModes.commands.contains(draft.command) {
                            draft.command = "skill-\(draft.command)"
                        }
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if draft.name.isEmpty { draft.name = "未命名技能" }
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Plugin editor

/// PluginEditorSheet
///
/// `PluginEditorSheet` 类型定义。
private struct PluginEditorSheet: View {
    /// onSave。
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HeiNiuPlugin
    let onSave: (HeiNiuPlugin) -> Void

    /// 初始化方法
    ///
    /// 初始化方法。
    init(plugin: HeiNiuPlugin, onSave: @escaping (HeiNiuPlugin) -> Void) {
        _draft = State(initialValue: plugin)
        self.onSave = onSave
    }

    /// 是否为系统预置。
    private var isBuiltIn: Bool { draft.scope == .builtIn }

    /// SwiftUI 视图内容。
    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("名称", text: $draft.name)
                        .disabled(isBuiltIn)
                    TextField("简介", text: $draft.summary)
                    TextField("版本", text: $draft.version)
                    TextField("作者", text: $draft.author)
                    Toggle("启用", isOn: $draft.isEnabled)
                    LabeledContent("类型", value: draft.scope.title)
                }
                if !draft.skillCommands.isEmpty {
                    Section("包含技能") {
                        ForEach(draft.skillCommands, id: \.self) { cmd in
                            Text("$\(cmd)")
                                .font(.body.monospaced())
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isBuiltIn ? "内置插件" : "编辑插件")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if draft.name.isEmpty { draft.name = "未命名插件" }
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}
