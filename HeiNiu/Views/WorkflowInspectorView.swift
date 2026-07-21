/// 工作流节点配置、完整用法和运行历史检查器。

import AppKit
import AVKit
import SwiftUI

/// 工作流右侧检查器。
struct WorkflowInspectorView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(KnowledgeStore.self) private var knowledge
    @Environment(WorkflowStore.self) private var workflowStore

    let workflow: WorkflowDefinition
    let node: WorkflowNode?
    @Binding var tab: WorkflowInspectorTab
    @Binding var selectedHistoryRunID: UUID?
    let onUpdateNode: (WorkflowNode) -> Void
    let onRunSelectedNode: () -> Void
    let onDeleteRun: (UUID) -> Void
    let onDeleteAllRuns: () -> Void

    private var runs: [WorkflowRun] {
        workflowStore.runsByWorkflowID[workflow.id] ?? []
    }

    private var displayedRun: WorkflowRun? {
        if let selectedHistoryRunID,
           let run = runs.first(where: { $0.id == selectedHistoryRunID }) {
            return run
        }
        if workflowStore.activeRun?.workflowID == workflow.id { return workflowStore.activeRun }
        return runs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("检查器", selection: $tab) {
                ForEach(WorkflowInspectorTab.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider().opacity(0.45)

            switch tab {
            case .configuration:
                if let node {
                    WorkflowNodeConfigurationView(node: node, onUpdate: onUpdateNode)
                        .id(node.id)
                } else {
                    inspectorEmpty("选择一个节点", "可配置节点参数和模型服务。", "slider.horizontal.3")
                }
            case .usage:
                if let node {
                    WorkflowNodeUsageView(node: node)
                        .id(node.id)
                } else {
                    inspectorEmpty("选择一个节点", "节点卡片的问号可直接打开完整用法。", "questionmark.circle")
                }
            case .run:
                WorkflowRunInspectorView(
                    workflow: workflow,
                    node: node,
                    runs: runs,
                    displayedRun: displayedRun,
                    selectedHistoryRunID: $selectedHistoryRunID,
                    onRunSelectedNode: onRunSelectedNode,
                    onDeleteRun: onDeleteRun,
                    onDeleteAllRuns: onDeleteAllRuns
                )
            }
        }
        .background(AppTheme.bgSidebar.opacity(0.45))
    }

    private func inspectorEmpty(_ title: String, _ message: String, _ icon: String) -> some View {
        EmptyStateView(title: title, message: message, systemImage: icon)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Configuration

private struct WorkflowNodeConfigurationView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(KnowledgeStore.self) private var knowledge

    let node: WorkflowNode
    let onUpdate: (WorkflowNode) -> Void

    @State private var draft: WorkflowNode
    @State private var ready = false

    init(node: WorkflowNode, onUpdate: @escaping (WorkflowNode) -> Void) {
        self.node = node
        self.onUpdate = onUpdate
        _draft = State(initialValue: node)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: draft.descriptor.systemImage)
                        .font(.title2)
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.descriptor.title).font(.headline)
                        Text(draft.descriptor.summary)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }

                inspectorSection("显示") {
                    TextField("自定义标题（可选）", text: $draft.configuration.title)
                        .textFieldStyle(.roundedBorder)
                }

                nodeSpecificConfiguration
            }
            .padding(14)
        }
        .onAppear {
            draft = node
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(40))
                ready = true
            }
        }
        .onChange(of: draft) { _, updated in
            guard ready else { return }
            onUpdate(updated)
        }
    }

    @ViewBuilder
    private var nodeSpecificConfiguration: some View {
        switch draft.kind {
        case .runtimeInput:
            inspectorSection("运行参数") {
                TextField("参数名称", text: $draft.configuration.parameterName)
                    .textFieldStyle(.roundedBorder)
                Picker("输入类型", selection: $draft.configuration.runtimeInputType) {
                    ForEach(WorkflowRuntimeInputType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                Toggle("必填", isOn: $draft.configuration.isRequired)
                if draft.configuration.runtimeInputType == .prompt {
                    Picker("提示词分类", selection: $draft.configuration.promptCategory) {
                        ForEach(PromptCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .onChange(of: draft.configuration.promptCategory) { _, category in
                        draft.configuration.promptItemID = nil
                        if let item = settings.prompts(in: category).first {
                            draft.configuration.promptSnapshot = item.template
                        }
                    }
                    Picker("默认提示词", selection: $draft.configuration.promptItemID) {
                        Text("按分类默认").tag(Optional<UUID>.none)
                        ForEach(settings.prompts(in: draft.configuration.promptCategory)) { item in
                            Text(item.name).tag(Optional(item.id))
                        }
                    }
                    .onChange(of: draft.configuration.promptItemID) { _, id in
                        if let item = settings.promptItem(id: id) {
                            draft.configuration.promptSnapshot = item.template
                        }
                    }
                    let resolved = WorkflowValidator.resolvedRuntimePrompt(for: draft, settings: settings)
                    Text(resolved.template)
                        .font(.caption.monospaced())
                        .foregroundStyle(AppTheme.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(8)
                    if resolved.usedSnapshot {
                        Label("默认提示词不可用，运行时将使用节点保存的快照。", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                    }
                    Text("运行工作流时可以为本次运行重新选择，不会修改这里的默认值。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                } else if draft.configuration.runtimeInputType == .knowledgeCollection {
                    Picker("默认知识集合", selection: $draft.configuration.collectionID) {
                        Text("未分类").tag(Optional<UUID>.none)
                        ForEach(knowledge.collections) { collection in
                            Text(collection.name).tag(Optional(collection.id))
                        }
                    }
                    Text("运行工作流时可以为本次运行重新选择，所选集合会从节点输出端口传递。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                } else if draft.configuration.runtimeInputType == .text {
                    labeledEditor("默认值", text: $draft.configuration.text, minHeight: 100)
                } else {
                    Text(draft.configuration.runtimeInputType == .folder
                         ? "每次运行时使用原生选择器选择一个文件夹。"
                         : "每次运行时使用原生文件选择器选择一个\(draft.configuration.runtimeInputType.title)文件。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

        case .promptTemplate:
            inspectorSection("模板来源") {
                Toggle("绑定提示词库", isOn: $draft.configuration.usesPromptLibrary)
                if draft.configuration.usesPromptLibrary {
                    Picker("提示词", selection: $draft.configuration.promptItemID) {
                        Text("请选择").tag(Optional<UUID>.none)
                        ForEach(settings.promptItems.sorted { $0.name < $1.name }) { item in
                            Text("\(item.category.displayName) · \(item.name)").tag(Optional(item.id))
                        }
                    }
                    .onChange(of: draft.configuration.promptItemID) { _, id in
                        if let item = settings.promptItem(id: id) {
                            draft.configuration.promptSnapshot = item.template
                        }
                    }
                    if let item = settings.promptItem(id: draft.configuration.promptItemID) {
                        Text(item.template)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.textSecondary)
                            .textSelection(.enabled)
                            .lineLimit(8)
                    } else {
                        labeledEditor("保存快照", text: $draft.configuration.promptSnapshot, minHeight: 120)
                    }
                } else {
                    labeledEditor("模板正文", text: $draft.configuration.text, minHeight: 180)
                }
                variableSummary
            }

        case .knowledgeSearch:
            inspectorSection("检索范围") {
                Picker("知识集合", selection: $draft.configuration.collectionID) {
                    Text("全部集合").tag(Optional<UUID>.none)
                    ForEach(knowledge.collections) { collection in
                        Text(collection.name).tag(Optional(collection.id))
                    }
                }
                TextField("标签（逗号分隔）", text: tagsBinding)
                    .textFieldStyle(.roundedBorder)
                Stepper("返回 \(draft.configuration.topK) 个片段", value: $draft.configuration.topK, in: 1...20)
                Text("检索使用设置页选定的嵌入服务商与模型。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }

        case .knowledgeImport:
            inspectorSection("模型补充要求") {
                labeledEditor("补充系统要求（可选）", text: $draft.configuration.systemPrompt, minHeight: 80)
                Text("知识整理提示词必须通过左侧输入端口连接；节点配置只保存模型相关要求。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            inspectorSection("视觉模型") {
                llmProviderPicker
                modelPicker(models: selectedLLMProvider?.models ?? [])
                VStack(alignment: .leading, spacing: 6) {
                    Text("温度 \(draft.configuration.temperature, specifier: "%.1f")").font(.caption)
                    Slider(value: $draft.configuration.temperature, in: 0...2, step: 0.1)
                }
                Picker("推理强度", selection: $draft.configuration.reasoningEffort) {
                    ForEach(ReasoningEffort.allCases) { effort in
                        Text(reasoningTitle(effort)).tag(effort)
                    }
                }
                if selectedLLMProvider?.supportsVision == false {
                    Label("当前服务商未开启视觉能力", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.danger)
                }
            }
            inspectorSection("入库规则") {
                TextField("公共标签（逗号分隔）", text: tagsBinding)
                    .textFieldStyle(.roundedBorder)
                Text("知识集合必须通过左侧输入端口连接。模型返回的标签会与公共标签合并；原图会一并复制到知识库。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            inspectorSection("批处理") {
                Stepper("最多处理 \(draft.configuration.maxFiles) 张", value: $draft.configuration.maxFiles, in: 1...500)
                Text("每张图片调用一次视觉模型。已配置嵌入服务时会自动索引；否则资料保持等待索引。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }

        case .llm:
            inspectorSection("模型") {
                llmProviderPicker
                modelPicker(models: selectedLLMProvider?.models ?? [])
                labeledEditor("系统提示（可选）", text: $draft.configuration.systemPrompt, minHeight: 90)
                VStack(alignment: .leading, spacing: 6) {
                    Text("温度 \(draft.configuration.temperature, specifier: "%.1f")").font(.caption)
                    Slider(value: $draft.configuration.temperature, in: 0...2, step: 0.1)
                }
                Picker("推理强度", selection: $draft.configuration.reasoningEffort) {
                    ForEach(ReasoningEffort.allCases) { effort in
                        Text(reasoningTitle(effort)).tag(effort)
                    }
                }
            }

        case .imageGeneration:
            inspectorSection("生图服务") {
                Picker("操作", selection: $draft.configuration.imageOperation) {
                    ForEach(WorkflowImageOperation.allCases) { operation in
                        Text(operation.title).tag(operation)
                    }
                }
                imageProviderPicker
                modelPicker(models: selectedImageProvider?.models ?? [])
                Picker("尺寸", selection: $draft.configuration.mediaSize) {
                    ForEach(selectedImageAdapter?.supportedSizes ?? ImageProvider.availableSizes, id: \.self) { size in
                        Text(size).tag(size)
                    }
                }
                if draft.configuration.imageOperation == .edit {
                    Label("请在画布上连接“原图”；需要局部编辑时再连接“遮罩”。", systemImage: "photo.on.rectangle.angled")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    if let adapter = selectedImageAdapter, !adapter.supportsImageEditing {
                        Label("当前适配器不支持图片编辑", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(AppTheme.danger)
                    }
                }
                adapterStatus(selectedImageAdapter, id: selectedImageProvider?.adapterID)
            }

        case .videoGeneration:
            inspectorSection("生视频服务") {
                videoProviderPicker
                modelPicker(models: selectedVideoProvider?.models ?? [])
                    .onChange(of: draft.configuration.model) { _, _ in applyVideoCapabilityDefaults() }
                if selectedVideoProvider?.kind == .pixmax {
                    Picker("画幅", selection: $draft.configuration.mediaSize) {
                        ForEach(selectedVideoCapability?.aspectRatios ?? VideoProvider.availableAspectRatios, id: \.self) { ratio in
                            Text(ratio).tag(ratio)
                        }
                    }
                    Picker("分辨率", selection: $draft.configuration.videoResolution) {
                        ForEach(selectedVideoCapability?.resolutions ?? ["720P"], id: \.self) { resolution in
                            Text(resolution).tag(resolution)
                        }
                    }
                } else {
                    Picker("尺寸", selection: $draft.configuration.mediaSize) {
                        ForEach(selectedVideoAdapter?.supportedSizes ?? ["720x1280", "1280x720"], id: \.self) { size in
                            Text(size).tag(size)
                        }
                    }
                }
                Picker("时长", selection: $draft.configuration.durationSeconds) {
                    ForEach(selectedVideoCapability?.durations ?? selectedVideoAdapter?.supportedDurations ?? [4, 8, 12], id: \.self) { seconds in
                        Text("\(seconds) 秒").tag(seconds)
                    }
                }
                if selectedVideoCapability?.supportsAudioGeneration == true || selectedVideoAdapter?.supportsAudioGeneration == true {
                    Toggle("同时生成音频", isOn: $draft.configuration.includeAudio)
                }
                adapterStatus(selectedVideoAdapter, id: selectedVideoProvider?.adapterID)
            }

        case .condition:
            comparisonConfiguration(title: "分支规则")

        case .loop:
            comparisonConfiguration(title: "停止条件")
            inspectorSection("安全上限") {
                Stepper("最多 \(draft.configuration.maxIterations) 次", value: $draft.configuration.maxIterations, in: 1...20)
                Text("达到上限会输出最后结果，并把本次运行标记为有警告。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }

        case .output:
            inspectorSection("结果行为") {
                Text("文本、图片、视频、音频或文件夹由上游端口决定。运行后可在“运行”标签复制、预览、播放或打开。")
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            }

        case .unsupported:
            inspectorSection("不可用") {
                Label("当前版本没有注册此节点实现", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(AppTheme.danger)
            }
        }
    }

    private var variableSummary: some View {
        let effective = WorkflowValidator.effectiveNode(draft, settings: settings)
        let variables = effective.configuration.templateVariables
        return VStack(alignment: .leading, spacing: 5) {
            Text("变量端口").font(.caption.weight(.semibold))
            Text(variables.isEmpty ? "模板没有变量，将作为固定文本输出。" : variables.map { "{{\($0)}}" }.joined(separator: "  "))
                .font(.caption.monospaced())
                .foregroundStyle(variables.isEmpty ? AppTheme.textTertiary : AppTheme.accent)
        }
    }

    private var selectedLLMProvider: LLMProvider? { settings.provider(id: draft.configuration.providerID) }
    private var selectedImageProvider: ImageProvider? { settings.imageProvider(id: draft.configuration.providerID) }
    private var selectedVideoProvider: VideoProvider? { settings.videoProvider(id: draft.configuration.providerID) }
    private var selectedImageAdapter: MediaAdapterDescriptor? {
        guard let id = selectedImageProvider?.adapterID else { return nil }
        return MediaAdapterRegistry.shared.imageAdapter(id: id)?.descriptor
    }
    private var selectedVideoAdapter: MediaAdapterDescriptor? {
        guard let id = selectedVideoProvider?.adapterID else { return nil }
        return MediaAdapterRegistry.shared.videoAdapter(id: id)?.descriptor
    }
    private var selectedVideoCapability: VideoModelCapability? {
        selectedVideoAdapter?.videoCapability(for: draft.configuration.model)
    }

    private var llmProviderPicker: some View {
        Picker("服务商", selection: $draft.configuration.providerID) {
            Text("请选择").tag(Optional<UUID>.none)
            ForEach(settings.providers) { provider in Text(provider.name).tag(Optional(provider.id)) }
        }
        .onChange(of: draft.configuration.providerID) { _, _ in ensureModel(selectedLLMProvider?.models ?? []) }
    }

    private var imageProviderPicker: some View {
        Picker("服务商", selection: $draft.configuration.providerID) {
            Text("请选择").tag(Optional<UUID>.none)
            ForEach(settings.imageProviders) { provider in Text(provider.name).tag(Optional(provider.id)) }
        }
        .onChange(of: draft.configuration.providerID) { _, _ in
            ensureModel(selectedImageProvider?.models ?? [])
            if let size = selectedImageAdapter?.supportedSizes.first { draft.configuration.mediaSize = size }
        }
    }

    private var videoProviderPicker: some View {
        Picker("服务商", selection: $draft.configuration.providerID) {
            Text("请选择").tag(Optional<UUID>.none)
            ForEach(settings.videoProviders) { provider in Text(provider.name).tag(Optional(provider.id)) }
        }
        .onChange(of: draft.configuration.providerID) { _, _ in
            ensureModel(selectedVideoProvider?.models ?? [])
            applyVideoCapabilityDefaults()
        }
    }

    private func modelPicker(models: [String]) -> some View {
        Picker("模型", selection: $draft.configuration.model) {
            if draft.configuration.model.isEmpty { Text("请选择").tag("") }
            ForEach(models, id: \.self) { model in Text(model).tag(model) }
        }
    }

    private func ensureModel(_ models: [String]) {
        if !models.contains(draft.configuration.model) { draft.configuration.model = models.first ?? "" }
    }

    private func applyVideoCapabilityDefaults() {
        if selectedVideoProvider?.kind == .pixmax, let capability = selectedVideoCapability {
            if !capability.aspectRatios.contains(draft.configuration.mediaSize) {
                draft.configuration.mediaSize = capability.aspectRatios.first ?? "auto"
            }
            if !capability.resolutions.contains(draft.configuration.videoResolution) {
                draft.configuration.videoResolution = capability.resolutions.first ?? ""
            }
            if !capability.durations.contains(draft.configuration.durationSeconds) {
                draft.configuration.durationSeconds = capability.durations.first ?? 4
            }
            if !capability.supportsAudioGeneration { draft.configuration.includeAudio = false }
        } else {
            if draft.configuration.mediaSize.isEmpty || !((selectedVideoAdapter?.supportedSizes ?? []).contains(draft.configuration.mediaSize)) {
                draft.configuration.mediaSize = selectedVideoAdapter?.supportedSizes.first ?? "720x1280"
            }
            if let durations = selectedVideoAdapter?.supportedDurations,
               !durations.isEmpty,
               !durations.contains(draft.configuration.durationSeconds) {
                draft.configuration.durationSeconds = durations[0]
            }
        }
    }

    private func comparisonConfiguration(title: String) -> some View {
        inspectorSection(title) {
            Picker("操作", selection: $draft.configuration.comparison) {
                ForEach(WorkflowComparison.allCases) { comparison in
                    Text(comparison.title).tag(comparison)
                }
            }
            if draft.configuration.comparison.needsOperand {
                TextField(draft.configuration.comparison == .regex ? "正则表达式" : "比较值", text: $draft.configuration.comparisonValue)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func adapterStatus(_ descriptor: MediaAdapterDescriptor?, id: String?) -> some View {
        Group {
            if let descriptor {
                VStack(alignment: .leading, spacing: 4) {
                    Label(descriptor.displayName, systemImage: "puzzlepiece.extension")
                        .font(.caption.weight(.semibold))
                    Text(descriptor.endpointHint)
                        .font(.caption2.monospaced())
                        .foregroundStyle(AppTheme.textTertiary)
                }
            } else if let id {
                Label("适配器未注册：\(id)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AppTheme.danger)
            }
        }
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: { draft.configuration.tags.joined(separator: ", ") },
            set: { value in
                draft.configuration.tags = value
                    .components(separatedBy: CharacterSet(charactersIn: ",，"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func labeledEditor(_ title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.textSecondary)
            TextEditor(text: text)
                .font(.callout.monospaced())
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: minHeight)
                .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.stroke))
        }
    }

    private func reasoningTitle(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none: "不指定"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}

// MARK: - Usage

private struct WorkflowNodeUsageView: View {
    @Environment(SettingsStore.self) private var settings
    let node: WorkflowNode

    private var effectiveNode: WorkflowNode { WorkflowValidator.effectiveNode(node, settings: settings) }
    private var descriptor: WorkflowNodeDescriptor { effectiveNode.descriptor }
    private var ports: [WorkflowPortDescriptor] { descriptor.ports(for: effectiveNode) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: descriptor.systemImage)
                        .font(.title)
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(descriptor.title).font(.title3.weight(.semibold))
                        Text(descriptor.summary).font(.callout).foregroundStyle(AppTheme.textSecondary)
                    }
                }

                usageSection("适用场景") {
                    Text(descriptor.usage.purpose)
                }

                usageSection("输入端口") {
                    portGuide(direction: .input)
                }

                usageSection("输出端口") {
                    portGuide(direction: .output)
                }

                usageSection("配置步骤") {
                    ForEach(Array(descriptor.usage.setupSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 20, height: 20)
                                .background(AppTheme.accentSoft, in: Circle())
                            Text(step)
                        }
                    }
                }

                usageSection("典型连线") {
                    Text(descriptor.usage.connectionExample)
                        .font(.callout.monospaced())
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 7))
                }

                usageSection("运行结果") { Text(descriptor.usage.resultDescription) }

                if let adapter = mediaAdapterDescriptor {
                    usageSection("当前适配器 · \(adapter.displayName)") {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(adapter.summary)
                            Text(adapter.endpointHint)
                                .font(.caption.monospaced())
                                .foregroundStyle(AppTheme.textTertiary)
                            if !mediaProviderModels.isEmpty {
                                Text("模型：\(mediaProviderModels.joined(separator: "、"))")
                            }
                            if !adapter.supportedSizes.isEmpty {
                                Text("尺寸：\(adapter.supportedSizes.joined(separator: "、"))")
                            }
                            if !adapter.supportedDurations.isEmpty {
                                Text("时长：\(adapter.supportedDurations.map { "\($0)s" }.joined(separator: "、"))")
                            }
                            if node.kind == .imageGeneration {
                                Text("图片编辑：\(adapter.supportsImageEditing ? "支持" : "不支持")")
                                Text("编辑遮罩：\(adapter.supportsMaskImage ? "支持" : "不支持")")
                            } else if node.kind == .videoGeneration {
                                Text("参考图片：\(adapter.supportsReferenceImage ? "支持" : "不支持")")
                            }
                            if !adapter.configurationFields.isEmpty {
                                Divider().opacity(0.4)
                                Text("请求字段").font(.caption.weight(.semibold))
                                ForEach(adapter.configurationFields) { field in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(field.title).font(.caption.weight(.semibold))
                                            Text(field.isRequired ? "必填" : "可选")
                                                .font(.caption2)
                                                .foregroundStyle(field.isRequired ? AppTheme.danger : AppTheme.textTertiary)
                                        }
                                        Text("\(field.help) 示例：\(field.example)")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                }
                            }
                            ForEach(adapter.usageNotes, id: \.self) { Label($0, systemImage: "info.circle") }
                        }
                    }
                } else if let adapterID = unresolvedAdapterID {
                    usageSection("当前适配器") {
                        Label("源码适配器未注册：\(adapterID)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppTheme.danger)
                    }
                }

                usageSection("常见错误") {
                    guideList(descriptor.usage.commonErrors, icon: "exclamationmark.circle", color: AppTheme.danger)
                }

                if !descriptor.usage.warnings.isEmpty {
                    usageSection("费用与副作用") {
                        guideList(descriptor.usage.warnings, icon: "creditcard.trianglebadge.exclamationmark", color: .orange)
                    }
                }
            }
            .font(.callout)
            .padding(14)
        }
    }

    @ViewBuilder
    private func portGuide(direction: WorkflowPortDirection) -> some View {
        let filtered = ports.filter { $0.direction == direction }
        if filtered.isEmpty {
            Text(direction == .input ? "此节点没有输入端口。" : "此节点没有输出端口。")
                .foregroundStyle(AppTheme.textTertiary)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(filtered) { port in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(port.title).font(.callout.weight(.semibold))
                            Text(port.valueType.title)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accentSoft, in: Capsule())
                            if direction == .input {
                                Text(port.isRequired ? "必填" : "可选")
                                    .font(.caption2)
                                    .foregroundStyle(port.isRequired ? AppTheme.danger : AppTheme.textTertiary)
                            }
                        }
                        Text(port.help).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
    }

    private var mediaAdapterDescriptor: MediaAdapterDescriptor? {
        switch node.kind {
        case .imageGeneration:
            guard let provider = settings.imageProvider(id: node.configuration.providerID) else { return nil }
            return MediaAdapterRegistry.shared.imageAdapter(id: provider.adapterID)?.descriptor
        case .videoGeneration:
            guard let provider = settings.videoProvider(id: node.configuration.providerID) else { return nil }
            return MediaAdapterRegistry.shared.videoAdapter(id: provider.adapterID)?.descriptor
        default:
            return nil
        }
    }

    private var unresolvedAdapterID: String? {
        switch node.kind {
        case .imageGeneration:
            guard let provider = settings.imageProvider(id: node.configuration.providerID),
                  MediaAdapterRegistry.shared.imageAdapter(id: provider.adapterID) == nil
            else { return nil }
            return provider.adapterID
        case .videoGeneration:
            guard let provider = settings.videoProvider(id: node.configuration.providerID),
                  MediaAdapterRegistry.shared.videoAdapter(id: provider.adapterID) == nil
            else { return nil }
            return provider.adapterID
        default:
            return nil
        }
    }

    private var mediaProviderModels: [String] {
        switch node.kind {
        case .imageGeneration:
            settings.imageProvider(id: node.configuration.providerID)?.models ?? []
        case .videoGeneration:
            settings.videoProvider(id: node.configuration.providerID)?.models ?? []
        default:
            []
        }
    }

    private func guideList(_ items: [String], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(items, id: \.self) { item in
                Label {
                    Text(item).foregroundStyle(AppTheme.textSecondary)
                } icon: {
                    Image(systemName: icon).foregroundStyle(color)
                }
            }
        }
    }
}

// MARK: - Runs

private struct WorkflowRunInspectorView: View {
    @Environment(WorkflowStore.self) private var store
    @Environment(KnowledgeStore.self) private var knowledge

    let workflow: WorkflowDefinition
    let node: WorkflowNode?
    let runs: [WorkflowRun]
    let displayedRun: WorkflowRun?
    @Binding var selectedHistoryRunID: UUID?
    let onRunSelectedNode: () -> Void
    let onDeleteRun: (UUID) -> Void
    let onDeleteAllRuns: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let node {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.displayTitle).font(.headline)
                            Text("节点运行结果").font(.caption).foregroundStyle(AppTheme.textTertiary)
                        }
                        Spacer()
                        Button("运行节点", action: onRunSelectedNode)
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.accent)
                            .foregroundStyle(.black)
                    }
                    if let nodeRun = displayedRun?.nodeRun(id: node.id) {
                        nodeRunDetail(nodeRun, run: displayedRun!)
                    } else {
                        Text("该节点还没有运行结果。")
                            .font(.callout)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    Divider().opacity(0.45)
                }

                HStack {
                    Text("运行历史").font(.headline)
                    Spacer()
                    if !runs.isEmpty {
                        Button("清空", role: .destructive, action: onDeleteAllRuns)
                            .buttonStyle(.plain)
                            .font(.caption)
                    }
                }
                if runs.isEmpty {
                    Text("运行工作流后，文本结果和媒体文件会完整保存在这里。")
                        .font(.callout)
                        .foregroundStyle(AppTheme.textTertiary)
                } else {
                    VStack(spacing: 7) {
                        ForEach(runs) { run in
                            Button {
                                selectedHistoryRunID = run.id
                            } label: {
                                HStack(spacing: 9) {
                                    Circle().fill(run.status.color).frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(run.targetNodeID == nil ? "整图运行" : "单节点运行")
                                            .font(.callout.weight(.medium))
                                        Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.textTertiary)
                                    }
                                    Spacer()
                                    Text(run.status.title).font(.caption).foregroundStyle(run.status.color)
                                }
                                .padding(9)
                                .background(
                                    selectedHistoryRunID == run.id ? AppTheme.accentSoft : AppTheme.bgElevated,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("删除运行记录", role: .destructive) { onDeleteRun(run.id) }
                            }
                        }
                    }
                }

                if node == nil, let displayedRun {
                    Divider().opacity(0.45)
                    Text("节点状态").font(.headline)
                    ForEach(displayedRun.nodeRuns) { nodeRun in
                        if let item = workflow.nodes.first(where: { $0.id == nodeRun.nodeID }) {
                            HStack {
                                Text(item.displayTitle).lineLimit(1)
                                Spacer()
                                Text(nodeRun.status.title).foregroundStyle(nodeRun.status.color)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func nodeRunDetail(_ nodeRun: WorkflowNodeRun, run: WorkflowRun) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(nodeRun.status.title, systemImage: nodeRun.status == .running ? "hourglass" : "checkmark.circle")
                    .foregroundStyle(nodeRun.status.color)
                Spacer()
                if let iteration = nodeRun.iteration { Text("第 \(iteration) 轮").font(.caption) }
            }
            if let progress = nodeRun.progress {
                ProgressView(value: progress).tint(AppTheme.accent)
            }
            if let message = nodeRun.message {
                Text(message).font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
            ForEach(nodeRun.outputs.keys.sorted(), id: \.self) { key in
                if let value = nodeRun.outputs[key] {
                    outputView(key: key, value: value, run: run)
                }
            }
        }
        .padding(10)
        .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private func outputView(key: String, value: WorkflowValue, run: WorkflowRun) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key).font(.caption2.monospaced()).foregroundStyle(AppTheme.textTertiary)
            switch value {
            case .text(let text):
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .lineLimit(18)
                Button("复制文本") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.link)
            case .knowledgeCollection(let raw):
                if let id = UUID(uuidString: raw),
                   let collection = knowledge.collections.first(where: { $0.id == id }) {
                    Label(collection.name, systemImage: "books.vertical.fill")
                } else if raw.isEmpty {
                    Label("未分类", systemImage: "tray")
                } else {
                    Label("集合已不存在", systemImage: "books.vertical")
                        .foregroundStyle(AppTheme.textTertiary)
                }
            case .image:
                if let url = store.artifactURL(for: value, run: run), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    artifactButtons(url)
                } else {
                    Label("图片文件不存在", systemImage: "photo.badge.exclamationmark")
                        .foregroundStyle(AppTheme.danger)
                }
            case .video:
                if let url = store.artifactURL(for: value, run: run) {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    artifactButtons(url)
                } else {
                    Label("视频文件不存在", systemImage: "video.badge.exclamationmark")
                        .foregroundStyle(AppTheme.danger)
                }
            case .audio:
                if let url = store.artifactURL(for: value, run: run) {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    artifactButtons(url)
                } else {
                    Label("音频文件不存在", systemImage: "waveform.badge.exclamationmark")
                        .foregroundStyle(AppTheme.danger)
                }
            case .folder:
                if let url = store.artifactURL(for: value, run: run) {
                    Label(url.lastPathComponent, systemImage: "folder.fill")
                    artifactButtons(url)
                } else {
                    Label("文件夹不存在", systemImage: "folder.badge.questionmark")
                        .foregroundStyle(AppTheme.danger)
                }
            }
        }
    }

    private func artifactButtons(_ url: URL) -> some View {
        HStack {
            Button("打开") { NSWorkspace.shared.open(url) }
            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        .buttonStyle(.link)
    }
}

// MARK: - Shared inspector layout

private func inspectorSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 9) {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textTertiary)
            .textCase(.uppercase)
        content()
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppTheme.bgCard, in: RoundedRectangle(cornerRadius: 9))
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.stroke))
}

private func usageSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.headline)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private extension WorkflowRunStatus {
    var color: Color {
        switch self {
        case .running: AppTheme.accent
        case .succeeded: AppTheme.success
        case .warning: .orange
        case .failed: AppTheme.danger
        case .cancelled: AppTheme.textSecondary
        }
    }
}
