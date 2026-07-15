/// 黑妞角色、会话与消息模型。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation
import SwiftUI

/// 黑妞：可配置的自定义 AI 角色。
///
/// 类似 Gemini Gem / Custom GPT：系统指令、模型绑定、技能白名单、MCP 策略与开场建议。
///
/// ## 设计原则
///
/// - **指令与模型分离**：`instructions` 管人设；`providerID`/`model` 管算力。
/// - **技能白名单**：`enabledSkillIDs` 为空表示全部技能可用。
/// - **MCP 策略**：见 ``mcpMode`` 与 ``enabledMCPServerIDs``。
///
/// ## 示例
///
/// ```swift
/// var agent = HeiNiuAgent(
///     name: "编剧黑妞",
///     instructions: "你是竖屏短剧编剧……",
///     providerID: provider.id,
///     model: "gpt-4o"
/// )
/// agent.enabledSkillIDs = [] // 全部技能
/// agent.mcpMode = .automatic
/// ```
///
/// - SeeAlso: ``HeiNiuAgentStore``, ``AgentMCPMode``, <doc:HeiNiuAgents>
///
struct HeiNiuAgent: Identifiable, Codable, Hashable {
    /// 唯一标识符。
    var id: UUID
    /// 显示名称。
    var name: String
    /// 副标题或说明文案。
    var subtitle: String
    /// 系统指令（人设与行为规则）。
    ///
    /// 会作为 LLM 的 system 消息；与知识库文本一并注入。
    ///
    var instructions: String
    /// 绑定的服务商 ID。
    var providerID: UUID?
    /// 模型 ID。
    var model: String
    /// 采样温度。
    var temperature: Double
    /// 思考等级（推理强度）；`none` 时不向 API 发送该字段。
    var reasoningEffort: ReasoningEffort
    /// 上下文容量上限（字符近似）。
    ///
    /// 仅用于 ``ContextUsageBar`` 占用估算与提示；不代表 API 实际 token 窗口。
    /// 常见量级：20 万 ≈ 旧默认；100 万 / 200 万对应号称长上下文的模型。
    var contextCharacterLimit: Int
    /// SF Symbol 图标名。
    var iconSymbol: String
    /// 强调色相（0...1）。
    var accentHue: Double
    /// 开场建议短语。
    var conversationStarters: [String]
    /// 允许调用的技能 ID 列表。
    ///
    /// - 空数组：不限制（全部可用，仍受插件启用状态约束）
    /// - 非空：仅列表中的技能可在聊天 `$命令` 中解析成功
    ///
    var enabledSkillIDs: [UUID]
    /// 本黑妞的 MCP 使用策略。
    ///
    /// 服务器清单在全局 ``SettingsStore/mcpServers``；此处只选策略。
    ///
    /// - SeeAlso: ``AgentMCPMode``, ``enabledMCPServerIDs``
    ///
    var mcpMode: AgentMCPMode
    /// 手动模式下启用的 MCP 服务器 ID。
    ///
    /// 仅当 ``mcpMode`` 为 ``AgentMCPMode/manual`` 时生效。
    ///
    var enabledMCPServerIDs: [UUID]
    /// 是否为系统预置。
    var isBuiltIn: Bool
    /// 列表排序权重，越小越靠前。
    var sortOrder: Int
    /// 创建时间。
    var createdAt: Date
    /// 最近更新时间。
    var updatedAt: Date

    /// defaultTemperature。
    static let defaultTemperature: Double = 0.8
    /// 默认上下文容量（字符）；与 ``ContextEstimator/defaultLimit`` 对齐。
    static let defaultContextCharacterLimit: Int = ContextEstimator.defaultLimit
    /// 编辑页可选的常用上下文容量（字符）。
    static let contextLimitPresets: [Int] = [
        128_000, 200_000, 256_000, 500_000, 1_000_000, 2_000_000,
    ]
    static let iconChoices = [
        "sparkles", "film.stack", "pencil.and.outline", "person.wave.2",
        "lightbulb", "text.bubble", "star.circle", "theatermasks",
        "camera.filters", "book.closed",
    ]

