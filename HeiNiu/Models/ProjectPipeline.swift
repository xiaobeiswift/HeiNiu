/// 项目创作流水线：分步状态与产物。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// 流水线步骤类型（固定顺序）。
enum PipelineStepKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    /// 生成完整剧本。
    case script
    /// 按集/场/段切分。
    case segment
    /// 提取人物卡。
    case characters
    /// 提取场景卡。
    case scenes
    /// 提取物品卡。
    case items
    /// 生成参考图（人物/场景/物品）。
    case images
    /// 为每段推理提示词并匹配资产。
    case shotPrompts
    /// 生成视频。
    case video

    var id: String { rawValue }

    /// 步骤序号（1-based）。
    var order: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    /// 界面标题。
    nonisolated var title: String {
        switch self {
        case .script: "生成剧本"
        case .segment: "分段拆解"
        case .characters: "提取人物"
        case .scenes: "提取场景"
        case .items: "提取物品"
        case .images: "生成图片"
        case .shotPrompts: "段落提示词"
        case .video: "生成视频"
        }
    }

    /// 简短说明。
    nonisolated var subtitle: String {
        switch self {
        case .script: "根据项目卖点与概要写出可拍剧本"
        case .segment: "按节奏切成场次/段落"
        case .characters: "从剧本抽出角色卡"
        case .scenes: "从剧本抽出场景卡"
        case .items: "从剧本抽出关键物品/道具"
        case .images: "为人物、场景、物品生成参考图"
        case .shotPrompts: "每段推理提示词并匹配资产"
        case .video: "按提示词生成镜头视频"
        }
    }

    /// 是否为文本 LLM 步骤（当前可跑）。
    nonisolated var isTextStep: Bool {
        switch self {
        case .script, .segment, .characters, .scenes, .items, .shotPrompts: true
        case .images, .video: false
        }
    }

    /// 依赖的上一步（nil = 可从项目元数据直接开跑）。
    nonisolated var prerequisite: PipelineStepKind? {
        switch self {
        case .script: nil
        case .segment: .script
        case .characters, .scenes, .items: .segment
        case .images: .items // 人物/场景/物品都完成后更合理；UI 会检查三者
        case .shotPrompts: .images
        case .video: .shotPrompts
        }
    }
}

/// 单步运行状态。
enum PipelineStepStatus: String, Codable, Hashable, Sendable {
    case idle
    case running
    case done
    case failed

    nonisolated var title: String {
        switch self {
        case .idle: "未开始"
        case .running: "进行中"
        case .done: "已完成"
        case .failed: "失败"
        }
    }
}

