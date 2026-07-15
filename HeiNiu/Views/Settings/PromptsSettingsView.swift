/// 多分类提示词库管理界面。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// PromptsSettingsView
///
/// `PromptsSettingsView` 类型定义。
struct PromptsSettingsView: View {
    /// onSaved。
    @Environment(SettingsStore.self) private var settings
    var onSaved: () -> Void = {}

    @State private var selectedCategory: PromptCategory = .script
    @State private var selectedID: UUID?
    @State private var pendingDelete: PromptItem?

    /// items。
    private var items: [PromptItem] {
        settings.prompts(in: selectedCategory)
    }

    /// selectedItem。
    private var selectedItem: PromptItem? {
        if let selectedID, let item = settings.promptItem(id: selectedID), item.category == selectedCategory {
            return item
        }
        return items.first
    }

    /// SwiftUI 视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            categoryChips

            if items.isEmpty {
                StudioCard {
                    EmptyStateView(
                        title: "「\(selectedCategory.displayName)」还没有提示词",
                        message: "每个创作环节可以有多条提示词，例如大纲、对白润色、分镜表、角色立绘…",
                        systemImage: selectedCategory.systemImage,
                        actionTitle: "新建提示词",
                        action: addPrompt
                    )
                    .frame(minHeight: 260)
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    promptList
                        .frame(width: 240)

                    if let item = selectedItem {
                        PromptEditorPanel(itemID: item.id, onSaved: onSaved)
                            .id(item.id)
                    } else {
                        StudioCard {
                            Text("选择一条提示词")
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: 200)
                        }
                    }
                }
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            selectedID = items.first?.id
        }
        .onAppear {
            if selectedID == nil {
                selectedID = items.first?.id
            }
        }
        .confirmationDialog(
            "删除提示词「\(pendingDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = pendingDelete?.id {
                    settings.deletePrompt(id: id)
                    if selectedID == id {
                        selectedID = settings.prompts(in: selectedCategory).first?.id
                    }
                    onSaved()
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text(pendingDelete?.isBuiltIn == true
                 ? "这是预置提示词，删除后可在需要时再新建。"
                 : "删除后不可恢复。")
        }
    }

    /// header。
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("提示词库")
                    .font(.title3.weight(.semibold))
                Text("按创作环节管理多条提示词；生图/生视频的文案也在这里配置")
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            Button(action: addPrompt) {
                Label("新建", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.accent, in: Capsule())
                    .foregroundStyle(.black.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
    }

    /// categoryChips。
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PromptCategory.allCases) { category in
                    let selected = selectedCategory == category
                    let count = settings.count(in: category)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category.systemImage)
                                .font(.caption)
                            Text(category.displayName)
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                            Text("\(count)")
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(selected ? AppTheme.accent.opacity(0.22) : AppTheme.bgElevated)
                                )
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
        }
    }

    /// promptList。
    private var promptList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedCategory.subtitle)
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.horizontal, 4)

            VStack(spacing: 6) {
                ForEach(items) { item in
                    PromptListRow(
                        item: item,
                        isSelected: selectedItem?.id == item.id,
                        onSelect: {
                            selectedID = item.id
                        },
                        onDuplicate: {
                            if let copy = settings.duplicatePrompt(id: item.id) {
                                selectedID = copy.id
                            }
                            onSaved()
                        },
                        onDelete: {
                            pendingDelete = item
                        }
                    )
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }

    /// addPrompt
    ///
    /// 执行 `addPrompt` 相关逻辑。
    private func addPrompt() {
        let item = settings.addPrompt(in: selectedCategory)
        selectedID = item.id
        onSaved()
    }
}

// MARK: - List row

/// PromptListRow
///
/// `PromptListRow` 类型定义。
private struct PromptListRow: View {
    /// item。
    let item: PromptItem
    /// isSelected。
    let isSelected: Bool
    /// onSelect。
    let onSelect: () -> Void
    /// onDuplicate。
    let onDuplicate: () -> Void
    /// onDelete。
    let onDelete: () -> Void

    /// SwiftUI 视图内容。
    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        if item.isBuiltIn {
                            Text("预置")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(AppTheme.accentSoft, in: Capsule())
                        }
                    }
                    Text(item.model.isEmpty ? "未绑定模型" : item.model)
                        .font(.caption2.monospaced())
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? AppTheme.accentSoft : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? AppTheme.accent.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Menu {
                Button("复制", action: onDuplicate)
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
        }
    }
}

