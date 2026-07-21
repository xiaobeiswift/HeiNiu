/// LLM 服务商列表与编辑卡片。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// ProvidersSettingsView
///
/// `ProvidersSettingsView` 类型定义。
struct ProvidersSettingsView: View {
    /// onSaved。
    @Environment(SettingsStore.self) private var settings
    @Environment(KnowledgeStore.self) private var knowledge
    var onSaved: () -> Void = {}

    @State private var expandedID: UUID?
    @State private var pendingDelete: LLMProvider?
    @State private var embeddingTestMessage: String?
    @State private var testingEmbedding = false
    @State private var rebuildingKnowledge = false

    /// SwiftUI 视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("API 服务商")
                        .font(.title3.weight(.semibold))
                    Text(settings.providers.isEmpty ? "添加后即可设置默认大模型" : "已配置 \(settings.providers.count) 家")
                        .font(.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Button(action: addProvider) {
                    Label("添加服务商", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.accent, in: Capsule())
                        .foregroundStyle(.black.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            defaultLLMCard

            embeddingCard

            if settings.providers.isEmpty {
                StudioCard {
                    EmptyStateView(
                        title: "还没有服务商",
                        message: "添加 OpenAI 兼容或 Anthropic 接口，用于剧本、分镜等任务。",
                        systemImage: "server.rack",
                        actionTitle: "添加第一家服务商",
                        action: addProvider
                    )
                    .frame(minHeight: 280)
                }
            } else {
                ForEach(settings.providers) { provider in
                    ProviderCard(
                        provider: provider,
                        isExpanded: expandedID == provider.id,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedID = expandedID == provider.id ? nil : provider.id
                            }
                        },
                        onDelete: { pendingDelete = provider },
                        onSaved: onSaved
                    )
                }
            }
        }
        .confirmationDialog(
            "删除服务商「\(pendingDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = pendingDelete?.id {
                    if expandedID == id { expandedID = nil }
                    let wasEmbeddingProvider = settings.knowledgeEmbeddingProviderID == id
                    settings.deleteProvider(id: id)
                    if wasEmbeddingProvider { knowledge.markAllPending() }
                    onSaved()
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("API Key 将从钥匙串移除；默认大模型、嵌入配置及相关提示词绑定也会按需清空。")
        }
        // 进入页面默认全部折叠，不自动展开
    }

    /// 添加 LLM 服务商
    ///
    /// 添加 LLM 服务商。
    private func addProvider() {
        let provider = LLMProvider(name: "新服务商", protocolType: .openAICompatible)
        settings.addProvider(provider)
        // 新建后展开，方便立刻填写
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedID = provider.id
        }
        onSaved()
    }

    /// 未单独绑定的提示词和工作流节点共同继承的默认文本/视觉模型。
    private var defaultLLMCard: some View {
        StudioCard(
            title: "默认大模型",
            subtitle: "内置提示词和未单独绑定的 LLM 节点会自动继承；图片知识入库需要服务商支持视觉。"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("服务商")
                        .frame(width: 64, alignment: .leading)
                        .foregroundStyle(AppTheme.textSecondary)
                    Picker("服务商", selection: defaultLLMProviderBinding) {
                        Text("未配置").tag(Optional<UUID>.none)
                        ForEach(settings.providers) { provider in
                            Text(provider.name).tag(Optional(provider.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Text("模型")
                        .frame(width: 64, alignment: .leading)
                        .foregroundStyle(AppTheme.textSecondary)
                    if let provider = settings.provider(id: settings.defaultLLMProviderID),
                       !provider.models.isEmpty {
                        Picker("模型", selection: defaultLLMModelBinding) {
                            if !settings.defaultLLMModel.isEmpty,
                               !provider.models.contains(settings.defaultLLMModel) {
                                Text(settings.defaultLLMModel).tag(settings.defaultLLMModel)
                            }
                            ForEach(provider.models, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("模型 ID", text: defaultLLMModelBinding)
                            .textFieldStyle(.roundedBorder)
                            .disabled(settings.defaultLLMProviderID == nil)
                    }
                }

                if let provider = settings.provider(id: settings.defaultLLMProviderID) {
                    HStack(spacing: 8) {
                        StatusBadge(text: provider.protocolBadgeText, style: .neutral)
                        if provider.supportsVision {
                            StatusBadge(text: "支持视觉", style: .accent, systemImage: "eye")
                        } else {
                            Label("可用于文本任务；运行图片知识入库前需改用支持视觉的服务商。", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                } else {
                    Text(settings.providers.isEmpty ? "请先添加 API 服务商。" : "请选择默认服务商和模型。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
    }

    private var defaultLLMProviderBinding: Binding<UUID?> {
        Binding(
            get: { settings.defaultLLMProviderID },
            set: { providerID in
                let model = settings.provider(id: providerID)?.models.first ?? ""
                settings.setDefaultLLM(providerID: providerID, model: model)
                onSaved()
            }
        )
    }

    private var defaultLLMModelBinding: Binding<String> {
        Binding(
            get: { settings.defaultLLMModel },
            set: { model in
                settings.setDefaultLLM(providerID: settings.defaultLLMProviderID, model: model)
                onSaved()
            }
        )
    }

    private var embeddingCard: some View {
        StudioCard(title: "知识库嵌入模型", subtitle: "支持标准文本向量与豆包多模态向量接口。") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("服务商")
                        .frame(width: 64, alignment: .leading)
                        .foregroundStyle(AppTheme.textSecondary)
                    Picker("服务商", selection: embeddingProviderBinding) {
                        Text("未配置").tag(Optional<UUID>.none)
                        ForEach(settings.providers.filter { $0.protocolType == .openAICompatible }) { provider in
                            Text(provider.name).tag(Optional(provider.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 12) {
                    Text("接口类型")
                        .frame(width: 64, alignment: .leading)
                        .foregroundStyle(AppTheme.textSecondary)
                    Picker("接口类型", selection: embeddingAPIModeBinding) {
                        ForEach(KnowledgeEmbeddingAPIMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .disabled(settings.knowledgeEmbeddingProviderID == nil)
                    Text(settings.knowledgeEmbeddingAPIMode.endpointPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(AppTheme.textTertiary)
                }
                HStack(spacing: 12) {
                    Text("模型 ID")
                        .frame(width: 64, alignment: .leading)
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("例如 text-embedding-3-small", text: embeddingModelBinding)
                        .textFieldStyle(.roundedBorder)
                        .disabled(settings.knowledgeEmbeddingProviderID == nil)
                }
                HStack(spacing: 10) {
                    Button(testingEmbedding ? "测试中…" : "测试嵌入") {
                        Task {
                            testingEmbedding = true
                            defer { testingEmbedding = false }
                            do {
                                let dimension = try await knowledge.testEmbedding(settings: settings)
                                embeddingTestMessage = "连接成功 · \(dimension) 维"
                            } catch {
                                embeddingTestMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(testingEmbedding || settings.knowledgeEmbeddingProviderID == nil || settings.knowledgeEmbeddingModel.isEmpty)

                    Button(rebuildingKnowledge ? "重建中…" : "重建全部索引") {
                        Task {
                            rebuildingKnowledge = true
                            await knowledge.reindexAll(settings: settings)
                            rebuildingKnowledge = false
                        }
                    }
                    .disabled(rebuildingKnowledge || knowledge.documents.isEmpty)

                    if let embeddingTestMessage {
                        Text(embeddingTestMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }
        }
    }

    private var embeddingProviderBinding: Binding<UUID?> {
        Binding(
            get: { settings.knowledgeEmbeddingProviderID },
            set: { providerID in
                settings.setKnowledgeEmbedding(providerID: providerID, model: settings.knowledgeEmbeddingModel)
                knowledge.markAllPending()
                embeddingTestMessage = nil
                onSaved()
            }
        )
    }

    private var embeddingModelBinding: Binding<String> {
        Binding(
            get: { settings.knowledgeEmbeddingModel },
            set: { model in
                settings.setKnowledgeEmbedding(providerID: settings.knowledgeEmbeddingProviderID, model: model)
                knowledge.markAllPending()
                embeddingTestMessage = nil
                onSaved()
            }
        )
    }

    private var embeddingAPIModeBinding: Binding<KnowledgeEmbeddingAPIMode> {
        Binding(
            get: { settings.knowledgeEmbeddingAPIMode },
            set: { apiMode in
                settings.setKnowledgeEmbedding(
                    providerID: settings.knowledgeEmbeddingProviderID,
                    model: settings.knowledgeEmbeddingModel,
                    apiMode: apiMode
                )
                knowledge.markAllPending()
                embeddingTestMessage = nil
                onSaved()
            }
        )
    }

}

// MARK: - Card

/// ProviderCard
///
/// `ProviderCard` 类型定义。
private struct ProviderCard: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(KnowledgeStore.self) private var knowledge

    /// 按 ID 查找 LLM 服务商。
    let provider: LLMProvider
    /// isExpanded。
    let isExpanded: Bool
    /// onToggle。
    let onToggle: () -> Void
    /// onDelete。
    let onDelete: () -> Void
    /// onSaved。
    let onSaved: () -> Void

    @State private var draft: LLMProvider
    @State private var apiKey: String = ""
    @State private var isTesting = false
    @State private var isFetchingModels = false
    @State private var testMessage: String?
    @State private var testOK: Bool?
    @State private var debouncer = DebouncedAction()
    @State private var ready = false

    /// 初始化方法
    ///
    /// 初始化方法。
    init(
        provider: LLMProvider,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        self.provider = provider
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.onDelete = onDelete
        self.onSaved = onSaved
        _draft = State(initialValue: provider)
    }

    /// hasKey。
    private var hasKey: Bool {
        !settings.apiKey(for: provider.id).isEmpty || !apiKey.isEmpty
    }

    /// SwiftUI 视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                Divider().opacity(0.5)
                editor
                    .padding(AppTheme.cardPadding)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(isExpanded ? AppTheme.accent.opacity(0.28) : AppTheme.stroke, lineWidth: 1)
        )
        .onAppear {
            ready = false
            draft = provider
            apiKey = settings.apiKey(for: provider.id)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                ready = true
            }
        }
        .onChange(of: provider) { _, newValue in
            if !isExpanded {
                draft = newValue
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            // 展开时同步一次最新数据与 Key
            if expanded {
                draft = provider
                apiKey = settings.apiKey(for: provider.id)
            }
        }
        .onChange(of: draft) { _, _ in
            schedulePersist()
        }
        .onChange(of: apiKey) { _, _ in
            schedulePersist()
        }
    }

    /// header。
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(draft.name.isEmpty ? "未命名服务商" : draft.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    StatusBadge(text: draft.protocolBadgeText, style: .accent)
                    if settings.defaultLLMProviderID == provider.id {
                        StatusBadge(text: "默认", style: .accent, systemImage: "checkmark.circle")
                    }
                    StatusBadge(text: "\(draft.models.count) 模型", style: .neutral)
                    if draft.supportsVision {
                        StatusBadge(text: "视觉", style: .neutral, systemImage: "eye")
                    }
                    HStack(spacing: 5) {
                        StatusDot(active: hasKey)
                        Text(hasKey ? "Key 已配置" : "未配置 Key")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }

            Spacer()

            Menu {
                Button(isExpanded ? "收起" : "编辑", action: onToggle)
                Divider()
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
        }
        .padding(AppTheme.cardPadding)
    }

    /// editor。
    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("基本信息")
                StudioTextField(title: "名称", text: $draft.name, placeholder: "例如：DeepSeek / 龙猫")

                VStack(alignment: .leading, spacing: 8) {
                    Text("协议")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    Picker("协议", selection: $draft.protocolType) {
                        ForEach(ProviderProtocolType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: draft.protocolType) { _, newValue in
                        let defaults = [
                            ProviderProtocolType.openAICompatible.defaultBaseURL,
                            ProviderProtocolType.anthropic.defaultBaseURL,
                        ]
                        if draft.baseURL.isEmpty || defaults.contains(draft.baseURL) {
                            draft.baseURL = newValue.defaultBaseURL
                        }
                    }
                }

                if draft.protocolType == .openAICompatible {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("接口模式")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        Picker("接口模式", selection: $draft.openAIAPIMode) {
                            ForEach(OpenAICompatibleAPIMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text(draft.openAIAPIMode.endpointHint)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }

                Toggle(isOn: $draft.supportsVision) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("支持视觉")
                        Text("允许在提示词任务中附带图片")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("接入")
                StudioTextField(title: "Base URL", text: $draft.baseURL, placeholder: "https://…", monospaced: true)
                KeyField(title: "API Key", text: $apiKey)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader("模型")
                    Spacer()
                    Button {
                        Task { await fetchModels() }
                    } label: {
                        HStack(spacing: 6) {
                            if isFetchingModels {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(isFetchingModels ? "获取中…" : "获取模型列表")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppTheme.accentSoft, in: Capsule())
                        .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFetchingModels || isTesting)
                    .help("从服务商接口拉取可用模型并合并到列表")
                }
                ModelTagList(models: $draft.models)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await runTest() }
                } label: {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isTesting ? "测试中…" : "测试连接")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.bgElevated, in: Capsule())
                    .overlay(Capsule().stroke(AppTheme.strokeStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isTesting || isFetchingModels)

                if let testMessage {
                    Label(testMessage, systemImage: testOK == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(testOK == true ? AppTheme.success : AppTheme.danger)
                        .lineLimit(2)
                }

                Spacer()
            }
        }
    }

    /// schedulePersist
    ///
    /// 执行 `schedulePersist` 相关逻辑。
    private func schedulePersist() {
        guard ready else { return }
        debouncer.schedule {
            persist()
        }
    }

    /// persist
    ///
    /// 执行 `persist` 相关逻辑。
    private func persist() {
        var cleaned = draft
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.name.isEmpty { cleaned.name = "未命名服务商" }
        cleaned.baseURL = cleaned.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = cleaned
        let embeddingEndpointChanged = settings.knowledgeEmbeddingProviderID == cleaned.id
            && (provider.effectiveBaseURL != cleaned.effectiveBaseURL
                || provider.protocolType != cleaned.protocolType)
        settings.updateProvider(cleaned)
        settings.setAPIKey(apiKey, for: cleaned.id)
        if embeddingEndpointChanged { knowledge.markAllPending() }
        onSaved()
    }

    /// runTest
    ///
    /// 执行 `runTest` 相关逻辑。
    private func runTest() async {
        persist()
        isTesting = true
        testMessage = nil
        testOK = nil
        let result = await settings.testConnection(for: draft)
        isTesting = false
        switch result {
        case .success(let message):
            testMessage = message
            testOK = true
        case .failure(let message):
            testMessage = message
            testOK = false
        }
    }

    /// 从服务商拉取可用模型列表
    ///
    /// 从服务商拉取可用模型列表。
    private func fetchModels() async {
        persist()
        isFetchingModels = true
        testMessage = nil
        testOK = nil
        let result = await settings.fetchModels(for: draft)
        isFetchingModels = false
        switch result {
        case .success(let models, let message):
            // 合并：保留用户已有顺序，追加新模型
            var merged = draft.models
            let existing = Set(merged.map { $0.lowercased() })
            for id in models where !existing.contains(id.lowercased()) {
                merged.append(id)
            }
            draft.models = merged
            persist()
            testMessage = message + (merged.count > models.count
                ? "（已与本地合并，共 \(merged.count) 个）"
                : "（已写入列表）")
            testOK = true
        case .failure(let message):
            testMessage = message
            testOK = false
        }
    }
}
