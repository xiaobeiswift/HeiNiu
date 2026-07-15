/// 知识库、附件、对话模式、技能与插件模型。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// 黑妞知识库条目。
///
/// 发送聊天时，`enabled == true` 的条目会注入 system 上下文。
///
/// - SeeAlso: ``HeiNiuAgentStore/importKnowledge(from:agentID:)``
///
struct KnowledgeItem: Identifiable, Codable, Hashable {
    /// 唯一标识符。
    var id: UUID
    /// 所属黑妞 ID。
    var agentID: UUID
    /// 显示名称。
    var name: String
    /// 相对 agents 知识库目录的文件名，或 inline 文本
    var fileName: String
    /// MIME 提示。
    var mimeHint: String
    /// 字节大小。
    var byteSize: Int
    /// 抽取后的纯文本（用于注入上下文；大文件可截断）
    var extractedText: String
    /// 是否启用该条目。
    var enabled: Bool
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
        name: String,
        fileName: String,
        mimeHint: String = "text/plain",
        byteSize: Int = 0,
        extractedText: String = "",
        enabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.agentID = agentID
        self.name = name
        self.fileName = fileName
        self.mimeHint = mimeHint
        self.byteSize = byteSize
        self.extractedText = extractedText
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 字符数。
    var charCount: Int { extractedText.count }

    /// 初始化方法
    ///
    /// 初始化方法。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        agentID = try c.decodeIfPresent(UUID.self, forKey: .agentID) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "未命名"
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        mimeHint = try c.decodeIfPresent(String.self, forKey: .mimeHint) ?? "text/plain"
        byteSize = try c.decodeIfPresent(Int.self, forKey: .byteSize) ?? 0
        extractedText = try c.decodeIfPresent(String.self, forKey: .extractedText) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 唯一标识符。
        case id, agentID, name, fileName, mimeHint, byteSize, extractedText, enabled, createdAt, updatedAt
    }
}

/// 本轮聊天附件（不进入知识库）。
///
/// UI 仅展示 `name` 文件名 chip；`extractedText` 在发送时并入模型输入。
///
struct ChatAttachment: Identifiable, Codable, Hashable {
    /// 唯一标识符。
    var id: UUID
    /// 仅文件名，不含路径
    var name: String
    /// 抽取后的纯文本。
    var extractedText: String
    /// 字节大小。
    var byteSize: Int
    /// 是否为图片附件。
    var isImage: Bool

    /// 初始化方法
    ///
    /// 初始化方法。
    init(
        id: UUID = UUID(),
        name: String,
        extractedText: String,
        byteSize: Int = 0,
        isImage: Bool = false
    ) {
        self.id = id
        self.name = (name as NSString).lastPathComponent
        self.extractedText = extractedText
        self.byteSize = byteSize
        self.isImage = isImage
    }

    /// 字符数。
    var charCount: Int { extractedText.count }

    /// 用于 UI 的 SF Symbol。
    var systemImage: String {
        if isImage { return "photo" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "md", "markdown", "txt": return "doc.text"
        case "json", "yml", "yaml": return "curlybraces"
        default: return "doc.fill"
        }
    }

    /// 初始化方法
    ///
    /// 初始化方法。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let rawName = try c.decodeIfPresent(String.self, forKey: .name) ?? "file"
        name = (rawName as NSString).lastPathComponent
        extractedText = try c.decodeIfPresent(String.self, forKey: .extractedText) ?? ""
        byteSize = try c.decodeIfPresent(Int.self, forKey: .byteSize) ?? 0
        isImage = try c.decodeIfPresent(Bool.self, forKey: .isImage) ?? false
    }

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 唯一标识符。
        case id, name, extractedText, byteSize, isImage
    }
}

// MARK: - 对话模式（系统内置，不是技能）

/// 聊天工作模式：/goal /plan 等，固定内置，不进技能库
struct ChatMode: Identifiable, Hashable {
    /// 唯一标识符。
    var id: String { command }
    /// 显示名称。
    var name: String
    /// 命令名（不含前缀）。
    var command: String
    /// 简介。
    var summary: String
    /// 模板正文。
    var template: String

    /// 斜杠命令形式，如 /goal。
    var slash: String { "/\(command)" }
}

/// 系统内置对话模式（命令）。
///
/// 提供 `/goal` `/plan` `/ask` `/execute` `/compress`，**不属于技能库**。
///
/// - SeeAlso: ``ChatMode``, ``HeiNiuAgentStore/resolveSlash(_:)``
///
enum BuiltInChatModes {
    /// commands。
    static let commands: Set<String> = ["goal", "plan", "ask", "execute", "compress"]

