/// 黑妞仓库：角色、对话、知识库、技能插件。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation
import Observation
import UniformTypeIdentifiers

/// 黑妞与对话的主仓库。
///
/// `HeiNiuAgentStore` 是黑妞模块的单一数据源，负责：
///
/// - 黑妞角色（``HeiNiuAgent``）增删改查
/// - 会话（``HeiNiuConversation``）与 LLM 收发
/// - 知识库（``KnowledgeItem``）导入与启用
/// - 技能（``HeiNiuSkill``）与插件（``HeiNiuPlugin``）管理
///
/// ## 设计原则
///
/// - **UI 不直接碰磁盘**：视图只调用本类型 API。
/// - **密钥隔离**：不存 API Key；发送时从 ``SettingsStore`` 读钥匙串。
/// - **插件门禁**：技能所属插件禁用时，`skill(command:)` 返回 `nil`。
/// - **容错加载**：JSON 异常时回退预置，避免启动失败。
///
/// ## 调用示例
///
/// ```swift
/// let agents = HeiNiuAgentStore()
/// let settings = SettingsStore()
///
/// let agent = agents.addAgent(named: "编剧黑妞")
/// var a = agent
/// a.providerID = settings.providers.first?.id
/// a.model = settings.providers.first?.models.first ?? "gpt-4o"
/// agents.updateAgent(a)
///
/// let chat = agents.startConversation(agentID: a.id)
/// try await agents.send(
///     package: .init(
///         displayText: "写一个都市反转大纲",
///         modelUserText: "写一个都市反转大纲",
///         skillCommands: [],
///         attachmentNames: [],
///         insertedSessionTitles: []
///     ),
///     conversationID: chat.id,
///     settings: settings
/// )
/// ```
///
/// ## 相关文档
///
/// - ``HeiNiuAgent``、``SettingsStore``、``LLMClientFactory``
/// - <doc:HeiNiuAgents>、<doc:ChatComposer>
///
@Observable
@MainActor
final class HeiNiuAgentStore {
    /// 全部黑妞角色（磁盘顺序）。
    ///
    /// 列表 UI 请用 ``sortedAgents``。文件：`agents.json`。
    ///
    /// - SeeAlso: ``addAgent(named:)``, ``deleteAgent(id:)``
    ///
    var agents: [HeiNiuAgent] = []
    /// 全部对话会话。
    ///
    /// 按角色筛选：``conversations(for:)``；跨会话引用：``insertableConversations(excluding:)``。
    ///
    /// - Important: 删除角色会级联删除其会话。
    ///
    var conversations: [HeiNiuConversation] = []
    /// 知识库索引（含抽取文本）。
    ///
    /// 原文件在 `Knowledge/<agentID>/`。聊天仅注入 ``enabledKnowledge(for:)``。
    ///
    /// - SeeAlso: ``importKnowledge(from:agentID:)``
    ///
    var knowledgeItems: [KnowledgeItem] = []
    /// 技能库（内置 + 个人）。
    ///
    /// 聊天用 `$command` 触发。对话模式 `/goal` 等**不是**技能（见 ``BuiltInChatModes``）。
    ///
    /// - SeeAlso: ``standaloneSkills(scope:)``, ``resolveSlash(_:)``
    ///
    var skills: [HeiNiuSkill] = []
    /// 插件列表（技能容器）。
    ///
    /// 用于分组管理技能：归属插件的技能只在插件页展示，避免与独立技能列表重复。
    ///
    /// ## 设计原则
    ///
    /// - `isEnabled == false` 时，其下技能在聊天中不可用。
    /// - 内置插件可开关、不可删除。
    ///
    /// ## 示例
    ///
    /// ```swift
    /// if var plugin = agents.plugins.first {
    ///     plugin.isEnabled = false
    ///     agents.updatePlugin(plugin)
    /// }
    /// ```
    ///
    /// - SeeAlso: ``HeiNiuPlugin``, ``skills(inPlugin:)``, ``sortedPlugins``
    ///
    var plugins: [HeiNiuPlugin] = []

    /// JSON 编码器（美化输出、ISO8601 日期）。
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// JSON 解码器（ISO8601 日期）。
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// 初始化方法
    ///
    /// 初始化方法。
    init() {
        AppPaths.ensureDirectories()
        load()
    }

    // MARK: - Agents

