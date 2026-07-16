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
                        .frame(width: 240, alignment: .top)

                    if let item = selectedItem {
                        PromptEditorPanel(itemID: item.id, onSaved: onSaved)
                            .id(item.id)
                            .frame(maxWidth: .infinity, alignment: .top)
                    } else {
                        StudioCard {
                            Text("选择一条提示词")
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
    /// 控制模板编辑器光标插入。
    @State private var templateController = PromptTemplateEditorController()

    /// selectedProvider。
    private var selectedProvider: LLMProvider? {
        settings.provider(id: providerID)
    }

    /// SwiftUI 视图内容。
    var body: some View {
        // 自然高度布局：由设置页外层 ScrollView 滚动；模板框固定高度内部滚
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

            StudioCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("模板")
                            .font(.headline)
                        Spacer()
                        Text("\(template.count) 字")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(AppTheme.textTertiary)
                        Button("恢复模板") {
                            settings.resetPromptTemplate(id: itemID)
                            load()
                            onSaved()
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accent)
                    }

                    // 建议变量：属于模板，点击插入到光标位置
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("建议变量")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                            Text("点击插入到光标处")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        FlowLayout(spacing: 8) {
                            ForEach(category.variableChips, id: \.self) { chip in
                                Button {
                                    insertVariableChip(chip)
                                } label: {
                                    Text(chip)
                                        .font(.caption.monospaced())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(AppTheme.accent)
                                        .background(AppTheme.accentSoft, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .help("插入 \(chip)")
                            }
                        }
                    }

                    // 固定高度：正文只在框内滚，外层设置页仍可整体滚动
                    PromptTemplateNSEditor(text: $template, controller: templateController)
                        .frame(maxWidth: .infinity)
                        .frame(height: 360)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.bgElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.stroke, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    private func insertVariableChip(_ chip: String) {
        templateController.insert(chip) { token in
            // 无焦点时：追加到末尾
            if template.isEmpty {
                template = token
            } else if template.hasSuffix("\n") {
                template += token
            } else {
                template += token
            }
        }
    }

    private func scheduleSave() {
        guard ready else { return }
        debouncer.schedule { save() }
    }

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

// MARK: - Template editor with cursor insertion

/// 持有模板 NSTextView 引用，供变量 chip 插入光标处。
@MainActor
private final class PromptTemplateEditorController {
    weak var textView: NSTextView?

    /// 在当前选区插入文本；若编辑器未就绪则走 fallback。
    func insert(_ token: String, fallback: (String) -> Void) {
        guard let textView, textView.window != nil else {
            fallback(token)
            return
        }
        let range = textView.selectedRange()
        guard textView.shouldChangeText(in: range, replacementString: token) else {
            fallback(token)
            return
        }
        textView.replaceCharacters(in: range, with: token)
        textView.didChangeText()
        let newLocation = min(range.location + (token as NSString).length, textView.string.utf16.count)
        textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        textView.scrollRangeToVisible(NSRange(location: newLocation, length: 0))
        textView.window?.makeFirstResponder(textView)
    }
}

/// 等宽模板编辑器：固定在父容器内滚动，支持光标处插入变量。
private struct PromptTemplateNSEditor: NSViewRepresentable {
    @Binding var text: String
    var controller: PromptTemplateEditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.string = text
        textView.textContainerInset = NSSize(width: 10, height: 10)

        context.coordinator.textView = textView
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        controller.textView = context.coordinator.textView
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            let maxLoc = (text as NSString).length
            let loc = min(selected.location, maxLoc)
            let len = min(selected.length, max(0, maxLoc - loc))
            textView.setSelectedRange(NSRange(location: loc, length: len))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptTemplateNSEditor
        weak var textView: NSTextView?

        init(_ parent: PromptTemplateNSEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }
    }
}