    /// 返回全部预置项。
    static let all: [ChatMode] = [
        ChatMode(
            name: "目标模式",
            command: "goal",
            summary: "先澄清目标与成功标准，再行动",
            template: """
            【目标模式】
            不要急着给长文案。先做目标对齐：
            1. 用一句话复述你理解的目标
            2. 列出成功标准（可验收）
            3. 标出缺失信息（最多 3 个关键问题）
            4. 若信息大致够，给出下一步最短路径（3 步内）

            用户输入：
            {{input}}
            """
        ),
        ChatMode(
            name: "计划模式",
            command: "plan",
            summary: "拆步骤、排优先级、标风险",
            template: """
            【计划模式】
            输出可执行计划，不要直接写最终成稿：
            1. 目标与约束
            2. 分步计划（步骤 / 产出 / 依赖）
            3. 优先级与建议顺序
            4. 风险与备选
            5. 你建议我下一条消息先做哪一步

            用户输入：
            {{input}}
            """
        ),
        ChatMode(
            name: "问答模式",
            command: "ask",
            summary: "简洁回答，少发挥",
            template: """
            【问答模式】
            直接回答问题，短句优先；不确定就说明不确定。
            默认不扩展成完整方案，除非用户要求。

            问题：
            {{input}}
            """
        ),
        ChatMode(
            name: "执行模式",
            command: "execute",
            summary: "少问多做，直接产出结果",
            template: """
            【执行模式】
            基于已有上下文直接产出可用结果。
            少解释、少反问；只有关键信息缺失到无法继续时才问 1 个问题。
            输出应可直接复制使用。

            任务：
            {{input}}
            """
        ),
        ChatMode(
            name: "压缩上下文",
            command: "compress",
            summary: "把当前对话压成摘要，腾出上下文",
            template: """
            【压缩上下文】
            将下列对话压缩为结构化摘要，供后续继续协作。要求：
            - 保留：目标、已确认设定、关键结论、未决问题、下一步
            - 删除：寒暄、重复、失败尝试细节
            - 用简洁条目，控制在 800 字内
            - 只输出摘要正文

            对话内容：
            {{input}}
            """
        ),
    ]

    /// 模式
    ///
    /// 模式。
    static func mode(command: String) -> ChatMode? {
        let key = command.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return all.first { $0.command == key }
    }
}

// MARK: - 技能 / 插件（≠ 对话模式 /goal /plan）

/// SkillScope
///
/// `SkillScope` 类型定义。
enum SkillScope: String, Codable, CaseIterable, Identifiable, Hashable {
    /// builtIn。
    case builtIn
    /// personal。
    case personal

    /// 唯一标识符。
    var id: String { rawValue }

    /// 标题。
    var title: String {
        switch self {
        case .builtIn: "内置"
        case .personal: "个人"
        }
    }
}

/// 插件：技能的分组容器。
///
/// 用于启用/禁用一组相关技能。内置插件不可删除。
///
/// - SeeAlso: ``HeiNiuSkill``, ``SkillScope``
///
struct HeiNiuPlugin: Identifiable, Codable, Hashable {
    /// 唯一标识符。
    var id: UUID
    /// 显示名称。
    var name: String
    /// 简介。
    var summary: String
    /// 内置或个人范围。
    var scope: SkillScope
    /// 是否启用。
    var isEnabled: Bool
    /// 关联的技能 command 列表（便于展示）
    var skillCommands: [String]
    /// 版本号。
    var version: String
    /// 作者。
    var author: String

    /// 初始化方法
    ///
    /// 初始化方法。
    init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        scope: SkillScope = .personal,
        isEnabled: Bool = true,
        skillCommands: [String] = [],
        version: String = "1.0",
        author: String = ""
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.scope = scope
        self.isEnabled = isEnabled
        self.skillCommands = skillCommands
        self.version = version
        self.author = author
    }

    /// 初始化方法
    ///
    /// 初始化方法。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "插件"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        scope = try c.decodeIfPresent(SkillScope.self, forKey: .scope) ?? .personal
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        skillCommands = try c.decodeIfPresent([String].self, forKey: .skillCommands) ?? []
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
    }

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 唯一标识符。
        case id, name, summary, scope, isEnabled, skillCommands, version, author
    }
}