// MARK: - Editor

/// PromptEditorPanel
///
/// `PromptEditorPanel` 类型定义。
private struct PromptEditorPanel: View {
    /// itemID。
    @Environment(SettingsStore.self) private var settings
    let itemID: UUID
    /// onSaved。
    let onSaved: () -> Void

    @State private var name: String = ""
    @State private var template: String = ""
    @State private var providerID: UUID?
    @State private var model: String = ""
    @State private var temperature: Double = PromptItem.defaultTemperature
    @State private var category: PromptCategory = .script
    @State private var debouncer = DebouncedAction()
    @State private var ready = false

    /// selectedProvider。
    private var selectedProvider: LLMProvider? {
        settings.provider(id: providerID)
    }

    /// SwiftUI 视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            StudioCard(title: "基本信息") {
                VStack(alignment: .leading, spacing: 14) {
                    StudioTextField(title: "名称", text: $name, placeholder: "例如：对白润色")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("分类")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        Picker("分类", selection: $category) {
                            ForEach(PromptCategory.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }

            StudioCard(title: "模型绑定", subtitle: "可覆盖默认服务商；留空则运行时再选") {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("服务商")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        Picker("服务商", selection: $providerID) {
                            Text("未选择").tag(Optional<UUID>.none)
                            ForEach(settings.providers) { provider in
                                Text(provider.name).tag(Optional(provider.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    if let provider = selectedProvider, !provider.models.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("模型")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                            Picker("模型", selection: $model) {
                                ForEach(provider.models, id: \.self) { item in
                                    Text(item).tag(item)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    } else {
                        StudioTextField(title: "模型 ID", text: $model, placeholder: "手动填写", monospaced: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("温度")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                            Spacer()
                            Text(String(format: "%.2f", temperature))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(AppTheme.accent)
                        }
                        Slider(value: $temperature, in: 0...2, step: 0.05)
                            .tint(AppTheme.accent)
                    }
                }
            }

            StudioCard(title: "建议变量") {
                FlowLayout(spacing: 8) {
                    ForEach(category.variableChips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(AppTheme.accent)
                            .background(AppTheme.accentSoft, in: Capsule())
                    }
                }
            }

            StudioCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("模板")
                            .font(.headline)
                        Spacer()
                        Button("恢复模板") {
                            settings.resetPromptTemplate(id: itemID)
                            load()
                            onSaved()
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accent)
                    }

                    TextEditor(text: $template)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 260)
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
        }
        .onAppear { load() }
        .onChange(of: itemID) { _, _ in load() }
        .onChange(of: name) { _, _ in scheduleSave() }
        .onChange(of: template) { _, _ in scheduleSave() }
        .onChange(of: providerID) { _, newValue in
            if let provider = settings.provider(id: newValue) {
                if model.isEmpty || !provider.models.contains(model) {
                    model = provider.models.first ?? ""
                }
            }
            scheduleSave()
        }
        .onChange(of: model) { _, _ in scheduleSave() }
        .onChange(of: temperature) { _, _ in scheduleSave() }
        .onChange(of: category) { _, _ in scheduleSave() }
    }

    /// 从磁盘加载持久化数据
    ///
    /// 从磁盘加载持久化数据。
    private func load() {
        ready = false
        debouncer.cancel()
        guard let item = settings.promptItem(id: itemID) else { return }
        name = item.name
        template = item.template
        providerID = item.providerID
        model = item.model
        temperature = item.temperature
        category = item.category
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            ready = true
        }
    }

    /// scheduleSave
    ///
    /// 执行 `scheduleSave` 相关逻辑。
    private func scheduleSave() {
        guard ready else { return }
        debouncer.schedule { save() }
    }

    /// 将当前状态写入磁盘
    ///
    /// 将当前状态写入磁盘。
    private func save() {
        guard var item = settings.promptItem(id: itemID) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.name = trimmedName.isEmpty ? "未命名提示词" : trimmedName
        item.template = template
        item.providerID = providerID
        item.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        item.temperature = temperature
        item.category = category
        settings.updatePrompt(item)
        onSaved()
    }
}
