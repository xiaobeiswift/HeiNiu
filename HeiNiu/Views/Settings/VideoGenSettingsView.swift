/// 生视频服务商配置界面。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// VideoGenSettingsView
///
/// `VideoGenSettingsView` 类型定义。
struct VideoGenSettingsView: View {
    /// onSaved。
    @Environment(SettingsStore.self) private var settings
    var onSaved: () -> Void = {}

    @State private var expandedID: UUID?
    @State private var pendingDelete: VideoProvider?

    /// SwiftUI 视图内容。
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
                        message: "添加 PixMax、OpenAI 兼容或通用 HTTP 视频接口，用于镜头成片。",
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
            Text("对应的 API Key 或 PixMax 登录凭据将从钥匙串移除。")
        }
        .onAppear {
            if expandedID == nil {
                expandedID = settings.videoProviders.first?.id
            }
        }
    }

    /// 添加 LLM 服务商
    ///
    /// 添加 LLM 服务商。
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

/// VideoProviderCard
///
/// `VideoProviderCard` 类型定义。
private struct VideoProviderCard: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PixmaxSessionManager.self) private var pixmaxSessions

    /// 按 ID 查找 LLM 服务商。
    let provider: VideoProvider
    /// isExpanded。
    let isExpanded: Bool
    /// onToggle。
    let onToggle: () -> Void
    /// onDelete。
    let onDelete: () -> Void
    /// onSaved。
    let onSaved: () -> Void

    @State private var draft: VideoProvider
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

    /// hasKey。
    private var hasKey: Bool {
        !settings.videoAPIKey(for: provider.id).isEmpty || !apiKey.isEmpty
    }

    private var isPixmax: Bool { draft.kind == .pixmax || draft.adapterID == VideoProvider.pixmaxAdapterID }

    private var pixmaxStatus: PixmaxSessionStatus {
        pixmaxSessions.states[draft.id] ?? (draft.isEnabled ? .checking : .disabled)
    }

    /// 当前源码适配器公开的能力说明。
    private var adapterDescriptor: MediaAdapterDescriptor? {
        MediaAdapterRegistry.shared.videoAdapter(id: draft.adapterID)?.descriptor
    }

    /// 未注册适配器仍显示为可诊断的旧配置。
    private var adapterDisplayName: String {
        adapterDescriptor?.displayName ?? "未注册适配器"
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
            apiKey = isPixmax ? "" : settings.videoAPIKey(for: provider.id)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                ready = true
            }
        }
        .onChange(of: draft) { _, _ in schedulePersist() }
        .onChange(of: apiKey) { _, _ in schedulePersist() }
        .onChange(of: provider) { _, updated in
            guard updated != draft else { return }
            ready = false
            draft = updated
            apiKey = isPixmax ? "" : settings.videoAPIKey(for: updated.id)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                ready = true
            }
        }
        .task(id: pixmaxStatus) {
            guard isPixmax,
                  case .authenticated = pixmaxStatus,
                  pixmaxSessions.accountOverviews[draft.id] == nil
            else { return }
            await pixmaxSessions.refreshAccountOverview(providerID: draft.id)
        }
    }

    /// header。
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
                    StatusBadge(text: adapterDisplayName, style: .accent, systemImage: "video")
                    StatusBadge(text: "\(draft.models.count) 模型", style: .neutral)
                    StatusBadge(text: draft.defaultAspectRatio, style: .neutral)
                    StatusBadge(text: "\(draft.defaultDurationSeconds)s", style: .neutral)
                    if isPixmax {
                        HStack(spacing: 5) {
                            StatusDot(active: {
                                if case .authenticated = pixmaxStatus { return true }
                                return false
                            }())
                            Text(pixmaxStatus.title)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    } else {
                        HStack(spacing: 5) {
                            StatusDot(active: hasKey)
                            Text(hasKey ? "Key 已配置" : "未配置 Key")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textTertiary)
                        }
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
                StudioTextField(title: "名称", text: $draft.name, placeholder: "例如：Sora / 可灵 / 自定义网关")

                VStack(alignment: .leading, spacing: 8) {
                    Text("源码适配器")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    Picker("源码适配器", selection: $draft.adapterID) {
                        ForEach(MediaAdapterRegistry.shared.videoDescriptors) { descriptor in
                            Text(descriptor.displayName).tag(descriptor.id)
                        }
                        if adapterDescriptor == nil {
                            Text("未注册：\(draft.adapterID)").tag(draft.adapterID)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: draft.adapterID) { _, newValue in
                        guard let descriptor = MediaAdapterRegistry.shared.videoAdapter(id: newValue)?.descriptor else { return }
                        if newValue == VideoProvider.openAIAdapterID {
                            draft.kind = .openAICompatible
                            if draft.baseURL.isEmpty { draft.baseURL = draft.kind.defaultBaseURL }
                            if draft.models.isEmpty { draft.models = draft.kind.defaultModels }
                        }
                        if newValue == VideoProvider.pixmaxAdapterID {
                            draft.kind = .pixmax
                            draft.baseURL = PixmaxSite.international.baseURL
                            draft.models = VideoProvider.pixmaxModels
                            draft.defaultAspectRatio = "16:9"
                            draft.defaultDurationSeconds = 5
                            draft.adapterSettings["enabled"] = draft.adapterSettings["enabled"] ?? "false"
                            draft.adapterSettings["submissionInterval"] = draft.adapterSettings["submissionInterval"] ?? "0"
                        }
                        if !descriptor.supportedDurations.contains(draft.defaultDurationSeconds),
                           let first = descriptor.supportedDurations.first {
                            draft.defaultDurationSeconds = first
                        }
                    }

                    Text(adapterDescriptor?.endpointHint ?? "适配器 \(draft.adapterID) 未在当前版本注册，因此不能执行。")
                        .font(.caption.monospaced())
                        .foregroundStyle(adapterDescriptor == nil ? AppTheme.danger : AppTheme.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("接入")
                if isPixmax {
                    pixmaxConnectionEditor
                } else {
                    StudioTextField(
                        title: "Base URL",
                        text: $draft.baseURL,
                        placeholder: draft.kind == .generic ? "https://your-gateway.example/v1" : draft.kind.defaultBaseURL,
                        monospaced: true
                    )
                    KeyField(title: "API Key", text: $apiKey)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("模型")
                if isPixmax {
                    Text("PixMax 内置目录（只读）")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    FlowLayout(spacing: 7) {
                        ForEach(draft.models, id: \.self) { model in
                            Text(model)
                                .font(.caption.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(AppTheme.bgElevated, in: Capsule())
                                .overlay(Capsule().stroke(AppTheme.stroke))
                        }
                    }
                } else {
                    ModelTagList(models: $draft.models)
                }
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
                    DurationChipSelector(
                        items: adapterDescriptor?.supportedDurations ?? VideoProvider.availableDurations,
                        selection: $draft.defaultDurationSeconds
                    )
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
                .disabled(isTesting || adapterDescriptor == nil || (isPixmax && !draft.isEnabled))
                .help(adapterDescriptor == nil ? "当前源码适配器未注册，不能测试连接" : "使用当前配置测试媒体接口")

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

    private var pixmaxConnectionEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("启用 PixMax 与 60 秒登录心跳", isOn: Binding(
                get: { draft.adapterSettings["enabled"] == "true" },
                set: { enabled in
                    draft.adapterSettings["enabled"] = enabled ? "true" : "false"
                    persist()
                    pixmaxSessions.setEnabled(enabled, providerID: draft.id)
                }
            ))

            Picker("站点", selection: Binding(
                get: { draft.effectiveBaseURL.contains("pixmax.cn") ? PixmaxSite.china : PixmaxSite.international },
                set: { site in
                    if draft.baseURL != site.baseURL {
                        draft.baseURL = site.baseURL
                        draft.adapterSettings["workspaceUUID"] = nil
                        draft.adapterSettings["fileUUID"] = nil
                    }
                }
            )) {
                ForEach(PixmaxSite.allCases) { site in Text(site.title).tag(site) }
            }

            HStack(spacing: 8) {
                Label(pixmaxStatus.title, systemImage: pixmaxStatusIcon)
                    .font(.callout)
                    .foregroundStyle(pixmaxStatusColor)
                Spacer()
                Button(hasKey ? "重新登录" : "登录") {
                    persist()
                    pixmaxSessions.requestLogin(providerID: draft.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .foregroundStyle(.black)
                Button("退出并停用", role: .destructive) {
                    pixmaxSessions.logoutAndDisable(providerID: draft.id)
                    draft = settings.videoProvider(id: draft.id) ?? draft
                }
                .buttonStyle(.bordered)
                .disabled(!hasKey && !draft.isEnabled)
            }

            if case .authenticated = pixmaxStatus {
                pixmaxAccountOverviewCard
            }

            Stepper(
                "提交间隔 \(Int(draft.adapterSettings["submissionInterval"] ?? "0") ?? 0) 秒",
                value: Binding(
                    get: { min(20, max(0, Int(draft.adapterSettings["submissionInterval"] ?? "0") ?? 0)) },
                    set: { draft.adapterSettings["submissionInterval"] = String(min(20, max(0, $0))) }
                ),
                in: 0...20
            )
            Text("上传、审核、画布写入和付费提交按该服务商串行执行。")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)

            let workspace = draft.adapterSettings["workspaceUUID"] ?? ""
            let file = draft.adapterSettings["fileUUID"] ?? ""
            if !workspace.isEmpty, !file.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("画布已就绪")
                        .font(.caption.weight(.semibold))
                    Text("workspace \(workspace) · file \(file)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(AppTheme.textTertiary)
                        .textSelection(.enabled)
                }
            } else {
                Text("登录成功后会自动验证或创建 PERSONAL 项目与画布。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private var pixmaxAccountOverviewCard: some View {
        let overview = pixmaxSessions.accountOverviews[draft.id]
        let isLoading = pixmaxSessions.overviewLoading.contains(draft.id)
        let error = pixmaxSessions.overviewErrors[draft.id]
        let isTeamAccount = draft.adapterSettings["loginMode"] == PixmaxLoginMode.team.rawValue

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    isTeamAccount ? "团队子账号用量" : "账号用量",
                    systemImage: "gauge.with.dots.needle.33percent"
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await pixmaxSessions.refreshAccountOverview(providerID: draft.id) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
            }

            if let overview {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isTeamAccount ? "子账号可用额度" : "可用积分")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                        Text(overview.credit.displayValue(isTeamAccount: isTeamAccount))
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    Spacer()
                    if isTeamAccount, !overview.credit.quotaMode.isEmpty {
                        Text(pixmaxQuotaTitle(overview.credit.quotaMode))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    } else if !overview.credit.userTier.isEmpty {
                        Text(overview.credit.userTier)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }

                Divider().opacity(0.5)

                VStack(alignment: .leading, spacing: 8) {
                    Text("最近生成记录")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    if overview.recentGenerations.isEmpty {
                        Text("该账号暂无生成记录")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    } else {
                        ForEach(overview.recentGenerations) { record in
                            pixmaxGenerationRow(record)
                        }
                    }
                }
            } else if isLoading {
                Text("正在读取积分与生成记录…")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }

    private func pixmaxGenerationRow(_ record: PixmaxGenerationRecord) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.modelName.isEmpty ? "未知模型" : record.modelName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text("\(record.createTimeTitle) · \(record.taskUUID)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Text(record.statusTitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(pixmaxGenerationStatusColor(record.status))
            Text("−\(record.creditCostTitle)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
                .frame(minWidth: 42, alignment: .trailing)
        }
    }

    private func pixmaxQuotaTitle(_ quotaMode: String) -> String {
        switch quotaMode.uppercased() {
        case "UNLIMITED": "不限额"
        case "DAILY": "每日额度"
        case "WEEKLY": "每周额度"
        case "MONTHLY": "每月额度"
        case "FIXED": "固定额度"
        default: quotaMode
        }
    }

    private func pixmaxGenerationStatusColor(_ status: String) -> Color {
        switch status.uppercased() {
        case "COMPLETED", "COMPLETE", "SUCCESS": AppTheme.success
        case "FAILED", "FAIL", "CANCELLED", "CANCELED", "ABORTED": AppTheme.danger
        default: AppTheme.accent
        }
    }

    private var pixmaxStatusIcon: String {
        switch pixmaxStatus {
        case .disabled: "pause.circle"
        case .checking: "arrow.triangle.2.circlepath"
        case .authenticated: "checkmark.shield.fill"
        case .unauthorized: "person.crop.circle.badge.exclamationmark"
        case .networkError: "wifi.exclamationmark"
        }
    }

    private var pixmaxStatusColor: Color {
        switch pixmaxStatus {
        case .authenticated: AppTheme.success
        case .unauthorized: AppTheme.danger
        case .networkError: .orange
        case .disabled, .checking: AppTheme.textSecondary
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
        if cleaned.name.isEmpty { cleaned.name = "未命名生视频服务商" }
        cleaned.baseURL = cleaned.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = cleaned
        settings.updateVideoProvider(cleaned)
        if !isPixmax { settings.setVideoAPIKey(apiKey, for: cleaned.id) }
        pixmaxSessions.reconcile()
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
        let result: SettingsStore.ConnectionTestResult
        if isPixmax {
            let status = await pixmaxSessions.checkNow(providerID: draft.id, automaticPrompt: false)
            switch status {
            case .authenticated(let summary): result = .success("登录有效：\(summary)")
            case .networkError(let message): result = .failure(message)
            case .unauthorized: result = .failure("登录已失效")
            case .disabled: result = .failure("请先启用 PixMax")
            case .checking: result = .failure("仍在检查")
            }
        } else {
            result = await settings.testConnection(for: draft)
        }
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

/// DurationChipSelector
///
/// `DurationChipSelector` 类型定义。
private struct DurationChipSelector: View {
    /// 当前适配器允许的时长。
    let items: [Int]
    @Binding var selection: Int

    /// SwiftUI 视图内容。
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { seconds in
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