    /// 初始化方法
    ///
    /// 初始化方法。
    init(
        id: UUID = UUID(),
        name: String,
        subtitle: String = "",
        instructions: String,
        providerID: UUID? = nil,
        model: String = "",
        temperature: Double = HeiNiuAgent.defaultTemperature,
        reasoningEffort: ReasoningEffort = .none,
        contextCharacterLimit: Int = HeiNiuAgent.defaultContextCharacterLimit,
        iconSymbol: String = "sparkles",
        accentHue: Double = 0.08,
        conversationStarters: [String] = [],
        enabledSkillIDs: [UUID] = [],
        mcpMode: AgentMCPMode = .disabled,
        enabledMCPServerIDs: [UUID] = [],
        isBuiltIn: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.instructions = instructions
        self.providerID = providerID
        self.model = model
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
        self.contextCharacterLimit = max(1_000, contextCharacterLimit)
        self.iconSymbol = iconSymbol
        self.accentHue = accentHue
        self.conversationStarters = conversationStarters
        self.enabledSkillIDs = enabledSkillIDs
        self.mcpMode = mcpMode
        self.enabledMCPServerIDs = enabledMCPServerIDs
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 强调色。
    var accentColor: Color {
        Color(hue: accentHue, saturation: 0.72, brightness: 0.92)
    }

    /// 实际发给模型的系统指令。
    ///
    /// 当黑妞开启思考、且当前模型**没有**原生思考输出时，在最前注入隐藏前缀，
    /// 让模型用中文「思考过程」格式写进正文，便于 UI 折叠。
    /// 关闭思考、或模型本身就会吐 reasoning 时，不加这段。
    ///
    /// 编辑页只展示可改的 ``instructions``；隐藏前缀不入库、不可改。
    var effectiveSystemInstructions: String {
        let body = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldInjectThinkingFormatPrefix else { return body }
        let prefix = Self.thinkingFormatInstructionPrefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return prefix }
        if body.hasPrefix(prefix) { return body }
        return prefix + "\n\n" + body
    }

    /// 是否注入「中文思考过程」隐藏前缀。
    ///
    /// 条件：
    /// 1. 思考等级不是 ``ReasoningEffort/none``
    /// 2. 当前 ``model`` **不**具备原生思考/reasoning 输出
    ///
    /// 与是否预置黑妞无关。
    var shouldInjectThinkingFormatPrefix: Bool {
        reasoningEffort != .none && !Self.modelHasNativeReasoningOutput(model)
    }

    /// 判断模型是否自带思考过程输出（有 API reasoning / thinking 字段或内置链）。
    ///
    /// 这类模型开思考时只传 `reasoning_effort` / thinking budget 即可，
    /// 不必再靠提示词演一段「思考过程」。
    ///
    /// 启发式匹配模型 ID；未知模型默认视为**无**原生思考输出（可走提示词格式）。
    static func modelHasNativeReasoningOutput(_ modelID: String) -> Bool {
        let m = modelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !m.isEmpty else { return false }

        // OpenAI o 系列（避免误伤 gpt-4o：要求 o1/o3/o4 作为独立段）
        if m.range(of: #"(^|[^a-z0-9])o[1-4]([-_.]|$)"#, options: .regularExpression) != nil {
            return true
        }
        if m.contains("gpt-5") || m.contains("gpt5") { return true }

        // 明确带原生思考能力的常见命名
        let markers = [
            "deepseek-r1", "deepseek-reasoner",
            "qwq", "qwen-qwq", "qwen3",
            "claude-3-7", "claude-4", "claude-opus-4", "claude-sonnet-4",
            "gemini-2.5", "gemini-3",
            "kimi-k1", "k1.5", "kimi-thinking",
            "doubao-thinking", "doubao-seed-1.6-thinking",
            "minimax-m1", "glm-z1",
            "reasoner", "reasoning", "thinking",
            "-r1", "r1-",
        ]
        return markers.contains { m.contains($0) }
    }

    /// 隐藏系统前缀：在「开思考但模型无原生思考输出」时，用中文格式写思考过程。
    ///
    /// 仅当 ``shouldInjectThinkingFormatPrefix`` 为真时附加。
    ///
    /// - Important: 不写入 `agents.json`，也不在编辑页展示。
    static let thinkingFormatInstructionPrefix = """
    ## 输出格式（系统强制，优先级最高）
    - 每次回答必须先用中文写「思考过程」，再写最终正文。
    - 严格使用下面结构（含分隔线），不要省略标题，不要复读用户原话：

    **思考过程：**
    （用中文写推理：目标、结构取舍、风险与约束；简洁可执行）

    ---

    （这里写最终成稿/答案）

    - 思考与正文必须分开；禁止用英文 “The user said…” / “用户要求：” 复读。
    - 若任务只需简短确认，思考过程可极短，但仍保留上述标题与分隔线。
    """

