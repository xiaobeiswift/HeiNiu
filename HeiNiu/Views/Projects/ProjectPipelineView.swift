/// 项目创作流水线：左侧步骤栏 + 右侧工作区。
///
/// 剧本步骤支持：
/// - 用户输入框（粘贴 / 手写简报或源文本）
/// - 导入本地文件
/// - 选择设置 → 提示词库中的「剧本」提示词
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 分步流程面板：左栏流程、右栏当前步骤工作区。
struct ProjectPipelineView: View {
    @Environment(ProjectStore.self) private var projects
    @Environment(SettingsStore.self) private var settings
    @Environment(KnowledgeStore.self) private var knowledge

    let project: ProjectItem

    /// 进入详情后懒加载；nil 时只显示骨架，避免首帧卡顿。
    @State private var pipeline: ProjectPipeline?
    @State private var selectedKind: PipelineStepKind = .script
    @State private var isRunning = false
    @State private var banner: String?
    @State private var isBootstrapping = true

    /// 剧本步骤：用户输入 / 源文本。
    @State private var scriptInput: String = ""
    /// 剧本步骤：选中的提示词库条目。
    @State private var selectedScriptPromptID: UUID?
    /// 导入文件名展示。
    @State private var importedFileName: String?
    /// 是否展开提示词模板预览。
    @State private var showPromptPreview = false
    /// 拖放高亮。
    @State private var isDropTargeted = false
    /// 防止路径→正文转换时递归触发 onChange。
    @State private var isResolvingPathInput = false
    /// 结果正文延迟挂载，避免进入项目首帧就布局 8k+ 字。
    @State private var revealOutput = false
    /// 输入草稿防抖落盘。
    @State private var draftSaveDebouncer = DebouncedAction(delayMs: 350)
    /// 避免 bootstrap 回填触发落盘。
    @State private var suppressDraftPersist = false

    init(project: ProjectItem) {
        self.project = project
    }

    private var activePipeline: ProjectPipeline {
        pipeline ?? ProjectPipeline(projectID: project.id)
    }

    private var selectedStep: PipelineStep {
        activePipeline.step(selectedKind)
    }

    private var scriptPrompts: [PromptItem] {
        settings.prompts(in: .script)
    }

    private var selectedScriptPrompt: PromptItem? {
        if let id = selectedScriptPromptID,
           let item = settings.promptItem(id: id),
           item.category == .script {
            return item
        }
        return scriptPrompts.first
    }