/// 可配置技能（能力包），聊天中以 `$command` 触发。
///
/// 与对话模式（`/goal` 等）不同：技能可增删改，可归属 ``HeiNiuPlugin``。
///
/// ## 设计原则
///
/// - 命令名不可与 ``BuiltInChatModes`` 冲突  
/// - `pluginID != nil` 时只在插件页展示  
/// - 插件禁用则技能不可调用  
///
/// ```swift
/// let skill = HeiNiuSkill(
///     name: "写短剧大纲",
///     command: "outline",
///     summary: "输出可拍大纲",
///     template: "请写大纲：\n{{input}}",
///     scope: .personal
/// )
/// ```
///
/// - SeeAlso: ``HeiNiuPlugin``, ``BuiltInChatModes``, <doc:SkillsAndPlugins>
///
struct HeiNiuSkill: Identifiable, Codable, Hashable {
    /// 唯一标识符。
    var id: UUID
    /// 显示名称。
    var name: String
    /// 斜杠命令，如 outline（不可与内置模式命令冲突）
    var command: String
    /// 简介。
    var summary: String
    /// 注入模板；可用 {{input}} 占位
    var template: String
    /// 内置或个人范围。
    var scope: SkillScope
    /// 所属插件 id（可选）
    var pluginID: UUID?
    /// 兼容旧字段
    var isBuiltIn: Bool

    /// 初始化方法
    ///
    /// 初始化方法。
    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        summary: String,
        template: String,
        scope: SkillScope = .personal,
        pluginID: UUID? = nil,
        isBuiltIn: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.summary = summary
        self.template = template
        self.scope = scope
        self.pluginID = pluginID
        self.isBuiltIn = isBuiltIn ?? (scope == .builtIn)
    }

    /// 斜杠命令形式，如 /goal。
    var slash: String { "/\(command)" }

    /// 聊天里技能触发前缀展示（$command）
    var dollar: String { "$\(command)" }

    /// 初始化方法
    ///
    /// 初始化方法。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "技能"
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? "skill"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        template = try c.decodeIfPresent(String.self, forKey: .template) ?? "{{input}}"
        pluginID = try c.decodeIfPresent(UUID.self, forKey: .pluginID)
        if let scope = try c.decodeIfPresent(SkillScope.self, forKey: .scope) {
            self.scope = scope
            isBuiltIn = scope == .builtIn
        } else {
            let builtIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
            isBuiltIn = builtIn
            scope = builtIn ? .builtIn : .personal
        }
    }

    /// encode
    ///
    /// 执行 `encode` 相关逻辑。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(command, forKey: .command)
        try c.encode(summary, forKey: .summary)
        try c.encode(template, forKey: .template)
        try c.encode(scope, forKey: .scope)
        try c.encodeIfPresent(pluginID, forKey: .pluginID)
        try c.encode(scope == .builtIn, forKey: .isBuiltIn)
    }

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 唯一标识符。
        case id, name, command, summary, template, scope, pluginID, isBuiltIn
    }
}

/// DefaultHeiNiuPlugins
///
/// `DefaultHeiNiuPlugins` 类型定义。
enum DefaultHeiNiuPlugins {
    /// 固定 UUID，保证重启后关联稳定
    static let dramaPackID = UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!
    static let visualPackID = UUID(uuidString: "A1000000-0000-4000-8000-000000000002")!

    /// 返回全部预置项
    ///
    /// 返回全部预置项。
    static func all() -> [HeiNiuPlugin] {
        [
            HeiNiuPlugin(
                id: dramaPackID,
                name: "短剧编剧包",
                summary: "大纲、对白、分镜等编剧向能力",
                scope: .builtIn,
                isEnabled: true,
                skillCommands: ["outline", "dialogue", "shots"],
                version: "1.0",
                author: "黑妞短剧"
            ),
            HeiNiuPlugin(
                id: visualPackID,
                name: "视觉提示词包",
                summary: "生图提示词等视觉向能力",
                scope: .builtIn,
                isEnabled: true,
                skillCommands: ["imgprompt"],
                version: "1.0",
                author: "黑妞短剧"
            ),
        ]
    }
}