    /// 初始化方法
    ///
    /// 初始化方法。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名黑妞"
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        providerID = try container.decodeIfPresent(UUID.self, forKey: .providerID)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? Self.defaultTemperature
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort) ?? .none
        let decodedLimit = try container.decodeIfPresent(Int.self, forKey: .contextCharacterLimit) ?? Self.defaultContextCharacterLimit
        contextCharacterLimit = max(1_000, decodedLimit)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol) ?? "sparkles"
        accentHue = try container.decodeIfPresent(Double.self, forKey: .accentHue) ?? 0.08
        conversationStarters = try container.decodeIfPresent([String].self, forKey: .conversationStarters) ?? []
        enabledSkillIDs = try container.decodeIfPresent([UUID].self, forKey: .enabledSkillIDs) ?? []
        mcpMode = try container.decodeIfPresent(AgentMCPMode.self, forKey: .mcpMode) ?? .disabled
        enabledMCPServerIDs = try container.decodeIfPresent([UUID].self, forKey: .enabledMCPServerIDs) ?? []
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 唯一标识符。
        case id, name, subtitle, instructions, providerID, model, temperature, reasoningEffort, contextCharacterLimit
        /// SF Symbol 图标名。
        case iconSymbol, accentHue, conversationStarters, enabledSkillIDs, mcpMode, enabledMCPServerIDs
        /// 是否为系统预置。
        case isBuiltIn, sortOrder, createdAt, updatedAt
    }

    /// 上下文容量的界面文案（如 `20万`、`100万`）。
    var contextLimitDisplayText: String {
        Self.formatContextLimit(contextCharacterLimit)
    }

    /// 把字符上限格式化为中文短文案。
    static func formatContextLimit(_ n: Int) -> String {
        if n >= 10_000 {
            let wan = Double(n) / 10_000
            if wan == floor(wan) {
                return "\(Int(wan))万"
            }
            return String(format: "%.1f万", wan)
        }
        return "\(n)"
    }
}

/// 模型思考 / 推理强度。
///
/// 对支持 reasoning 的模型（如部分 OpenAI Responses / o 系列兼容网关）生效；
/// 选 ``none`` 时不向请求体写入相关字段。
enum ReasoningEffort: String, Codable, CaseIterable, Identifiable, Hashable {
    /// 不发送思考等级（默认）。
    case none
    /// 低强度，更快更省。
    case low
    /// 中等。
    case medium
    /// 高强度，更慢更细。
    case high

    var id: String { rawValue }

    /// 界面文案。
    var displayName: String {
        switch self {
        case .none: "默认"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }

    /// 简短说明。
    var subtitle: String {
        switch self {
        case .none: "不指定思考等级"
        case .low: "更快，适合简单任务"
        case .medium: "平衡速度与质量"
        case .high: "更深推理，更慢"
        }
    }

    /// 写入 API 的 effort 字符串；`none` 为 `nil`。
    var apiValue: String? {
        switch self {
        case .none: nil
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        }
    }
}

/// 黑妞级 MCP 策略。
///
/// - ``disabled``：不使用 MCP
/// - ``automatic``：使用全局已启用服务器
/// - ``manual``：仅 ``enabledMCPServerIDs``
///
/// UI 上以三张卡片呈现（禁用 / 自动 / 手动）。
enum AgentMCPMode: String, Codable, CaseIterable, Identifiable, Hashable {
    /// disabled。
    case disabled
    /// automatic。
    case automatic
    /// manual。
    case manual

    /// 唯一标识符。
    var id: String { rawValue }

    /// 标题。
    var title: String {
        switch self {
        case .disabled: "禁用"
        case .automatic: "自动"
        case .manual: "手动"
        }
    }

    /// 副标题或说明文案。
    var subtitle: String {
        switch self {
        case .disabled: "不使用 MCP 工具"
        case .automatic: "AI 自动发现和使用已启用的 MCP 服务器"
        case .manual: "仅使用下方勾选的 MCP 服务器"
        }
    }
}

/// 单条聊天消息。
///
/// 助手消息可附带 ``reasoning``（思考过程），与最终 ``content`` 分开存、分开展示。
///
/// - SeeAlso: ``HeiNiuConversation``
///
struct ChatTurn: Identifiable, Codable, Hashable {
    /// Role
    ///
    /// `Role` 类型定义。
    enum Role: String, Codable {
        /// user。
        case user
        /// assistant。
        case assistant
        /// system。
        case system
    }

    /// 唯一标识符。
    var id: UUID
    /// 消息角色。
    var role: Role
    /// 消息正文（最终回答）。
    var content: String
    /// 模型思考过程（可选；仅助手消息有意义）。
    ///
    /// 来自 API 的 `reasoning` / `reasoning_content` / `thinking` 等字段，
    /// 或从正文中的 `<think>…</think>` 标签拆出。
    var reasoning: String?
    /// 创建时间。
    var createdAt: Date

    /// 初始化方法
    ///
    /// 初始化方法。
    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        reasoning: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = Self.normalizedOptionalText(reasoning)
        self.createdAt = createdAt
    }