    var body: some View {
        HStack(spacing: 0) {
            stepRail
                .frame(width: 200)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(AppTheme.bgSidebar.opacity(0.55))

            Divider().opacity(0.45)

            Group {
                if isBootstrapping {
                    bootstrapPlaceholder
                } else {
                    stepWorkspace
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.bgBase)
        .task(id: project.id) {
            await bootstrap()
        }
        .onDisappear {
            // 返回列表前立刻落盘，避免防抖未触发导致草稿丢失
            if !suppressDraftPersist, !isBootstrapping {
                persistScriptDraft(immediate: true)
            }
        }
        .onChange(of: selectedScriptPromptID) { _, _ in
            showPromptPreview = false
            persistScriptDraft(immediate: true)
        }
        // 拖文件进 TextEditor 时系统常只粘贴绝对路径 → 自动读正文
        .onChange(of: scriptInput) { _, newValue in
            resolvePathOnlyInputIfNeeded(newValue)
            persistScriptDraft(immediate: false)
        }
        .onChange(of: importedFileName) { _, _ in
            persistScriptDraft(immediate: true)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var bootstrapPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("正在打开项目…")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 分帧加载：先出壳，再读 pipeline，再挂结果正文。
    private func bootstrap() async {
        isBootstrapping = true
        suppressDraftPersist = true
        revealOutput = false
        banner = nil
        showPromptPreview = false
        draftSaveDebouncer.cancel()

        // 让出一帧：详情顶栏先画出来
        await Task.yield()

        let loaded = projects.pipeline(for: project.id)
        pipeline = loaded
        selectedKind = loaded.currentKind

        // 恢复离开前的输入 / 提示词 / 导入文件名
        scriptInput = loaded.scriptInput
        importedFileName = loaded.importedFileName
        if let savedPromptID = loaded.selectedScriptPromptID,
           let item = settings.promptItem(id: savedPromptID),
           item.category == .script {
            selectedScriptPromptID = savedPromptID
        } else {
            selectedScriptPromptID = nil
            ensureDefaultScriptPrompt()
        }

        isBootstrapping = false

        // 再让出一帧后再挂大段结果，避免布局与解码抢同一帧
        await Task.yield()
        if loaded.step(selectedKind).hasOutput {
            revealOutput = true
        }
        // 下一拍再允许草稿落盘，避免回填触发写入
        await Task.yield()
        suppressDraftPersist = false
    }

    /// 把当前剧本草稿写回 pipeline（输入防抖，其它立即）。
    private func persistScriptDraft(immediate: Bool) {
        guard !suppressDraftPersist, !isBootstrapping else { return }
        if immediate {
            draftSaveDebouncer.flush {
                self.writeScriptDraftNow()
            }
        } else {
            draftSaveDebouncer.schedule {
                self.writeScriptDraftNow()
            }
        }
    }

    private func writeScriptDraftNow() {
        var pipe = activePipeline
        // 当前 UI 值完整写回，保证离开再进能恢复
        pipe.scriptInput = scriptInput
        pipe.selectedScriptPromptID = selectedScriptPromptID
        pipe.importedFileName = importedFileName
        pipe.updatedAt = Date()
        pipeline = pipe
        projects.savePipeline(pipe)
    }

    // MARK: - Left rail

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("创作流程")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("一步一步推进")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(PipelineStepKind.allCases.enumerated()), id: \.element.id) { index, kind in
                        if index > 0 {
                            Rectangle()
                                .fill(AppTheme.strokeStrong)
                                .frame(width: 1, height: 10)
                                .padding(.leading, 22)
                        }
                        stepRow(kind)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
    }

    private func stepRow(_ kind: PipelineStepKind) -> some View {
        let step = activePipeline.step(kind)
        let selected = selectedKind == kind
        return Button {
            select(kind)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(selected ? AppTheme.accent : AppTheme.bgElevated)
                        .frame(width: 26, height: 26)
                    if step.status == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(selected ? Color.black.opacity(0.8) : AppTheme.success)
                    } else if step.status == .running {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("\(kind.order)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(selected ? Color.black.opacity(0.8) : AppTheme.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.callout.weight(selected ? .semibold : .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text(step.status.title)
                        .font(.caption2)
                        .foregroundStyle(statusColor(step.status))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? AppTheme.accentSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? AppTheme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right workspace

    private var stepWorkspace: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceHeader

            if let err = selectedStep.errorMessage, selectedStep.status == .failed {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(AppTheme.danger)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            if !selectedKind.isTextStep {
                Text("此步依赖生图/生视频接口，当前版本先完成文本链路；可在「设置」里预先配置服务商。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            Divider().opacity(0.4)

            // 中间可滚动：输入区 + 产物，避免撑破顶栏
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if selectedKind == .script {
                        scriptComposer
                    }

                    if selectedStep.hasOutput {
                        if revealOutput {
                            outputSection
                        } else {
                            outputLoadingStub
                        }
                    } else if selectedKind != .script {
                        idlePlaceholder
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else {
                        scriptIdleFooter
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if selectedStep.hasOutput, revealOutput {
                Divider().opacity(0.4)
                outputActions
            }
        }
    }

    private var workspaceHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedKind.title)
                    .font(.title3.weight(.semibold))
                Text(selectedKind.subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer()
            StatusBadge(
                text: selectedStep.status.title,
                style: badgeStyle(selectedStep.status)
            )
            Button {
                Task { await runSelected() }
            } label: {
                HStack(spacing: 6) {
                    if isRunning && selectedStep.status == .running {
                        ProgressView().controlSize(.small)
                    }
                    Text(runButtonTitle)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(canRun ? Color.black.opacity(0.85) : AppTheme.textTertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(canRun ? AppTheme.accent : AppTheme.bgElevated))
            }
            .buttonStyle(.plain)
            .disabled(!canRun || isRunning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Script composer

    private var scriptComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("剧本提示词")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)

                if scriptPrompts.isEmpty {
                    Text("设置 → 提示词库里还没有「剧本」分类条目")
                        .font(.caption)
                        .foregroundStyle(AppTheme.danger)
                        .lineLimit(2)
                } else {
                    Picker("提示词", selection: Binding(
                        get: { selectedScriptPromptID ?? scriptPrompts.first?.id },
                        set: { selectedScriptPromptID = $0 }
                    )) {
                        ForEach(scriptPrompts) { item in
                            Text(item.name).tag(Optional(item.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 240, alignment: .leading)

                    if let p = selectedScriptPrompt {
                        Text(modelHint(for: p))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if selectedScriptPrompt != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showPromptPreview.toggle()
                        }
                    } label: {
                        Label(
                            showPromptPreview ? "收起模板" : "预览模板",
                            systemImage: showPromptPreview ? "chevron.up" : "eye"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.textSecondary)
                }

                Button {
                    importSourceFile()
                } label: {
                    Label("导入文件", systemImage: "doc.badge.plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .help("支持 txt / md 等文本文件")

                if !scriptInput.isEmpty {
                    Button("清空输入") {
                        scriptInput = ""
                        importedFileName = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                }
            }

            if let importedFileName {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                    Text("已导入：\(importedFileName)")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppTheme.textSecondary)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $scriptInput)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 160, idealHeight: 180, maxHeight: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.bgElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isDropTargeted ? AppTheme.accent.opacity(0.7) : AppTheme.stroke,
                                lineWidth: isDropTargeted ? 1.5 : 1
                            )
                    )

                if scriptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("在这里输入创作简报、灵感、对白草稿…\n也可点「导入文件」或把 .md / .txt 拖进来（会自动读取正文）。\n留空则仅用项目名称 / 卖点 / 概要生成。")
                        .font(.callout)
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }

            if showPromptPreview, let prompt = selectedScriptPrompt {
                promptPreviewCard(prompt)
            }
        }
    }

    private func promptPreviewCard(_ prompt: PromptItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
                Text("模板预览 · \(prompt.name)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer(minLength: 0)
                Text("仅预览，不会直接发送")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            ScrollView {
                Text(prompt.template)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.bgBase.opacity(0.55))
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }

    private var scriptIdleFooter: some View {
        Group {
            if let banner {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(bannerColor(for: banner))
            } else {
                Text(idleHint)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedKind.isTextStep ? "text.badge.plus" : "sparkles.rectangle.stack")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(AppTheme.accent.opacity(0.85))
            Text(idleHint)
                .font(.callout)
                .foregroundStyle(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let banner {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(AppTheme.danger)
            }
        }
    }

    private var outputLoadingStub: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("加载生成结果…")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.bgElevated)
        )
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("生成结果")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("\(selectedStep.outputText.count) 字")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppTheme.textTertiary)
            }

            // 用 AppKit 文本视图承载长文：SwiftUI Text 布局/选区对 8k+ 字很重
            PipelineOutputTextView(text: selectedStep.outputText)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 220, idealHeight: 320, maxHeight: 420)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.bgElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.stroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let warning = selectedStep.knowledgeWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            if !selectedStep.knowledgeCitations.isEmpty {
                DisclosureGroup("知识引用（\(selectedStep.knowledgeCitations.count)）") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(selectedStep.knowledgeCitations) { citation in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(citation.documentTitle)
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Text(String(format: "%.1f%%", citation.similarity * 100))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(AppTheme.textTertiary)
                                }
                                Text(citation.chunkText)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(5)
                                    .textSelection(.enabled)
                            }
                            .padding(10)
                            .background(AppTheme.bgCard, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.caption.weight(.medium))
            }
        }
    }

    private var outputActions: some View {
        HStack(spacing: 16) {
            Button("复制结果") {
                copyText(selectedStep.outputText)
                banner = "已复制"
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)

            if selectedKind == .script {
                Button("清空结果") {
                    clearScriptOutput()
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary)
            }

            if let next = nextKind(after: selectedKind) {
                Button("下一步：\(next.title)") {
                    select(next)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            if let banner {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Logic

    private var canRun: Bool {
        if isRunning || isBootstrapping { return false }
        if !selectedKind.isTextStep { return false }
        switch selectedKind {
        case .script:
            return true
        case .segment, .characters, .scenes, .items:
            return activePipeline.step(.script).status == .done
        case .shotPrompts:
            return activePipeline.step(.segment).status == .done
        case .images, .video:
            return false
        }
    }

    private var runButtonTitle: String {
        if isRunning && selectedStep.status == .running { return "生成中…" }
        if selectedStep.status == .done { return "重新生成" }
        if !selectedKind.isTextStep { return "即将支持" }
        return "开始"
    }

    private var idleHint: String {
        switch selectedKind {
        case .script:
            return "可输入创作简报或导入源文本，并选择设置中的「剧本」提示词；留空则仅用项目卖点 / 概要生成。"
        case .segment:
            return "需要先有剧本。将把剧本切成可拍段落。"
        case .characters, .scenes, .items:
            return "基于剧本（与分段，如有）提取结构化设定卡。"
        case .images:
            return "需要人物 / 场景 / 物品卡完成后，再调用生图服务商。"
        case .shotPrompts:
            return "基于分段与资产卡，为每段写提示词并匹配人物场景物品。"
        case .video:
            return "需要段落提示词完成后，再调用生视频服务商。"
        }
    }

    private func modelHint(for prompt: PromptItem) -> String {
        if let pid = prompt.providerID,
           let provider = settings.provider(id: pid),
           !prompt.model.isEmpty {
            return "\(provider.name) · \(prompt.model)"
        }
        return "使用默认服务商模型"
    }

    private func bannerColor(for text: String) -> Color {
        if text.contains("失败") || text.contains("请") || text.contains("错误") {
            return AppTheme.danger
        }
        return AppTheme.textTertiary
    }

    private func ensureDefaultScriptPrompt() {
        if selectedScriptPromptID == nil {
            selectedScriptPromptID = scriptPrompts.first?.id
        } else if let id = selectedScriptPromptID,
                  settings.promptItem(id: id)?.category != .script {
            selectedScriptPromptID = scriptPrompts.first?.id
        }
    }

    private func select(_ kind: PipelineStepKind) {
        guard selectedKind != kind else { return }
        selectedKind = kind
        // 仅更新当前步：内存先改，落盘防抖，避免连点步骤时卡 UI
        var pipe = activePipeline
        pipe.currentKind = kind
        pipeline = pipe
        projects.savePipeline(pipe)
        banner = nil
        revealOutput = pipe.step(kind).hasOutput
        if kind == .script {
            ensureDefaultScriptPrompt()
        } else {
            showPromptPreview = false
        }
    }

    private func clearScriptOutput() {
        var pipe = activePipeline
        pipe.updateStep(.script) {
            $0.status = .idle
            $0.outputText = ""
            $0.errorMessage = nil
            $0.knowledgeCitations = []
            $0.knowledgeWarning = nil
        }
        pipeline = pipe
        projects.savePipeline(pipe)
        banner = nil
        revealOutput = false
    }

    private func runSelected() async {
        banner = nil
        isRunning = true
        defer { isRunning = false }

        // 先轻量切到 running，立刻刷新按钮；不在这里 encode/写盘
        let kind = selectedKind
        revealOutput = false
        pipeline = projects.markPipelineStep(kind, projectID: project.id, status: .running)
        await Task.yield()

        let options: PipelineStepOptions = {
            if kind == .script {
                return PipelineStepOptions(
                    userInput: scriptInput,
                    promptItemID: selectedScriptPromptID ?? selectedScriptPrompt?.id
                )
            }
            return .init()
        }()

        do {
            let next = try await projects.runPipelineStep(
                kind,
                projectID: project.id,
                settings: settings,
                knowledge: knowledge,
                options: options
            )
            // 结果可能很长：先结束 running 态再挂正文，减少同一帧双重重绘
            isRunning = false
            pipeline = next
            banner = "「\(kind.title)」已完成"
            await Task.yield()
            revealOutput = next.step(kind).hasOutput
        } catch {
            isRunning = false
            pipeline = projects.pipeline(for: project.id)
            banner = error.localizedDescription
            revealOutput = activePipeline.step(kind).hasOutput
        }
    }

    private func importSourceFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "导入"
        panel.message = "选择要作为源文本的文件（txt / md 等），将读取文件正文"
        panel.allowedContentTypes = [
            .plainText, .utf8PlainText, .text, .commaSeparatedText,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            UTType(filenameExtension: "srt") ?? .plainText,
            UTType(filenameExtension: "fountain") ?? .plainText,
            UTType(filenameExtension: "rtf") ?? .plainText,
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyImportedFile(url, replaceIfPathOnly: true)
    }

    /// 把本地文件正文写入输入框（不是路径）。
    private func applyImportedFile(_ url: URL, replaceIfPathOnly: Bool) {
        let result = TextExtractor.extractDetailed(from: url, maxCharacters: 100_000)
        let body = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        isResolvingPathInput = true
        defer { isResolvingPathInput = false }

        let current = scriptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentIsThisPath =
            current == url.path
            || current == url.standardizedFileURL.path
            || current == url.absoluteString
            || (TextExtractor.fileURLIfPathOnly(current)?.path == url.path)

        if current.isEmpty || (replaceIfPathOnly && currentIsThisPath) {
            scriptInput = result.text
        } else if currentIsThisPath {
            scriptInput = result.text
        } else {
            scriptInput = scriptInput.trimmingCharacters(in: .whitespacesAndNewlines)
                + "\n\n---\n文件：\(url.lastPathComponent)\n\n"
                + result.text
        }

        importedFileName = url.lastPathComponent
        if result.didExtractContent {
            let chars = body.count
            banner = "已读取「\(url.lastPathComponent)」正文（\(chars) 字）"
        } else {
            banner = result.errorMessage.map { "导入「\(url.lastPathComponent)」：\($0)" }
                ?? "已附加「\(url.lastPathComponent)」，但未能解析正文"
        }
    }

    /// 输入框若只剩一条本地路径，自动读文件正文替换。
    private func resolvePathOnlyInputIfNeeded(_ text: String) {
        guard !isResolvingPathInput else { return }
        guard let url = TextExtractor.fileURLIfPathOnly(text) else { return }
        applyImportedFile(url, replaceIfPathOnly: true)
    }

    @discardableResult
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL? = {
                    if let data = item as? Data {
                        return URL(dataRepresentation: data, relativeTo: nil)
                    }
                    if let url = item as? URL { return url }
                    if let str = item as? String {
                        if str.lowercased().hasPrefix("file://") {
                            return URL(string: str)
                        }
                        return URL(fileURLWithPath: str)
                    }
                    return nil
                }()
                guard let url else { return }
                Task { @MainActor in
                    applyImportedFile(url, replaceIfPathOnly: true)
                }
            }
        }
        return handled
    }

    private func nextKind(after kind: PipelineStepKind) -> PipelineStepKind? {
        let all = PipelineStepKind.allCases
        guard let i = all.firstIndex(of: kind), i + 1 < all.count else { return nil }
        return all[i + 1]
    }

    private func badgeStyle(_ status: PipelineStepStatus) -> StatusBadge.Style {
        switch status {
        case .idle: .neutral
        case .running: .accent
        case .done: .success
        case .failed: .danger
        }
    }

    private func statusColor(_ status: PipelineStepStatus) -> Color {
        switch status {
        case .idle: AppTheme.textTertiary
        case .running: AppTheme.accent
        case .done: AppTheme.success
        case .failed: AppTheme.danger
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Long text host

/// 用 NSTextView 展示流水线长文本结果，避免 SwiftUI `Text` 布局/选区过重。
private struct PipelineOutputTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = NSColor.labelColor
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }
}