    /// 按排序权重与名称排序后的黑妞列表。
    var sortedAgents: [HeiNiuAgent] {
        agents.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// 按 ID 查找黑妞
    ///
    /// 按 ID 查找黑妞。
    func agent(id: UUID?) -> HeiNiuAgent? {
        guard let id else { return nil }
        return agents.first { $0.id == id }
    }

    /// 新建黑妞并立即写入 `agents.json`。
    ///
    /// 同时创建知识库目录与默认指令。新建后需绑定 `providerID`/`model` 才能
    /// ``HeiNiuAgentStore/send(package:conversationID:settings:activeSkillIDs:)``。
    ///
    /// - Parameter name: 显示名，默认「新黑妞」。
    /// - Returns: 新建的 ``HeiNiuAgent``。
    ///
    /// ```swift
    /// let agent = store.addAgent(named: "分镜黑妞")
    /// ```
    ///
    @discardableResult
    func addAgent(named name: String = "新黑妞") -> HeiNiuAgent {
        let nextOrder = (agents.map(\.sortOrder).max() ?? -1) + 1
        let agent = HeiNiuAgent(
            name: name,
            subtitle: "自定义助手",
            instructions: """
            你是「\(name)」，黑妞短剧里的专属 AI 助手。

            请说明你的专长，并始终以对创作者有用、可执行为目标回答。
            """,
            conversationStarters: ["你能帮我做什么？", "从哪里开始比较好？"],
            sortOrder: nextOrder
        )
        agents.append(agent)
        _ = AppPaths.ensureKnowledgeDirectory(for: agent.id)
        saveAgents()
        return agent
    }

    /// 用新值覆盖同 ID 黑妞并刷新 `updatedAt`。
    ///
    /// - Parameter agent: 完整角色快照。
    /// - Note: 找不到 ID 时静默忽略。
    ///
    func updateAgent(_ agent: HeiNiuAgent) {
        guard let index = agents.firstIndex(where: { $0.id == agent.id }) else { return }
        var updated = agent
        updated.updatedAt = Date()
        agents[index] = updated
        saveAgents()
    }

    /// 删除黑妞及关联会话、知识库文件。
    ///
    /// - Parameter id: 角色 ID。
    ///
    func deleteAgent(id: UUID) {
        agents.removeAll { $0.id == id }
        conversations.removeAll { $0.agentID == id }
        let removed = knowledgeItems.filter { $0.agentID == id }
        knowledgeItems.removeAll { $0.agentID == id }
        let dir = AppPaths.knowledgeDirectory(for: id)
        try? FileManager.default.removeItem(at: dir)
        _ = removed
        saveAgents()
        saveConversations()
        saveKnowledge()
    }

    /// 复制黑妞（含知识库元数据）
    ///
    /// 复制黑妞（含知识库元数据）。
    @discardableResult
    func duplicateAgent(id: UUID) -> HeiNiuAgent? {
        guard let source = agent(id: id) else { return nil }
        let nextOrder = (agents.map(\.sortOrder).max() ?? -1) + 1
        var copy = source
        copy.id = UUID()
        copy.name = source.name + " 副本"
        copy.isBuiltIn = false
        copy.sortOrder = nextOrder
        copy.createdAt = Date()
        copy.updatedAt = Date()
        agents.append(copy)
        _ = AppPaths.ensureKnowledgeDirectory(for: copy.id)
        // 复制知识库元数据与文本（不强制拷贝原文件）
        for item in knowledge(for: source.id) {
            var k = item
            k.id = UUID()
            k.agentID = copy.id
            k.createdAt = Date()
            k.updatedAt = Date()
            knowledgeItems.append(k)
        }
        saveAgents()
        saveKnowledge()
        return copy
    }

    // MARK: - Knowledge

    /// 查询某黑妞的知识库条目
    ///
    /// 查询某黑妞的知识库条目。
    func knowledge(for agentID: UUID) -> [KnowledgeItem] {
        knowledgeItems
            .filter { $0.agentID == agentID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 返回已启用的知识库条目
    ///
    /// 返回已启用的知识库条目。
    func enabledKnowledge(for agentID: UUID) -> [KnowledgeItem] {
        knowledge(for: agentID).filter(\.enabled)
    }

    /// 导入本地文件到指定黑妞知识库。
    ///
    /// 复制文件到 `Knowledge/<agentID>/`，并用 ``TextExtractor`` 抽取文本写入索引。
    ///
    /// - Parameters:
    ///   - urls: 安全作用域文件 URL 列表。
    ///   - agentID: 目标黑妞。
    /// - Returns: 新建的 ``KnowledgeItem`` 数组。
    ///
    @discardableResult
    func importKnowledge(from urls: [URL], agentID: UUID) -> [KnowledgeItem] {
        let dir = AppPaths.ensureKnowledgeDirectory(for: agentID)
        var created: [KnowledgeItem] = []

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let extract = TextExtractor.extract(from: url)
            let safeName = uniqueFileName(url.lastPathComponent, in: dir)
            let dest = dir.appendingPathComponent(safeName)
            try? FileManager.default.copyItem(at: url, to: dest)

            let item = KnowledgeItem(
                agentID: agentID,
                name: url.lastPathComponent,
                fileName: safeName,
                mimeHint: extract.mime,
                byteSize: extract.byteSize,
                extractedText: extract.text
            )
            knowledgeItems.append(item)
            created.append(item)
        }
        saveKnowledge()
        return created
    }

    /// 添加笔记型知识库条目
    ///
    /// 添加笔记型知识库条目。
    func addKnowledgeNote(agentID: UUID, title: String, body: String) {
        let dir = AppPaths.ensureKnowledgeDirectory(for: agentID)
        let fileName = uniqueFileName("\(title.isEmpty ? "note" : title).md", in: dir)
        let dest = dir.appendingPathComponent(fileName)
        try? body.data(using: .utf8)?.write(to: dest)

        let item = KnowledgeItem(
            agentID: agentID,
            name: title.isEmpty ? "笔记" : title,
            fileName: fileName,
            mimeHint: "text/markdown",
            byteSize: body.utf8.count,
            extractedText: body
        )
        knowledgeItems.append(item)
        saveKnowledge()
    }

    /// 更新知识库条目
    ///
    /// 更新知识库条目。
    func updateKnowledge(_ item: KnowledgeItem) {
        guard let index = knowledgeItems.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.updatedAt = Date()
        knowledgeItems[index] = updated
        saveKnowledge()
    }

    /// 删除知识库条目
    ///
    /// 删除知识库条目。
    func deleteKnowledge(id: UUID) {
        guard let item = knowledgeItems.first(where: { $0.id == id }) else { return }
        let url = AppPaths.knowledgeDirectory(for: item.agentID).appendingPathComponent(item.fileName)
        try? FileManager.default.removeItem(at: url)
        knowledgeItems.removeAll { $0.id == id }
        saveKnowledge()
    }

    // MARK: - Plugins & Skills

    /// 排序后的插件列表（内置优先）。
    var sortedPlugins: [HeiNiuPlugin] {
        plugins.sorted {
            if $0.scope != $1.scope { return $0.scope == .builtIn }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// 排序后的技能列表（内置优先）。
    var sortedSkills: [HeiNiuSkill] {
        skills.sorted {
            if $0.scope != $1.scope { return $0.scope == .builtIn }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// 按范围筛选插件
    ///
    /// 按范围筛选插件。
    func plugins(scope: SkillScope) -> [HeiNiuPlugin] {
        sortedPlugins.filter { $0.scope == scope }
    }

    /// 按范围或插件筛选技能
    ///
    /// 按范围或插件筛选技能。
    func skills(scope: SkillScope) -> [HeiNiuSkill] {
        sortedSkills.filter { $0.scope == scope }
    }

    /// 返回未归属插件的技能（供「技能」页展示）。
    ///
    /// 归属插件的技能只在插件页列出，避免重复管理。
    ///
    /// - Parameter scope: 内置或个人。
    ///
    func standaloneSkills(scope: SkillScope) -> [HeiNiuSkill] {
        skills(scope: scope).filter { $0.pluginID == nil }
    }

    /// 返回插件包含的技能（按 `pluginID` 或 command 关联）。
    ///
    /// - Parameter plugin: 插件。
    ///
    func skills(inPlugin plugin: HeiNiuPlugin) -> [HeiNiuSkill] {
        let cmds = Set(plugin.skillCommands.map { $0.lowercased() })
        return sortedSkills.filter { skill in
            if skill.pluginID == plugin.id { return true }
            return cmds.contains(skill.command.lowercased())
        }
    }

    /// 按 ID 查找插件
    ///
    /// 按 ID 查找插件。
    func plugin(id: UUID?) -> HeiNiuPlugin? {
        guard let id else { return nil }
        return plugins.first { $0.id == id }
    }

    /// 按命令名查找可用技能
    ///
    /// 按命令名查找可用技能。
    func skill(command: String) -> HeiNiuSkill? {
        let key = command.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/$¥"))
        // 模式不是技能
        if BuiltInChatModes.commands.contains(key) { return nil }
        guard let skill = skills.first(where: { $0.command.lowercased() == key }) else { return nil }
        // 所属插件被禁用则不可用
        if let pid = skill.pluginID, let plugin = plugin(id: pid), !plugin.isEnabled {
            return nil
        }
        return skill
    }

    /// 解析 `/` 或 `$` 触发词。
    ///
    /// 优先 ``BuiltInChatModes``，再查技能库。
    ///
    /// - Parameter command: 可带 `/`、`$`、`¥` 前缀。
    /// - Returns: 模式与技能至多一个非空。
    ///
    /// ```swift
    /// let (mode, skill) = store.resolveSlash("$outline")
    /// ```
    ///
    func resolveSlash(_ command: String) -> (mode: ChatMode?, skill: HeiNiuSkill?) {
        let key = command.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/$¥"))
        if let mode = BuiltInChatModes.mode(command: key) {
            return (mode, nil)
        }
        return (nil, skill(command: key))
    }

    /// 更新插件
    ///
    /// 更新插件。
    func updatePlugin(_ plugin: HeiNiuPlugin) {
        guard let index = plugins.firstIndex(where: { $0.id == plugin.id }) else { return }
        // 内置插件允许改启用状态与摘要，不允许改 scope
        var updated = plugin
        if plugins[index].scope == .builtIn {
            updated.scope = .builtIn
            updated.id = plugins[index].id
        }
        plugins[index] = updated
        savePlugins()
    }

    /// 插入或更新插件
    ///
    /// 插入或更新插件。
    func upsertPlugin(_ plugin: HeiNiuPlugin) {
        if let index = plugins.firstIndex(where: { $0.id == plugin.id }) {
            plugins[index] = plugin
        } else {
            plugins.append(plugin)
        }
        savePlugins()
    }

    /// 删除个人插件
    ///
    /// 删除个人插件。
    func deletePlugin(id: UUID) {
        guard let plugin = plugins.first(where: { $0.id == id }), plugin.scope == .personal else { return }
        plugins.removeAll { $0.id == id }
        // 解绑技能
        for i in skills.indices where skills[i].pluginID == id {
            skills[i].pluginID = nil
        }
        savePlugins()
        saveSkills()
    }

    /// 更新技能
    ///
    /// 更新技能。
    func updateSkill(_ skill: HeiNiuSkill) {
        guard let index = skills.firstIndex(where: { $0.id == skill.id }) else { return }
        var updated = skill
        // 内置技能可改模板/简介，但保持 builtIn scope
        if skills[index].scope == .builtIn {
            updated.scope = .builtIn
            updated.isBuiltIn = true
            updated.command = skills[index].command // 命令锁定
        } else {
            updated.scope = .personal
            updated.isBuiltIn = false
        }
        skills[index] = updated
        syncPluginSkillCommands()
        saveSkills()
        savePlugins()
    }

    /// 插入或更新技能
    ///
    /// 插入或更新技能。
    func upsertSkill(_ skill: HeiNiuSkill) {
        var s = skill
        if BuiltInChatModes.commands.contains(s.command.lowercased()) {
            s.command = "skill-\(s.command)"
        }
        if s.scope == .builtIn {
            s.isBuiltIn = true
        } else {
            s.isBuiltIn = false
            s.scope = .personal
        }
        if let index = skills.firstIndex(where: { $0.id == s.id }) {
            skills[index] = s
        } else {
            skills.append(s)
        }
        syncPluginSkillCommands()
        saveSkills()
        savePlugins()
    }

    /// 删除个人技能
    ///
    /// 删除个人技能。
    func deleteSkill(id: UUID) {
        // 仅个人技能可删
        skills.removeAll { $0.id == id && $0.scope == .personal }
        for i in agents.indices {
            agents[i].enabledSkillIDs.removeAll { $0 == id }
        }
        syncPluginSkillCommands()
        saveSkills()
        savePlugins()
        saveAgents()
    }

    /// syncPluginSkillCommands
    ///
    /// 执行 `syncPluginSkillCommands` 相关逻辑。
    private func syncPluginSkillCommands() {
        for i in plugins.indices {
            let pid = plugins[i].id
            plugins[i].skillCommands = skills
                .filter { $0.pluginID == pid }
                .map(\.command)
                .sorted()
        }
    }

    /// 清理各黑妞对手动 MCP 勾选的引用
    ///
    /// 清理各黑妞对手动 MCP 勾选的引用。
    func purgeMCPReferences(serverID: UUID) {
        for i in agents.indices {
            agents[i].enabledMCPServerIDs.removeAll { $0 == serverID }
        }
        saveAgents()
    }

    // MARK: - Conversations

    /// 全部对话会话
    ///
    /// 全部对话会话。
    func conversations(for agentID: UUID) -> [HeiNiuConversation] {
        conversations
            .filter { $0.agentID == agentID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 其它会话（可插入上下文），可跨黑妞
    func insertableConversations(excluding conversationID: UUID?) -> [HeiNiuConversation] {
        conversations
            .filter { $0.id != conversationID && !$0.messages.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// conversation
    ///
    /// 执行 `conversation` 相关逻辑。
    func conversation(id: UUID?) -> HeiNiuConversation? {
        guard let id else { return nil }
        return conversations.first { $0.id == id }
    }

    /// 为指定黑妞创建空会话并置顶。
    ///
    /// - Parameter agentID: 黑妞 ID。
    /// - Returns: 新 ``HeiNiuConversation``。
    ///
    @discardableResult
    func startConversation(agentID: UUID) -> HeiNiuConversation {
        let conversation = HeiNiuConversation(agentID: agentID)
        conversations.insert(conversation, at: 0)
        saveConversations()
        return conversation
    }

    /// 删除对话
    ///
    /// 删除对话。
    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        saveConversations()
    }

    /// 更新对话并刷新时间戳
    ///
    /// 更新对话并刷新时间戳。
    func updateConversation(_ conversation: HeiNiuConversation) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        var updated = conversation
        updated.updatedAt = Date()
        conversations[index] = updated
        saveConversations()
    }

    /// 将会话格式化为可注入的摘要文本。
    ///
    /// 用于聊天 `#` 插入其它会话。默认截断到 `maxCharacters`。
    ///
    /// - Parameters:
    ///   - conversation: 源会话。
    ///   - maxCharacters: 最大字符数，默认 12000。
    /// - Returns: 带标题与角色标注的纯文本。
    ///
    func formatConversationForInsert(_ conversation: HeiNiuConversation, maxCharacters: Int = 12_000) -> String {
        let agentName = agent(id: conversation.agentID)?.name ?? "黑妞"
        var lines: [String] = ["【插入会话：\(conversation.title) · \(agentName)】"]
        for turn in conversation.messages.suffix(30) {
            let role = turn.role == .user ? "用户" : (turn.role == .assistant ? "助手" : "系统")
            lines.append("\(role)：\(turn.content)")
        }
        return TextExtractor.truncate(lines.joined(separator: "\n"), max: maxCharacters)
    }

    // MARK: - Translate

    /// 翻译方向。
    enum TranslateDirection: Hashable, Sendable {
        /// 译成英文。
        case toEnglish
        /// 译成中文。
        case toChinese
        /// 按正文自动判断：偏中文 → 英；否则 → 中。
        case auto
    }

    /// 将文本翻译（不写会话）。
    ///
    /// 优先全局翻译模型；未配置时回退黑妞模型。`reasoningEffort = none`。
    ///
    /// - Parameters:
    ///   - text: 原文。
    ///   - direction: 方向；`TranslateDirection.auto` 时按汉字占比判断。
    ///   - agent: 回退用黑妞。
    ///   - settings: API Key / 全局翻译配置。
    /// - Returns: 译文。
    func translate(
        _ text: String,
        direction: TranslateDirection = .auto,
        agent: HeiNiuAgent,
        settings: SettingsStore
    ) async throws -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "" }

        guard let target = settings.resolveTranslationTarget(fallbackAgent: agent) else {
            throw LLMError.missingProvider
        }
        let provider = target.provider
        let model = target.model

        let apiKey = settings.apiKey(for: provider.id)
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        let resolved: TranslateDirection = {
            switch direction {
            case .auto: return Self.inferredDirection(for: source)
            case .toEnglish, .toChinese: return direction
            }
        }()

        let system: String = {
            switch resolved {
            case .toEnglish:
                return """
                You are a precise translator for a short-drama writing workbench.
                Translate the user's text into natural, fluent English.
                Rules:
                - Output English translation only.
                - Preserve meaning, tone, line breaks, and markdown structure.
                - Keep proper names when appropriate; do not add explanations.
                - If the text is already English, lightly polish and return it.
                """
            case .toChinese:
                return """
                你是短剧创作工作台的精准翻译。
                将用户文本译为自然流畅的简体中文。
                规则：
                - 只输出中文译文，不要解释。
                - 保留语气、换行与 Markdown 结构。
                - 专有名词可酌情保留原文。
                - 若原文已是中文，可轻度润色后返回。
                """
            case .auto:
                // 已在上方 resolve
                return ""
            }
        }()

        let client = LLMClientFactory.make(for: provider)
        let messages: [LLMChatMessage] = [
            LLMChatMessage(role: .system, content: system),
            LLMChatMessage(role: .user, content: source),
        ]

        let completion = try await client.complete(
            messages: messages,
            model: model,
            temperature: min(agent.temperature, 0.4),
            reasoningEffort: .none,
            apiKey: apiKey
        )
        let translated = completion.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty else { throw LLMError.emptyResponse }
        return translated
    }

    /// 输入框「译英」便捷入口。
    func translateToEnglish(
        _ text: String,
        agent: HeiNiuAgent,
        settings: SettingsStore
    ) async throws -> String {
        try await translate(text, direction: .toEnglish, agent: agent, settings: settings)
    }

    /// 按汉字/假名等 CJK 占比推断翻译方向。
    static func inferredDirection(for text: String) -> TranslateDirection {
        var cjk = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                // CJK Unified + 扩展、假名、韩文
                if (0x4E00...0x9FFF).contains(scalar.value)
                    || (0x3400...0x4DBF).contains(scalar.value)
                    || (0x3040...0x30FF).contains(scalar.value)
                    || (0xAC00...0xD7AF).contains(scalar.value)
                    || (0xF900...0xFAFF).contains(scalar.value) {
                    cjk += 1
                } else if (0x0041...0x005A).contains(scalar.value)
                    || (0x0061...0x007A).contains(scalar.value) {
                    latin += 1
                }
            }
        }
        // 明显偏中文 → 英；否则默认中译方向（含中英混排英文为主）
        if cjk > 0, cjk >= latin {
            return .toEnglish
        }
        return .toChinese
    }

    /// 原地替换某条消息正文（用于气泡内翻译结果写回）。
    func replaceMessageContent(
        conversationID: UUID,
        messageID: UUID,
        content: String
    ) {
        guard var conversation = conversation(id: conversationID),
              let index = conversation.messages.firstIndex(where: { $0.id == messageID })
        else { return }
        conversation.messages[index].content = content
        // 翻译后清掉旧思考过程，避免中英错位
        conversation.messages[index].reasoning = nil
        updateConversation(conversation)
    }

    // MARK: - Send

    /// 发送消息包：分离 UI 展示与模型真实输入。
    ///
    /// - `displayText`：气泡可见文案  
    /// - `modelUserText`：发给模型的完整用户内容（模板/附件/会话）  
    /// - `skillCommands`：本轮命令名列表  
    ///
    /// 由 ``HeiNiuChatView`` 组装后交给
    /// ``HeiNiuAgentStore/send(package:conversationID:settings:activeSkillIDs:)``。
    ///
    struct SendPackage {
        var displayText: String
        var modelUserText: String
        var skillCommands: [String]
        var attachmentNames: [String]
        var insertedSessionTitles: [String]
    }

    /// 发送一轮聊天：写气泡、组装上下文、调用 LLM、追加回复。
    ///
    /// ## 流程
    ///
    /// 1. 校验服务商 / 模型 / API Key  
    /// 2. 追加用户气泡（`package.displayText`）  
    /// 3. system = 指令 + 启用知识库 + 技能说明  
    /// 4. 用户侧 = 历史 + `package.modelUserText`  
    /// 5. ``LLMClientFactory/make(for:)`` 请求模型  
    ///
    /// - Parameters:
    ///   - package: 展示与模型侧文本分离的消息包。
    ///   - conversationID: 会话 ID。
    ///   - settings: 读取服务商与钥匙串。
    ///   - activeSkillIDs: 本轮激活技能。
    /// - Throws: ``LLMError`` 或底层网络错误。
    ///
    /// ```swift
    /// try await store.send(
    ///     package: .init(
    ///         displayText: "$outline 都市甜宠",
    ///         modelUserText: renderedTemplate,
    ///         skillCommands: ["outline"],
    ///         attachmentNames: [],
    ///         insertedSessionTitles: []
    ///     ),
    ///     conversationID: id,
    ///     settings: settings,
    ///     activeSkillIDs: [skillID]
    /// )
    /// ```
    ///
    /// - SeeAlso: ``SendPackage``, ``resolveSlash(_:)``, ``contextUsage(for:conversation:draft:attachments:insertedSessionTexts:activeSkillIDs:)``
    ///
    func send(
        package: SendPackage,
        conversationID: UUID,
        settings: SettingsStore,
        activeSkillIDs: [UUID] = []
    ) async throws {
        let display = package.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelText = package.modelUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !display.isEmpty || !modelText.isEmpty else { return }

        guard var conversation = conversation(id: conversationID) else { return }
        guard let agent = agent(id: conversation.agentID) else {
            throw LLMError.missingProvider
        }
        guard let providerID = agent.providerID,
              let provider = settings.provider(id: providerID)
        else {
            throw LLMError.missingProvider
        }

        let model = agent.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw LLMError.missingModel }

        let apiKey = settings.apiKey(for: providerID)
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        let bubble = display.isEmpty ? modelText : display
        conversation.messages.append(ChatTurn(role: .user, content: bubble))
        if conversation.title == "新对话" {
            conversation.title = String(bubble.prefix(24))
        }
        updateConversation(conversation)

        // system =（预置隐藏前缀 +）人设 + 知识库
        var systemParts: [String] = []
        let instructions = agent.effectiveSystemInstructions
        if !instructions.isEmpty {
            systemParts.append(instructions)
        }
        let knowledge = enabledKnowledge(for: agent.id)
        if !knowledge.isEmpty {
            var kb = ["# 知识库（请优先依据下列资料回答，并在相关时引用文件名）"]
            for item in knowledge {
                kb.append("## \(item.name)\n\(item.extractedText)")
            }
            systemParts.append(kb.joined(separator: "\n\n"))
        }

        // 激活技能说明（轻量）
        let activeSkills = skills.filter { activeSkillIDs.contains($0.id) }
        if !activeSkills.isEmpty {
            let skillDesc = activeSkills.map { "- /\($0.command)：\($0.summary)" }.joined(separator: "\n")
            systemParts.append("可用技能：\n\(skillDesc)")
        }

        var llmMessages: [LLMChatMessage] = []
        let system = systemParts.joined(separator: "\n\n")
        if !system.isEmpty {
            llmMessages.append(LLMChatMessage(role: .system, content: system))
        }

        // 历史（最后一条用户用 modelText 替换，便于附带上下文）
        let history = conversation.messages.dropLast()
        for turn in history {
            switch turn.role {
            case .user:
                llmMessages.append(LLMChatMessage(role: .user, content: turn.content))
            case .assistant:
                llmMessages.append(LLMChatMessage(role: .assistant, content: turn.content))
            case .system:
                break
            }
        }
        llmMessages.append(LLMChatMessage(role: .user, content: modelText.isEmpty ? bubble : modelText))

        let client = LLMClientFactory.make(for: provider)

        // 先插入空助手气泡，流式增量写入 content / reasoning
        let assistantID = UUID()
        guard var preparing = self.conversation(id: conversationID) else { return }
        preparing.messages.append(
            ChatTurn(id: assistantID, role: .assistant, content: "", reasoning: nil)
        )
        updateConversation(preparing)

        var contentBuffer = LLMStreamTextBuffer()
        var reasoningBuffer = LLMStreamTextBuffer()
        var lastPersist = Date.distantPast

        do {
            for try await event in client.stream(
                messages: llmMessages,
                model: model,
                temperature: agent.temperature,
                reasoningEffort: agent.reasoningEffort,
                apiKey: apiKey
            ) {
                switch event {
                case .reasoningDelta(let delta):
                    _ = reasoningBuffer.absorb(delta)
                case .contentDelta(let delta):
                    _ = contentBuffer.absorb(delta)
                }

                // 节流 UI 刷新：过密会导致左右气泡切换时滚动卡顿
                let now = Date()
                if now.timeIntervalSince(lastPersist) >= 0.22 {
                    lastPersist = now
                    applyStreamingAssistant(
                        conversationID: conversationID,
                        messageID: assistantID,
                        content: contentBuffer.text,
                        reasoning: reasoningBuffer.text
                    )
                }
            }
        } catch {
            // 已有部分内容则保留；完全空则移除占位气泡再抛出
            if contentBuffer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               reasoningBuffer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                removeMessage(conversationID: conversationID, messageID: assistantID)
            } else {
                finalizeStreamingAssistant(
                    conversationID: conversationID,
                    messageID: assistantID,
                    content: contentBuffer.text,
                    reasoning: reasoningBuffer.text
                )
            }
            throw error
        }

        finalizeStreamingAssistant(
            conversationID: conversationID,
            messageID: assistantID,
            content: contentBuffer.text,
            reasoning: reasoningBuffer.text
        )

        // 完全空响应
        if contentBuffer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           reasoningBuffer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            removeMessage(conversationID: conversationID, messageID: assistantID)
            throw LLMError.emptyResponse
        }
    }

    /// 流式过程中更新助手气泡（不强制改 updatedAt 过频，由调用方节流）。
    private func applyStreamingAssistant(
        conversationID: UUID,
        messageID: UUID,
        content: String,
        reasoning: String
    ) {
        guard var conversation = conversation(id: conversationID),
              let index = conversation.messages.firstIndex(where: { $0.id == messageID })
        else { return }

        let split = LLMReasoningExtractor.split(
            content: content,
            reasoning: reasoning.isEmpty ? nil : reasoning
        )
        conversation.messages[index].content = split.content
        // 流式中也做轻量清洗，避免界面闪出复读垃圾
        conversation.messages[index].reasoning = Self.usableReasoning(
            split.reasoning,
            content: split.content,
            recentUserText: conversation.messages.last(where: { $0.role == .user })?.content
        )
        // 流式中不每次 save，避免磁盘抖动；仅改内存
        if let convIndex = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[convIndex] = conversation
        }
    }