/// DefaultHeiNiuSkills
///
/// `DefaultHeiNiuSkills` 类型定义。
enum DefaultHeiNiuSkills {
    /// 预置内置技能（真正的能力包，不是对话模式）
    static func all() -> [HeiNiuSkill] {
        [
            HeiNiuSkill(
                name: "写短剧大纲",
                command: "outline",
                summary: "按卖点 / 人物 / 冲突输出可拍大纲",
                template: """
                请根据以下需求，输出 3 个可拍的竖屏短剧大纲。每个含：一句话卖点、人物关系、核心冲突、结局走向、建议时长。

                需求：
                {{input}}
                """,
                scope: .builtIn,
                pluginID: DefaultHeiNiuPlugins.dramaPackID
            ),
            HeiNiuSkill(
                name: "润色对白",
                command: "dialogue",
                summary: "把对白改得更口语、更抓耳",
                template: """
                请润色下列对白，保持剧情不变，让台词更短、冲突更强。只输出润色结果。

                {{input}}
                """,
                scope: .builtIn,
                pluginID: DefaultHeiNiuPlugins.dramaPackID
            ),
            HeiNiuSkill(
                name: "拆分镜表",
                command: "shots",
                summary: "剧本拆成镜号 / 景别 / 运镜",
                template: """
                将下列内容拆成竖屏短剧分镜表。每镜：镜号、景别、画面、对白、运镜、秒数。

                {{input}}
                """,
                scope: .builtIn,
                pluginID: DefaultHeiNiuPlugins.dramaPackID
            ),
            HeiNiuSkill(
                name: "生图提示词",
                command: "imgprompt",
                summary: "生成 AI 绘图提示词",
                template: """
                为 AI 绘图生成高质量提示词（英文为主），含主体、光影、镜头、风格。避免水印文字。

                描述：
                {{input}}
                """,
                scope: .builtIn,
                pluginID: DefaultHeiNiuPlugins.visualPackID
            ),
        ]
    }
}

// MARK: - Context accounting

/// ContextBucket
///
/// `ContextBucket` 类型定义。
struct ContextBucket: Identifiable, Hashable {
    /// 唯一标识符。
    var id: String { name }
    /// 显示名称。
    var name: String
    /// characters。
    var characters: Int
    /// colorHue。
    var colorHue: Double
}

/// ContextUsage
///
/// `ContextUsage` 类型定义。
struct ContextUsage: Hashable {
    /// limitCharacters。
    var limitCharacters: Int
    /// buckets。
    var buckets: [ContextBucket]

    /// totalCharacters。
    var totalCharacters: Int { buckets.reduce(0) { $0 + $1.characters } }

    /// ratio。
    var ratio: Double {
        guard limitCharacters > 0 else { return 0 }
        return min(1, Double(totalCharacters) / Double(limitCharacters))
    }

    /// percentText。
    var percentText: String {
        String(format: "%.1f%%", ratio * 100)
    }

    /// displayCount
    ///
    /// 执行 `displayCount` 相关逻辑。
    func displayCount(_ n: Int) -> String {
        if n >= 10_000 {
            return String(format: "%.1f万", Double(n) / 10_000)
        }
        if n >= 1000 {
            return String(format: "%.1f千", Double(n) / 1000)
        }
        return "\(n)"
    }

    /// headline。
    var headline: String {
        "\(displayCount(totalCharacters))/\(displayCount(limitCharacters))（\(percentText)）"
    }
}

/// 按字符近似估算上下文占用。
///
/// 中文场景下比 token 更直观；结果供 ``ContextUsageBar`` 展示。
///
enum ContextEstimator {
    /// 粗略按字符估算（中文场景比 token 更直观）；默认窗口可配置
    static let defaultLimit = 200_000

    /// estimate
    ///
    /// 执行 `estimate` 相关逻辑。
    static func estimate(
        systemPrompt: String,
        knowledge: [KnowledgeItem],
        activeSkills: [HeiNiuSkill],
        messages: [ChatTurn],
        attachments: [ChatAttachment],
        insertedSessions: [String],
        draft: String,
        limit: Int = defaultLimit
    ) -> ContextUsage {
        let sys = systemPrompt.count
        let know = knowledge.filter(\.enabled).reduce(0) { $0 + $1.charCount }
        let skill = activeSkills.reduce(0) { $0 + $1.template.count }
        let msg = messages.reduce(0) { $0 + $1.content.count }
        let att = attachments.reduce(0) { $0 + $1.charCount }
        let sess = insertedSessions.reduce(0) { $0 + $1.count }
        let draftCount = draft.count

        return ContextUsage(
            limitCharacters: limit,
            buckets: [
                ContextBucket(name: "消息", characters: msg + draftCount, colorHue: 0.58),
                ContextBucket(name: "知识库", characters: know, colorHue: 0.12),
                ContextBucket(name: "附件", characters: att, colorHue: 0.75),
                ContextBucket(name: "技能", characters: skill, colorHue: 0.85),
                ContextBucket(name: "系统提示词", characters: sys, colorHue: 0.45),
                ContextBucket(name: "插入会话", characters: sess, colorHue: 0.33),
            ].filter { $0.characters > 0 }
        )
    }
}
