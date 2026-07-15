import SwiftUI

struct ProvidersSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    var onSaved: () -> Void = {}

    @State private var expandedID: UUID?
    @State private var pendingDelete: LLMProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("API 服务商")
                        .font(.title3.weight(.semibold))
                    Text(settings.providers.isEmpty ? "添加后即可在提示词中绑定模型" : "已配置 \(settings.providers.count) 家")
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
                    settings.deleteProvider(id: id)
                    onSaved()
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("API Key 将从钥匙串移除，相关提示词绑定会被清空。")
        }
        .onAppear {
            if expandedID == nil {
                expandedID = settings.providers.first?.id
            }
        }
    }

    private func addProvider() {
        let provider = LLMProvider(name: "新服务商", protocolType: .openAICompatible)
        settings.addProvider(provider)
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedID = provider.id
        }
        onSaved()
    }
}

// MARK: - Card

private struct ProviderCard: View {
    @Environment(SettingsStore.self) private var settings

    let provider: LLMProvider
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onSaved: () -> Void

    @State private var draft: LLMProvider
    @State private var apiKey: String = ""
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testOK: Bool?
    @State private var debouncer = DebouncedAction()
    @State private var ready = false

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

    private var hasKey: Bool {
        !settings.apiKey(for: provider.id).isEmpty || !apiKey.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggle)

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
        .onChange(of: draft) { _, _ in
            schedulePersist()
        }
        .onChange(of: apiKey) { _, _ in
            schedulePersist()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.name.isEmpty ? "未命名服务商" : draft.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    StatusBadge(text: draft.protocolBadgeText, style: .accent)
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
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(AppTheme.cardPadding)
    }

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
                SectionHeader("模型")
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
                .disabled(isTesting)

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

    private func schedulePersist() {
        guard ready else { return }
        debouncer.schedule {
            persist()
        }
    }

    private func persist() {
        var cleaned = draft
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.name.isEmpty { cleaned.name = "未命名服务商" }
        cleaned.baseURL = cleaned.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = cleaned
        settings.updateProvider(cleaned)
        settings.setAPIKey(apiKey, for: cleaned.id)
        onSaved()
    }

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
}