    /// 流结束：拆分 <think>、规范化并持久化。
    private func finalizeStreamingAssistant(
        conversationID: UUID,
        messageID: UUID,
        content: String,
        reasoning: String
    ) {
        guard var conversation = conversation(id: conversationID),
              let index = conversation.messages.firstIndex(where: { $0.id == messageID })
        else { return }

        let split = LLMReasoningExtractor.split(
            content: content,
            reasoning: reasoning.isEmpty ? nil : reasoning
        )
        // 仅有思考无正文时，正文留空、思考仍展示（避免把思考当答案）
        conversation.messages[index].content = split.content
        conversation.messages[index].reasoning = Self.usableReasoning(
            split.reasoning,
            content: split.content,
            recentUserText: conversation.messages.last(where: { $0.role == .user })?.content
        )
        updateConversation(conversation)
    }

    /// 过滤无价值「思考」：复读用户话、与正文相同、过短噪声。
    private static func usableReasoning(
        _ reasoning: String?,
        content: String,
        recentUserText: String?
    ) -> String? {
        guard let text = LLMReasoningExtractor.sanitizeReasoning(reasoning) else { return nil }

        if LLMReasoningExtractor.looksLikeUserEcho(text, userText: recentUserText) {
            return nil
        }

        let normalizedReasoning = Self.compactText(text)
        let normalizedContent = Self.compactText(content)
        if !normalizedContent.isEmpty, normalizedReasoning == normalizedContent {
            return nil
        }
        // 思考几乎就是正文的前缀/副本
        if !normalizedContent.isEmpty,
           normalizedReasoning.count >= 20,
           normalizedContent.hasPrefix(normalizedReasoning) || normalizedReasoning.hasPrefix(normalizedContent) {
            return nil
        }
        // 太短且没有实质结构，不当作思考展示
        if text.count < 12 { return nil }
        return text
    }

