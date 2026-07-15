/// 生图服务商配置界面。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// ImageGenSettingsView
///
/// `ImageGenSettingsView` 类型定义。
struct ImageGenSettingsView: View {
    /// onSaved。
    @Environment(SettingsStore.self) private var settings
    var onSaved: () -> Void = {}

    @State private var expandedID: UUID?
    @State private var pendingDelete: ImageProvider?

    /// SwiftUI 视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("生图服务商")
                        .font(.title3.weight(.semibold))
                    Text(settings.imageProviders.isEmpty
                         ? "可添加多家生图接口；提示词在「提示词库 → 生图」"
                         : "已配置 \(settings.imageProviders.count) 家")
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

            if settings.imageProviders.isEmpty {
                StudioCard {
                    EmptyStateView(
                        title: "还没有生图服务商",
                        message: "添加 OpenAI Images 兼容接口，用于角色图、场景图等。",
                        systemImage: "photo.artframe",
                        actionTitle: "添加生图服务商",
                        action: addProvider
                    )
                    .frame(minHeight: 260)
                }
            } else {
                ForEach(settings.imageProviders) { provider in
                    ImageProviderCard(
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
            "删除生图服务商「\(pendingDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = pendingDelete?.id {
                    if expandedID == id { expandedID = nil }
                    settings.deleteImageProvider(id: id)
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
                expandedID = settings.imageProviders.first?.id
            }
        }
    }

    /// 添加 LLM 服务商
    ///
    /// 添加 LLM 服务商。
    private func addProvider() {
        let provider = ImageProvider(name: "新的生图服务")
        settings.addImageProvider(provider)
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedID = provider.id
        }
        onSaved()
    }
}

// MARK: - Card

/// ImageProviderCard
///
/// `ImageProviderCard` 类型定义。
private struct ImageProviderCard: View {
    @Environment(SettingsStore.self) private var settings

    /// 按 ID 查找 LLM 服务商。
    let provider: ImageProvider
    /// isExpanded。
    let isExpanded: Bool
    /// onToggle。
    let onToggle: () -> Void
    /// onDelete。
    let onDelete: () -> Void
    /// onSaved。
    let onSaved: () -> Void

    @State private var draft: ImageProvider
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testOK: Bool?
    @State private var debouncer = DebouncedAction()
    @State private var ready = false

    /// 初始化方法
    ///
    /// 初始化方法。
    init(
        provider: ImageProvider,
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
        !settings.imageAPIKey(for: provider.id).isEmpty || !apiKey.isEmpty
    }

    /// SwiftUI 视图内容。
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
            apiKey = settings.imageAPIKey(for: provider.id)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                ready = true
            }
        }
        .onChange(of: draft) { _, _ in schedulePersist() }
        .onChange(of: apiKey) { _, _ in schedulePersist() }
    }

    /// header。
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.name.isEmpty ? "未命名生图服务商" : draft.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    StatusBadge(text: draft.kind.displayName, style: .accent, systemImage: "photo")
                    StatusBadge(text: "\(draft.models.count) 模型", style: .neutral)
                    StatusBadge(text: draft.defaultSize, style: .neutral)
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

    /// editor。
    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("基本信息")
                StudioTextField(title: "名称", text: $draft.name, placeholder: "例如：OpenAI / 第三方网关")

                VStack(alignment: .leading, spacing: 8) {
                    Text("类型")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    HStack(spacing: 8) {
                        StatusBadge(text: draft.kind.displayName, style: .accent)
                        Text(draft.kind.endpointHint)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("接入")
                StudioTextField(title: "Base URL", text: $draft.baseURL, placeholder: draft.kind.defaultBaseURL, monospaced: true)
                KeyField(title: "API Key", text: $apiKey)
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("模型")
                ModelTagList(models: $draft.models)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("默认尺寸")
                ChipSelector(items: ImageProvider.availableSizes, selection: $draft.defaultSize)
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

    /// schedulePersist
    ///
    /// 执行 `schedulePersist` 相关逻辑。
    private func schedulePersist() {
        guard ready else { return }
        debouncer.schedule { persist() }
    }

    /// persist
    ///
    /// 执行 `persist` 相关逻辑。
    private func persist() {
        var cleaned = draft
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.name.isEmpty { cleaned.name = "未命名生图服务商" }
        cleaned.baseURL = cleaned.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = cleaned
        settings.updateImageProvider(cleaned)
        settings.setImageAPIKey(apiKey, for: cleaned.id)
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
}