/// 流水线中的一步。
///
/// 纯值类型，可在后台拼装提示词时安全读取（不受默认 MainActor isolation 限制）。
nonisolated struct PipelineStep: Identifiable, Codable, Hashable, Sendable {
    /// 与 ``kind`` 一致，便于稳定身份。
    var id: PipelineStepKind { kind }
    /// 步骤类型。
    var kind: PipelineStepKind
    /// 状态。
    var status: PipelineStepStatus
    /// 文本产物（剧本、分段、卡片、提示词等）。
    var outputText: String
    /// 失败信息。
    var errorMessage: String?
    /// 本次生成命中的知识来源。
    var knowledgeCitations: [KnowledgeCitation]
    /// 部分资料未就绪等非致命提醒。
    var knowledgeWarning: String?
    /// 最近更新。
    var updatedAt: Date

    init(
        kind: PipelineStepKind,
        status: PipelineStepStatus = .idle,
        outputText: String = "",
        errorMessage: String? = nil,
        knowledgeCitations: [KnowledgeCitation] = [],
        knowledgeWarning: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.kind = kind
        self.status = status
        self.outputText = outputText
        self.errorMessage = errorMessage
        self.knowledgeCitations = knowledgeCitations
        self.knowledgeWarning = knowledgeWarning
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(PipelineStepKind.self, forKey: .kind) ?? .script
        status = try c.decodeIfPresent(PipelineStepStatus.self, forKey: .status) ?? .idle
        outputText = try c.decodeIfPresent(String.self, forKey: .outputText) ?? ""
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        knowledgeCitations = try c.decodeIfPresent([KnowledgeCitation].self, forKey: .knowledgeCitations) ?? []
        knowledgeWarning = try c.decodeIfPresent(String.self, forKey: .knowledgeWarning)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    private enum CodingKeys: String, CodingKey {
        case kind, status, outputText, errorMessage, knowledgeCitations, knowledgeWarning, updatedAt
    }

    var hasOutput: Bool {
        !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 某项目的完整流水线快照。
///
/// 纯值类型，可在后台拼装提示词时安全读取。
nonisolated struct ProjectPipeline: Codable, Hashable, Sendable {
    /// 所属项目。
    var projectID: UUID
    /// 有序步骤（与 `PipelineStepKind.allCases` 对齐）。
    var steps: [PipelineStep]
    /// 当前聚焦步骤。
    var currentKind: PipelineStepKind
    /// 剧本步骤：用户输入 / 源文本草稿（离开项目后应能恢复）。
    var scriptInput: String
    /// 剧本步骤：选中的提示词库条目。
    var selectedScriptPromptID: UUID?
    /// 剧本步骤：最近导入的文件名（仅展示）。
    var importedFileName: String?
    /// 最近更新。
    var updatedAt: Date

    init(projectID: UUID) {
        self.projectID = projectID
        self.steps = PipelineStepKind.allCases.map { PipelineStep(kind: $0) }
        self.currentKind = .script
        self.scriptInput = ""
        self.selectedScriptPromptID = nil
        self.importedFileName = nil
        self.updatedAt = Date()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID) ?? UUID()
        let decoded = try c.decodeIfPresent([PipelineStep].self, forKey: .steps) ?? []
        // 合并缺省步骤，兼容后续新增 kind
        let map = Dictionary(uniqueKeysWithValues: decoded.map { ($0.kind, $0) })
        steps = PipelineStepKind.allCases.map { map[$0] ?? PipelineStep(kind: $0) }
        currentKind = try c.decodeIfPresent(PipelineStepKind.self, forKey: .currentKind) ?? .script
        scriptInput = try c.decodeIfPresent(String.self, forKey: .scriptInput) ?? ""
        selectedScriptPromptID = try c.decodeIfPresent(UUID.self, forKey: .selectedScriptPromptID)
        importedFileName = try c.decodeIfPresent(String.self, forKey: .importedFileName)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    private enum CodingKeys: String, CodingKey {
        case projectID, steps, currentKind, scriptInput, selectedScriptPromptID, importedFileName, updatedAt
    }

    func step(_ kind: PipelineStepKind) -> PipelineStep {
        steps.first(where: { $0.kind == kind }) ?? PipelineStep(kind: kind)
    }

    mutating func updateStep(_ kind: PipelineStepKind, mutate: (inout PipelineStep) -> Void) {
        guard let i = steps.firstIndex(where: { $0.kind == kind }) else { return }
        mutate(&steps[i])
        steps[i].updatedAt = Date()
        updatedAt = Date()
    }

    /// 同步剧本编辑草稿（输入框 / 提示词选择 / 导入文件名）。
    mutating func updateScriptDraft(
        input: String? = nil,
        promptID: UUID? = nil,
        clearPromptID: Bool = false,
        importedFileName: String? = nil,
        clearImportedFileName: Bool = false
    ) {
        if let input {
            scriptInput = input
        }
        if clearPromptID {
            selectedScriptPromptID = nil
        } else if let promptID {
            selectedScriptPromptID = promptID
        }
        if clearImportedFileName {
            self.importedFileName = nil
        } else if let importedFileName {
            self.importedFileName = importedFileName
        }
        updatedAt = Date()
    }

    /// 人物/场景/物品是否都已完成（生图前置）。
    var extractionComplete: Bool {
        step(.characters).status == .done
            && step(.scenes).status == .done
            && step(.items).status == .done
    }
}