    private static func compactText(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined()
    }

    /// 移除指定消息（流式失败且无内容时清掉占位气泡）。
    private func removeMessage(conversationID: UUID, messageID: UUID) {
        guard var conversation = conversation(id: conversationID) else { return }
        conversation.messages.removeAll { $0.id == messageID }
        updateConversation(conversation)
    }

    /// 估算当前输入相关的上下文占用（字符近似）。
    ///
    /// 分桶：消息、知识库、附件、技能、系统提示、插入会话。用于 ``ContextUsageBar``。
    ///
    /// - Returns: ``ContextUsage`` 快照。
    /// - SeeAlso: ``ContextEstimator``
    ///
    func contextUsage(
        for agent: HeiNiuAgent,
        conversation: HeiNiuConversation?,
        draft: String,
        attachments: [ChatAttachment],
        insertedSessionTexts: [String],
        activeSkillIDs: [UUID]
    ) -> ContextUsage {
        let activeSkills = skills.filter { activeSkillIDs.contains($0.id) }
        return ContextEstimator.estimate(
            systemPrompt: agent.effectiveSystemInstructions,
            knowledge: enabledKnowledge(for: agent.id),
            activeSkills: activeSkills,
            messages: conversation?.messages ?? [],
            attachments: attachments,
            insertedSessions: insertedSessionTexts,
            draft: draft,
            limit: agent.contextCharacterLimit
        )
    }