    /// 容错解码：旧会话无 `reasoning` 字段时为 `nil`。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decodeIfPresent(Role.self, forKey: .role) ?? .assistant
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        let rawReasoning: String? = {
            if let s = try? container.decodeIfPresent(String.self, forKey: .reasoning) { return s }
            if let s = try? container.decodeIfPresent(String.self, forKey: .thinking) { return s }
            if let s = try? container.decodeIfPresent(String.self, forKey: .reasoningContent) { return s }
            return nil
        }()
        reasoning = Self.normalizedOptionalText(rawReasoning)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encode(createdAt, forKey: .createdAt)
    }

    /// 是否有可展示的思考过程。
    var hasReasoning: Bool {
        !(reasoning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, reasoning, thinking, reasoningContent, createdAt
    }

    private static func normalizedOptionalText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// 一次黑妞对话会话。
///
/// 包含标题与有序 ``ChatTurn`` 列表，持久化于 `conversations.json`。
///
struct HeiNiuConversation: Identifiable, Codable, Hashable {
    /// 唯一标识符。
    var id: UUID
    /// 所属黑妞 ID。
    var agentID: UUID
    /// 标题。
    var title: String
    /// 会话消息列表。
    var messages: [ChatTurn]
    /// 创建时间。
    var createdAt: Date
    /// 最近更新时间。
    var updatedAt: Date

    /// 初始化方法
    ///
    /// 初始化方法。
    init(
        id: UUID = UUID(),
        agentID: UUID,
        title: String = "新对话",
        messages: [ChatTurn] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.agentID = agentID
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 初始化方法
    ///
    /// 初始化方法。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        agentID = try container.decodeIfPresent(UUID.self, forKey: .agentID) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "新对话"
        messages = try container.decodeIfPresent([ChatTurn].self, forKey: .messages) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 唯一标识符。
        case id, agentID, title, messages, createdAt, updatedAt
    }
}

/// DefaultHeiNiuAgents
///
/// `DefaultHeiNiuAgents` 类型定义。
enum DefaultHeiNiuAgents {
    /// seed
    ///
    /// 执行 `seed` 相关逻辑。
    static func seed() -> [HeiNiuAgent] {
        [
            HeiNiuAgent(
                name: "编剧黑妞",
                subtitle: "短剧大纲、对白与节奏",
                instructions: """
                你是「编剧黑妞」，一位经验丰富的竖屏短剧编剧。

                你的风格：
                - 口语化、抓耳、冲突明确
                - 擅长 1–3 分钟单集结构
                - 对白短、行动强、情绪递进清晰

                工作方式：
                1. 先确认题材、受众与时长
                2. 给出可拍的结构（钩子 → 冲突 → 反转 → 收束）
                3. 需要剧本时按场次输出，含对白与动作提示
                4. 避免空话，直接给可用文本
                """,
                iconSymbol: "pencil.and.outline",
                accentHue: 0.08,
                conversationStarters: [
                    "帮我构思一个都市反转短剧大纲",
                    "把这段剧情改成更抓人的对白",
                    "一集 90 秒，怎么开场最强？",
                ],
                isBuiltIn: true,
                sortOrder: 0
            ),
            HeiNiuAgent(
                name: "分镜黑妞",
                subtitle: "镜头语言与分镜表",
                instructions: """
                你是「分镜黑妞」，短剧分镜导演。

                你会把剧本拆成可执行镜头，每个镜头包含：
                镜号、景别、画面、对白/旁白、运镜、时长。

                原则：
                - 竖屏优先
                - 信息密度高，少水镜
                - 给够美术与拍摄提示
                - 输出清晰 Markdown
                """,
                iconSymbol: "rectangle.split.3x1",
                accentHue: 0.62,
                conversationStarters: [
                    "把这段剧本拆成 12 个镜头",
                    "这个分手戏怎么拍更虐？",
                    "帮我压镜头，总时长控制 60 秒",
                ],
                isBuiltIn: true,
                sortOrder: 1
            ),
            HeiNiuAgent(
                name: "提示词黑妞",
                subtitle: "生图 / 生视频提示词",
                instructions: """
                你是「提示词黑妞」，AI 生图与生视频提示词工程师。

                你输出的提示词应：
                - 主体、动作、镜头、光影、风格齐全
                - 英文为主，必要时保留中文专有名
                - 避免水印、字幕、低质量词
                - 可按镜头编号批量给出
                """,
                iconSymbol: "camera.filters",
                accentHue: 0.78,
                conversationStarters: [
                    "给这个女主做一张立绘提示词",
                    "把分镜转成视频模型提示词",
                    "写一套风格锁定词，保证多镜头一致",
                ],
                isBuiltIn: true,
                sortOrder: 2
            ),
        ]
    }
}
