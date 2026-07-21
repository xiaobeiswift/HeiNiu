/// 项目流水线步骤执行器（文本步骤走 LLM；生图/生视频后续接入）。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// 单步运行时的可选覆盖参数。
struct PipelineStepOptions: Sendable {
    /// 用户额外输入 / 源文本（会注入 `{{source}}` / `{{brief}}` 补充）。
    var userInput: String = ""
    /// 指定提示词库条目；`nil` 时按分类取第一条。
    var promptItemID: UUID? = nil

    init(userInput: String = "", promptItemID: UUID? = nil) {
        self.userInput = userInput
        self.promptItemID = promptItemID
    }
}

/// 执行单步流水线。
enum ProjectPipelineRunner {
    /// 运行指定步骤，返回更新后的 pipeline。
    @MainActor
    static func run(
        step kind: PipelineStepKind,
        project: ProjectItem,
        pipeline: ProjectPipeline,
        settings: SettingsStore,
        knowledge: KnowledgeStore,
        options: PipelineStepOptions = .init()
    ) async throws -> ProjectPipeline {
        var pipe = pipeline
        pipe.currentKind = kind

        guard kind.isTextStep else {
            throw PipelineError.notImplemented(kind)
        }

        try validatePrerequisites(kind, pipeline: pipe)

        pipe.updateStep(kind) { step in
            step.status = .running
            step.errorMessage = nil
        }

        do {
            let result = try await runTextStep(
                kind,
                project: project,
                pipeline: pipe,
                settings: settings,
                knowledge: knowledge,
                options: options
            )
            pipe.updateStep(kind) { step in
                step.status = .done
                step.outputText = result.text
                step.errorMessage = nil
                step.knowledgeCitations = result.retrieval.citations
                step.knowledgeWarning = result.retrieval.warning
            }
            return pipe
        } catch {
            pipe.updateStep(kind) { step in
                step.status = .failed
                step.errorMessage = error.localizedDescription
                step.knowledgeCitations = []
                step.knowledgeWarning = nil
            }
            throw PipelineRunError(pipeline: pipe, underlying: error)
        }
    }

    // MARK: - Prerequisites

    @MainActor
    private static func validatePrerequisites(
        _ kind: PipelineStepKind,
        pipeline: ProjectPipeline
    ) throws {
        switch kind {
        case .script:
            return
        case .segment:
            guard pipeline.step(.script).status == .done else {
                throw PipelineError.needPrerequisite(.script)
            }
        case .characters, .scenes, .items:
            guard pipeline.step(.script).status == .done else {
                throw PipelineError.needPrerequisite(.script)
            }
        case .images:
            guard pipeline.extractionComplete else {
                throw PipelineError.needExtraction
            }
        case .shotPrompts:
            guard pipeline.step(.segment).status == .done else {
                throw PipelineError.needPrerequisite(.segment)
            }
        case .video:
            guard pipeline.step(.shotPrompts).status == .done else {
                throw PipelineError.needPrerequisite(.shotPrompts)
            }
        }
    }

    // MARK: - Text LLM

    private struct TextStepResult {
        var text: String
        var retrieval: KnowledgeRetrievalResult
    }

    @MainActor
    private static func runTextStep(
        _ kind: PipelineStepKind,
        project: ProjectItem,
        pipeline: ProjectPipeline,
        settings: SettingsStore,
        knowledge: KnowledgeStore,
        options: PipelineStepOptions
    ) async throws -> TextStepResult {
        let selectedPrompt = resolvePromptItem(kind: kind, settings: settings, preferredID: options.promptItemID)
        let (provider, model, temperature) = try resolveLLM(
            kind: kind,
            settings: settings,
            promptItem: selectedPrompt
        )
        let apiKey = settings.apiKey(for: provider.id)
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        // 模板渲染可能涉及超长 source/template：放到后台，避免卡住「生成中」按钮
        let template = selectedPrompt?.template ?? ""
        let fallback = fallbackTemplate(kind)
        let system = buildSystemPrompt(kind: kind)
        var userPrompt = await Task.detached(priority: .userInitiated) {
            var values = PromptTemplate.context(project: project, pipeline: pipeline)
            let userExtra = options.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !userExtra.isEmpty {
                values["source"] = userExtra
                let existingBrief = values["brief"] ?? ""
                values["brief"] = [existingBrief, "用户补充/源文本：\n\(userExtra)"]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n\n")
            }
            if !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return PromptTemplate.render(template, values: values)
            }
            return PromptTemplate.render(fallback, values: values)
        }.value

        let query = knowledgeQuery(
            kind: kind,
            project: project,
            pipeline: pipeline,
            userInput: options.userInput
        )
        let retrieval = try await knowledge.retrieve(query: query, project: project, settings: settings)
        if !retrieval.context.isEmpty {
            userPrompt += """


            <knowledge_context>
            以下资料仅作为事实、风格和约束参考；若与用户明确要求冲突，以用户要求为准。
            \(retrieval.context)
            </knowledge_context>
            """
        }