    // MARK: - Persistence

    /// 从磁盘加载持久化数据
    ///
    /// 从磁盘加载持久化数据。
    private func load() {
        loadAgents()
        loadConversations()
        loadKnowledge()
        loadPlugins()
        loadSkills()
    }

    /// loadAgents
    ///
    /// 执行 `loadAgents` 相关逻辑。
    private func loadAgents() {
        let url = AppPaths.agentsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            agents = DefaultHeiNiuAgents.seed()
            saveAgents()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            agents = try decoder.decode([HeiNiuAgent].self, from: data)
            if agents.isEmpty {
                agents = DefaultHeiNiuAgents.seed()
                saveAgents()
            } else if seedMissingBuiltIns() {
                saveAgents()
            }
        } catch {
            agents = DefaultHeiNiuAgents.seed()
        }
    }

    /// loadConversations
    ///
    /// 执行 `loadConversations` 相关逻辑。
    private func loadConversations() {
        let url = AppPaths.conversationsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            conversations = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            conversations = try decoder.decode([HeiNiuConversation].self, from: data)
        } catch {
            conversations = []
        }
    }

    /// loadKnowledge
    ///
    /// 执行 `loadKnowledge` 相关逻辑。
    private func loadKnowledge() {
        let url = AppPaths.knowledgeIndexFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            knowledgeItems = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            knowledgeItems = try decoder.decode([KnowledgeItem].self, from: data)
        } catch {
            knowledgeItems = []
        }
    }

