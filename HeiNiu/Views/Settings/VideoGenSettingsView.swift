import SwiftUI

struct VideoGenSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    var onSaved: () -> Void = {}

    @State private var expandedID: UUID?
    @State private var pendingDelete: VideoProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("生视频服务商")
                        .font(.title3.weight(.semibold))
                    Text(settings.videoProviders.isEmpty
                         ? "可添加多家视频生成接口；提示词在「提示词库 → 生视频」"
                         : "已配置 \(settings.videoProviders.count) 家")
                        .font(.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Button(action: addProvider) {
                    Label("添加", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.accent, in: Capsule())
                        .foregroundStyle(.black.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            if settings.videoProviders.isEmpty {
                StudioCard {
                    EmptyStateView(
                        title: "还没有生视频服务商",
                        message: "添加 OpenAI 兼容或通用 HTTP 视频接口，用于镜头成片。",
                        systemImage: "video.badge.waveform",
                        actionTitle: "添加生视频服务商",
                        action: addProvider
                    )
                    .frame(minHeight: 260)
                }
            } else {
                ForEach(settings.videoProviders) { provider in
                    VideoProviderCard(
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
            "删除生视频服务商「\(pendingDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = pendingDelete?.id {
                    if expandedID == id { expandedID = nil }
                    settings.deleteVideoProvider(id: id)
                    onSaved()
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("API Key 将从钥匙串移除。")
        }
        .onAppear {
            if expandedID == nil {
                expandedID = settings.videoProviders.first?.id
            }
        }
    }

    private func addProvider() {
        let provider = VideoProvider(name: "新的生视频服务")
        settings.addVideoProvider(provider)
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedID = provider.id
        }
        onSaved()
    }
}

// MARK: - Card

private struct VideoProviderCard: View {
    @Environment(SettingsStore.self) private var settings

    let provider: VideoProvider
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onSaved: () -> Void

    @State private var draft: VideoProvider
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testOK: Bool?
    @State private var debouncer = DebouncedAction()
    @State private var ready = false

    init(
        provider: VideoProvider,
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
        !settings.videoAPIKey(for: provider.id).isEmpty || !apiKey.isEmpty
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
            apiKey = settings.videoAPIKey(for: provider.id)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                ready = true
            }
        }
        .onChange(of: draft) { _, _ in schedulePersist() }
        .onChange(of: apiKey) { _, _ in schedulePersist() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.name.isEmpty ? "未命名生视频服务商" : draft.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    StatusBadge(text: draft.kind.displayName, style: .accent, systemImage: "video")
                    StatusBadge(text: "\(draft.models.count) 模型", style: .neutral)
                    StatusBadge(text: draft.defaultAspectRatio, style: .neutral)
                    StatusBadge(text: "\(draft.defaultDurationSeconds)s", style: .neutral)
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
                StudioTextField(title: "名称", text: $draft.name, placeholder: "例如：Sora / 可灵 / 自定义网关")

                VStack(alignment: .leading, spacing: 8) {
                    Text("协议")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    Picker("协议", selection: $draft.kind) {
                        ForEach(VideoProviderKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: draft.kind) { _, newValue in
                        let defaults = [
                            VideoProviderKind.openAICompatible.defaultBaseURL,
                            VideoProviderKind.generic.defaultBaseURL,
                        ]
                        if draft.baseURL.isEmpty || defaults.contains(draft.baseURL) {
                            draft.baseURL = newValue.defaultBaseURL
                        }
                        if draft.models.isEmpty {
                            draft.models = newValue.defaultModels
                        }
                    }

                    Text(draft.kind.endpointHint)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("接入")
                StudioTextField(
                    title: "Base URL",
                    text: $draft.baseURL,
                    placeholder: draft.kind == .generic ? "https://your-gateway.example/v1" : draft.kind.defaultBaseURL,
                    monospaced: true
                )
                KeyField(title: "API Key", text: $apiKey)
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("模型")
                ModelTagList(models: $draft.models)
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("默认参数")
                VStack(alignment: .leading, spacing: 8) {
                    Text("画幅")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    ChipSelector(items: VideoProvider.availableAspectRatios, selection: $draft.defaultAspectRatio)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("时长（秒）")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    // 用字符串 chip 再映射
                    DurationChipSelector(selection: $draft.defaultDurationSeconds)
                }
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
        debouncer.schedule { persist() }
    }

    private func persist() {
        var cleaned = draft
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.name.isEmpty { cleaned.name = "未命名生视频服务商" }
        cleaned.baseURL = cleaned.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = cleaned
        settings.updateVideoProvider(cleaned)
        settings.setVideoAPIKey(apiKey, for: cleaned.id)
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

private struct DurationChipSelector: View {
    @Binding var selection: Int

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(VideoProvider.availableDurations, id: \.self) { seconds in
                let selected = selection == seconds
                Button {
                    selection = seconds
                } label: {
                    Text("\(seconds)s")
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
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