        let client = LLMClientFactory.make(for: provider)
        let completion = try await client.complete(
            messages: [
                LLMChatMessage(role: .system, content: system),
                LLMChatMessage(role: .user, content: userPrompt),
            ],
            model: model,
            temperature: temperature,
            reasoningEffort: .none,
            apiKey: apiKey
        )
        let text = completion.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMError.emptyResponse }
        return TextStepResult(text: text, retrieval: retrieval)
    }

    private static func knowledgeQuery(
        kind: PipelineStepKind,
        project: ProjectItem,
        pipeline: ProjectPipeline,
        userInput: String
    ) -> String {
        let upstream: String = {
            switch kind {
            case .script: return userInput
            case .segment, .characters, .scenes, .items: return pipeline.step(.script).outputText
            case .shotPrompts: return pipeline.step(.segment).outputText
            case .images, .video: return ""
            }
        }()
        return [
            kind.title,
            project.name,
            project.logline,
            project.synopsis,
            project.genre,
            project.audience,
            String(upstream.prefix(6_000)),
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    @MainActor
    private static func resolvePromptItem(
        kind: PipelineStepKind,
        settings: SettingsStore,
        preferredID: UUID?
    ) -> PromptItem? {
        let category = promptCategory(for: kind)
        if let preferredID,
           let item = settings.promptItem(id: preferredID),
           item.category == category {
            return item
        }
        return settings.prompts(in: category).first
    }

    @MainActor
    private static func resolveLLM(
        kind: PipelineStepKind,
        settings: SettingsStore,
        promptItem: PromptItem?
    ) throws -> (LLMProvider, String, Double) {
        if let item = promptItem,
           let pid = item.providerID,
           let provider = settings.provider(id: pid),
           !item.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (provider, item.model, item.temperature)
        }
        guard let provider = settings.providers.first else {
            throw LLMError.missingProvider
        }
        let model = provider.models.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !model.isEmpty else { throw LLMError.missingModel }
        return (provider, model, promptItem?.temperature ?? 0.8)
    }

    private static func promptCategory(for kind: PipelineStepKind) -> PromptCategory {
        switch kind {
        case .script: .script
        case .segment: .storyboard
        case .characters: .character
        case .scenes: .scene
        case .items: .item
        case .images: .image
        case .shotPrompts: .video
        case .video: .video
        }
    }

    @MainActor
    private static func buildUserPrompt(
        kind: PipelineStepKind,
        settings: SettingsStore,
        values: [String: String],
        promptItem: PromptItem?
    ) -> String {
        if let template = promptItem?.template,
           !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return PromptTemplate.render(template, values: values)
        }
        let category = promptCategory(for: kind)
        if let template = settings.prompts(in: category).first?.template,
           !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return PromptTemplate.render(template, values: values)
        }
        return PromptTemplate.render(fallbackTemplate(kind), values: values)
    }

    nonisolated private static func buildSystemPrompt(kind: PipelineStepKind) -> String {
        switch kind {
        case .script:
            return "你是竖屏短剧编剧。只输出可拍的剧本正文，不要前言后语。"
        case .segment:
            return "你是短剧分场编辑。把剧本拆成有序段落/场次，结构清晰，只输出分段结果。"
        case .characters:
            return "你是角色设定编辑。从剧本提取人物卡，Markdown 列表，只输出人物卡。"
        case .scenes:
            return "你是场景设定编辑。从剧本提取场景卡，Markdown 列表，只输出场景卡。"
        case .items:
            return "你是道具设定编辑。从剧本提取关键物品/产品卡，Markdown 列表，只输出物品卡。"
        case .shotPrompts:
            return "你是分镜提示词工程师。为每段生成可生图/生视频的提示词，并标注匹配的人物/场景/物品，只输出结果。"
        case .images, .video:
            return ""
        }
    }

    nonisolated private static func fallbackTemplate(_ kind: PipelineStepKind) -> String {
        switch kind {
        case .script:
            return """
            根据以下创作简报与源文本，写一部适合竖屏的短剧完整剧本（可多场）。
            单集目标时长约 {{duration}}。

            创作简报：
            {{brief}}

            用户补充/源文本：
            {{source}}

            要求：
            1. 场次清晰，含对白与动作
            2. 冲突明确、节奏紧
            3. 只输出剧本正文
            """
        case .segment:
            return """
            将下列剧本按可拍段落拆分（建议按场或 15–40 秒一段）。
            每段包含：段号、标题、时长估计、摘要、对应原文要点。

            剧本：
            {{script}}
            """
        case .characters:
            return """
            从剧本中提取全部主要人物。每人包含：姓名、身份、外形、性格、关系、标志动作/台词。

            剧本：
            {{script}}

            分段参考：
            {{segments}}
            """
        case .scenes:
            return """
            从剧本中提取场景。每个场景包含：名称、时间、空间、光影氛围、关键道具、出现人物。

            剧本：
            {{script}}

            分段参考：
            {{segments}}
            """
        case .items:
            return """
            从剧本中提取关键物品/产品/道具。每项包含：名称、外观、剧作功能、出现场次。

            剧本：
            {{script}}

            分段参考：
            {{segments}}
            """
        case .shotPrompts:
            return """
            基于分段结果，为每一段写生图/生视频提示词（中英皆可，推荐中文描述 + 英文关键词）。
            每段格式：
            ## 段号 标题
            - 画面提示词：
            - 运镜/时长：
            - 匹配人物：
            - 匹配场景：
            - 匹配物品：

            分段：
            {{segments}}

            人物卡：
            {{characters}}

            场景卡：
            {{scenes}}

            物品卡：
            {{items}}
            """
        case .images, .video:
            return ""
        }
    }
}

/// 流水线业务错误。
enum PipelineError: LocalizedError {
    case needPrerequisite(PipelineStepKind)
    case needExtraction
    case notImplemented(PipelineStepKind)

    var errorDescription: String? {
        switch self {
        case .needPrerequisite(let k):
            return "请先完成「\(k.title)」"
        case .needExtraction:
            return "请先完成人物、场景、物品提取"
        case .notImplemented(let k):
            return "「\(k.title)」的生成接口尚未接入，请先在设置中配置并等待后续版本"
        }
    }
}

/// 携带已更新 pipeline 的运行失败（用于 UI 落盘 failed 状态）。
struct PipelineRunError: LocalizedError {
    var pipeline: ProjectPipeline
    var underlying: Error

    var errorDescription: String? {
        underlying.localizedDescription
    }
}