/// loadPlugins
///
/// 执行 `loadPlugins` 相关逻辑。
private func loadPlugins() {
        let url = AppPaths.pluginsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            plugins = DefaultHeiNiuPlugins.all()
            savePlugins()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            var loaded = try decoder.decode([HeiNiuPlugin].self, from: data)
            // 补齐内置插件
            let ids = Set(loaded.map(\.id))
            for seed in DefaultHeiNiuPlugins.all() where !ids.contains(seed.id) {
                loaded.append(seed)
            }
            // 内置插件保持 scope
            for i in loaded.indices {
                if DefaultHeiNiuPlugins.all().contains(where: { $0.id == loaded[i].id }) {
                    loaded[i].scope = .builtIn
                }
            }
            plugins = loaded
            savePlugins()
        } catch {
            plugins = DefaultHeiNiuPlugins.all()
        }
    }

    /// loadSkills
    ///
    /// 执行 `loadSkills` 相关逻辑。
    private func loadSkills() {
        let url = AppPaths.skillsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            skills = DefaultHeiNiuSkills.all()
            saveSkills()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            var loaded = try decoder.decode([HeiNiuSkill].self, from: data)

            // 对话模式不属于技能库
            loaded.removeAll {
                BuiltInChatModes.commands.contains($0.command.lowercased())
            }

            // 规范化 scope
            for i in loaded.indices {
                if loaded[i].isBuiltIn || loaded[i].scope == .builtIn {
                    loaded[i].scope = .builtIn
                    loaded[i].isBuiltIn = true
                } else {
                    loaded[i].scope = .personal
                    loaded[i].isBuiltIn = false
                }
            }

            if loaded.isEmpty {
                skills = DefaultHeiNiuSkills.all()
                saveSkills()
                return
            }

            // 补齐内置技能（按 command）
            let existing = Set(loaded.map { $0.command.lowercased() })
            for seed in DefaultHeiNiuSkills.all() where !existing.contains(seed.command.lowercased()) {
                loaded.append(seed)
            }
            // 内置技能命令与插件绑定校正
            for i in loaded.indices {
                if let seed = DefaultHeiNiuSkills.all().first(where: {
                    $0.command.lowercased() == loaded[i].command.lowercased()
                }) {
                    loaded[i].scope = .builtIn
                    loaded[i].isBuiltIn = true
                    if loaded[i].pluginID == nil {
                        loaded[i].pluginID = seed.pluginID
                    }
                }
            }
            skills = loaded
            syncPluginSkillCommands()
            saveSkills()
            savePlugins()
        } catch {
            skills = DefaultHeiNiuSkills.all()
        }
    }

    /// 用压缩摘要替换会话历史，降低上下文占用。
    ///
    /// 通常由 `/compress` 成功回调后调用。
    ///
    /// - Parameters:
    ///   - conversationID: 目标会话。
    ///   - summary: 模型生成的摘要。
    ///   - userRequestDisplay: 用户触发压缩时的展示文案。
    ///
    func replaceConversationWithSummary(
        conversationID: UUID,
        summary: String,
        userRequestDisplay: String
    ) {
        guard var conversation = conversation(id: conversationID) else { return }
        let stamp = Date()
        conversation.messages = [
            ChatTurn(
                role: .assistant,
                content: "【上下文已压缩】\n\n\(summary)",
                createdAt: stamp
            ),
        ]
        if !userRequestDisplay.isEmpty {
            // 用户触发压缩的那条也保留在摘要后，便于阅读
            conversation.messages.insert(
                ChatTurn(role: .user, content: userRequestDisplay, createdAt: stamp.addingTimeInterval(-1)),
                at: 0
            )
        }
        conversation.updatedAt = Date()
        updateConversation(conversation)
    }

    /// saveAgents
    ///
    /// 执行 `saveAgents` 相关逻辑。
    private func saveAgents() {
        AppPaths.ensureDirectories()
        if let data = try? encoder.encode(agents) {
            try? data.write(to: AppPaths.agentsFileURL, options: .atomic)
        }
    }

    /// saveConversations
    ///
    /// 执行 `saveConversations` 相关逻辑。
    private func saveConversations() {
        AppPaths.ensureDirectories()
        if let data = try? encoder.encode(conversations) {
            try? data.write(to: AppPaths.conversationsFileURL, options: .atomic)
        }
    }

    /// saveKnowledge
    ///
    /// 执行 `saveKnowledge` 相关逻辑。
    private func saveKnowledge() {
        AppPaths.ensureDirectories()
        if let data = try? encoder.encode(knowledgeItems) {
            try? data.write(to: AppPaths.knowledgeIndexFileURL, options: .atomic)
        }
    }

    /// saveSkills
    ///
    /// 执行 `saveSkills` 相关逻辑。
    private func saveSkills() {
        AppPaths.ensureDirectories()
        if let data = try? encoder.encode(skills) {
            try? data.write(to: AppPaths.skillsFileURL, options: .atomic)
        }
    }

    /// savePlugins
    ///
    /// 执行 `savePlugins` 相关逻辑。
    private func savePlugins() {
        AppPaths.ensureDirectories()
        if let data = try? encoder.encode(plugins) {
            try? data.write(to: AppPaths.pluginsFileURL, options: .atomic)
        }
    }

    /// seedMissingBuiltIns
    ///
    /// 执行 `seedMissingBuiltIns` 相关逻辑。
    @discardableResult
    private func seedMissingBuiltIns() -> Bool {
        var added = false
        let names = Set(agents.map(\.name))
        var order = (agents.map(\.sortOrder).max() ?? -1) + 1
        for seed in DefaultHeiNiuAgents.seed() where !names.contains(seed.name) {
            var item = seed
            item.sortOrder = order
            order += 1
            agents.append(item)
            added = true
        }
        return added
    }

    /// uniqueFileName
    ///
    /// 执行 `uniqueFileName` 相关逻辑。
    private func uniqueFileName(_ name: String, in directory: URL) -> String {
        let fm = FileManager.default
        var candidate = name.replacingOccurrences(of: "/", with: "-")
        let base = (candidate as NSString).deletingPathExtension
        let ext = (candidate as NSString).pathExtension
        var i = 1
        while fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            i += 1
        }
        return candidate
    }
}
