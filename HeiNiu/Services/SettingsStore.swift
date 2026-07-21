/// 全局设置仓库：服务商、提示词与备份。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation
import Observation

/// 全局设置仓库。
///
/// 管理应用级配置与密钥访问入口：
///
/// | 数据 | 位置 |
/// |------|------|
/// | 服务商 / 提示词 | `settings.json` |
/// | API Key | 钥匙串（``KeychainHelper``） |
///
/// ## 设计原则
///
/// - **密钥永不入库**：JSON 不含 Key；删除服务商时同步删钥匙串。
/// - **容错解码**：缺字段给默认值，升级不冲配置。
/// - **模型拉取**：``fetchModels(for:)`` 解析 OpenAI 风格 `/models`。
///
/// ## 示例
///
/// ```swift
/// let settings = SettingsStore()
/// var provider = LLMProvider(name: "OpenAI", protocolType: .openAICompatible)
/// settings.addProvider(provider)
/// settings.setAPIKey("sk-xxx", for: provider.id)
///
/// if case .success(let models, let msg) = await settings.fetchModels(for: provider) {
///     provider.models = models
///     settings.updateProvider(provider)
///     print(msg)
/// }
/// ```
///
/// - SeeAlso: ``LLMProvider``；另见文档「SettingsAndProviders」「DataStorage」。
///
@Observable
@MainActor
final class SettingsStore {
    /// 已配置的 LLM 服务商。
    ///
    /// Key 不在此数组中；使用 ``apiKey(for:)`` / ``setAPIKey(_:for:)``。
    ///
    /// - SeeAlso: ``addProvider(_:)``, ``fetchModels(for:)``
    ///
    var providers: [LLMProvider] = []
    /// 知识库向量使用的 OpenAI 兼容服务商。
    var knowledgeEmbeddingProviderID: UUID?
    /// 知识库向量模型 ID。
    var knowledgeEmbeddingModel: String = ""
    /// 提示词库全部条目（多分类多条）。
    ///
    /// 按分类筛选请在 UI 层对 `category` 过滤。默认模板见 ``DefaultPrompts``。
    ///
    var promptItems: [PromptItem] = []
    /// 生图服务商列表。
    var imageProviders: [ImageProvider] = []
    /// 生视频服务商列表。
    var videoProviders: [VideoProvider] = []
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

    // MARK: - LLM Provider CRUD

    /// 追加 LLM 服务商并保存。
    ///
    /// - Parameter provider: 完整服务商配置（不含 Key）。
    ///
    func addProvider(_ provider: LLMProvider) {
        providers.append(provider)
        save()
    }

    /// 更新 LLM 服务商
    ///
    /// 更新 LLM 服务商。
    func updateProvider(_ provider: LLMProvider) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[index] = provider
        save()
    }

    /// 删除服务商、清理钥匙串，并断开提示词中的绑定。
    ///
    /// - Parameter id: 服务商 ID。
    /// - Note: 引用该服务商的 ``PromptItem/providerID`` 会被置空。
    ///
    func deleteProvider(id: UUID) {
        providers.removeAll { $0.id == id }
        if knowledgeEmbeddingProviderID == id {
            knowledgeEmbeddingProviderID = nil
            knowledgeEmbeddingModel = ""
        }
        KeychainHelper.delete(account: Self.llmKeyAccount(id))

        for index in promptItems.indices where promptItems[index].providerID == id {
            promptItems[index].providerID = nil
            promptItems[index].model = ""
            promptItems[index].updatedAt = Date()
        }
        save()
    }

    /// 更新知识库嵌入服务配置。
    func setKnowledgeEmbedding(providerID: UUID?, model: String) {
        knowledgeEmbeddingProviderID = providerID
        knowledgeEmbeddingModel = providerID == nil
            ? ""
            : model.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    /// 按 ID 查找 LLM 服务商
    ///
    /// 按 ID 查找 LLM 服务商。
    func provider(id: UUID?) -> LLMProvider? {
        guard let id else { return nil }
        return providers.first { $0.id == id }
    }

    // MARK: - Image Provider CRUD

    /// 添加生图服务商
    ///
    /// 添加生图服务商。
    func addImageProvider(_ provider: ImageProvider) {
        imageProviders.append(provider)
        save()
    }

    /// 更新生图服务商
    ///
    /// 更新生图服务商。
    func updateImageProvider(_ provider: ImageProvider) {
        guard let index = imageProviders.firstIndex(where: { $0.id == provider.id }) else { return }
        imageProviders[index] = provider
        save()
    }

    /// 删除生图服务商
    ///
    /// 删除生图服务商。
    func deleteImageProvider(id: UUID) {
        imageProviders.removeAll { $0.id == id }
        KeychainHelper.delete(account: Self.imageKeyAccount(id))
        save()
    }

    /// 按 ID 查找生图服务商
    ///
    /// 按 ID 查找生图服务商。
    func imageProvider(id: UUID?) -> ImageProvider? {
        guard let id else { return nil }
        return imageProviders.first { $0.id == id }
    }

    // MARK: - Video Provider CRUD

    /// 添加生视频服务商
    ///
    /// 添加生视频服务商。
    func addVideoProvider(_ provider: VideoProvider) {
        videoProviders.append(provider)
        save()
    }

    /// 更新生视频服务商
    ///
    /// 更新生视频服务商。
    func updateVideoProvider(_ provider: VideoProvider) {
        guard let index = videoProviders.firstIndex(where: { $0.id == provider.id }) else { return }
        videoProviders[index] = provider
        save()
    }

    /// 删除生视频服务商
    ///
    /// 删除生视频服务商。
    func deleteVideoProvider(id: UUID) {
        videoProviders.removeAll { $0.id == id }
        KeychainHelper.delete(account: Self.videoKeyAccount(id))
        save()
    }

    /// 按 ID 查找生视频服务商
    ///
    /// 按 ID 查找生视频服务商。
    func videoProvider(id: UUID?) -> VideoProvider? {
        guard let id else { return nil }
        return videoProviders.first { $0.id == id }
    }

    // MARK: - API Keys

    /// 读取 LLM API Key。
    ///
    /// - Returns: 明文 Key；未设置则为空字符串。
    ///
    func apiKey(for providerID: UUID) -> String {
        KeychainHelper.get(account: Self.llmKeyAccount(providerID)) ?? ""
    }

    /// 写入或清除 LLM API Key（钥匙串）。
    ///
    /// 空字符串表示删除。账户名：`provider-<uuid>`。
    ///
    func setAPIKey(_ key: String, for providerID: UUID) {
        setKey(key, account: Self.llmKeyAccount(providerID))
    }

    /// 读取/设置生图 API Key
    ///
    /// 读取/设置生图 API Key。
    func imageAPIKey(for providerID: UUID) -> String {
        KeychainHelper.get(account: Self.imageKeyAccount(providerID)) ?? ""
    }

    /// 写入生图服务商 API Key
    ///
    /// 写入生图服务商 API Key。
    func setImageAPIKey(_ key: String, for providerID: UUID) {
        setKey(key, account: Self.imageKeyAccount(providerID))
    }

    /// 读取/设置生视频 API Key
    ///
    /// 读取/设置生视频 API Key。
    func videoAPIKey(for providerID: UUID) -> String {
        KeychainHelper.get(account: Self.videoKeyAccount(providerID)) ?? ""
    }

    /// 写入生视频服务商 API Key
    ///
    /// 写入生视频服务商 API Key。
    func setVideoAPIKey(_ key: String, for providerID: UUID) {
        setKey(key, account: Self.videoKeyAccount(providerID))
    }

    // MARK: - Prompt library

    /// prompts
    ///
    /// 执行 `prompts` 相关逻辑。
    func prompts(in category: PromptCategory) -> [PromptItem] {
        promptItems
            .filter { $0.category == category }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// promptItem
    ///
    /// 执行 `promptItem` 相关逻辑。
    func promptItem(id: UUID?) -> PromptItem? {
        guard let id else { return nil }
        return promptItems.first { $0.id == id }
    }

    /// count
    ///
    /// 执行 `count` 相关逻辑。
    func count(in category: PromptCategory) -> Int {
        promptItems.filter { $0.category == category }.count
    }

    /// addPrompt
    ///
    /// 执行 `addPrompt` 相关逻辑。
    @discardableResult
    func addPrompt(in category: PromptCategory, name: String? = nil) -> PromptItem {
        let nextOrder = (prompts(in: category).map(\.sortOrder).max() ?? -1) + 1
        let item = PromptItem(
            category: category,
            name: name ?? "新提示词",
            template: DefaultPrompts.blankTemplate(for: category),
            isBuiltIn: false,
            sortOrder: nextOrder
        )
        promptItems.append(item)
        save()
        return item
    }

    /// updatePrompt
    ///
    /// 执行 `updatePrompt` 相关逻辑。
    func updatePrompt(_ item: PromptItem) {
        guard let index = promptItems.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.updatedAt = Date()
        promptItems[index] = updated
        save()
    }

    /// deletePrompt
    ///
    /// 执行 `deletePrompt` 相关逻辑。
    func deletePrompt(id: UUID) {
        promptItems.removeAll { $0.id == id }
        save()
    }

    /// duplicatePrompt
    ///
    /// 执行 `duplicatePrompt` 相关逻辑。
    @discardableResult
    func duplicatePrompt(id: UUID) -> PromptItem? {
        guard let source = promptItem(id: id) else { return nil }
        let nextOrder = (prompts(in: source.category).map(\.sortOrder).max() ?? -1) + 1
        var copy = source
        copy.id = UUID()
        copy.name = source.name + " 副本"
        copy.isBuiltIn = false
        copy.sortOrder = nextOrder
        copy.updatedAt = Date()
        promptItems.append(copy)
        save()
        return copy
    }

    /// resetPromptTemplate
    ///
    /// 执行 `resetPromptTemplate` 相关逻辑。
    func resetPromptTemplate(id: UUID) {
        guard let index = promptItems.firstIndex(where: { $0.id == id }) else { return }
        let item = promptItems[index]
        if let seed = DefaultPrompts.seedItems().first(where: {
            $0.category == item.category && $0.name == item.name
        }) {
            promptItems[index].template = seed.template
        } else {
            promptItems[index].template = DefaultPrompts.blankTemplate(for: item.category)
        }
        promptItems[index].updatedAt = Date()
        save()
    }

    // MARK: - Connection test

    /// 连通性测试结果。
    ///
    /// - `success`：可读提示文案  
    /// - `failure`：错误说明  
    ///
    enum ConnectionTestResult: Equatable {
        /// success。
        case success(String)
        /// failure。
        case failure(String)
    }

    /// 拉取模型列表结果。
    ///
    /// - `success([String], String)`：模型 ID 与状态文案  
    /// - `failure(String)`：错误说明  
    ///
    enum FetchModelsResult: Equatable {
        /// success。
        case success([String], String)
        /// failure。
        case failure(String)
    }

    /// 测试 LLM 服务商连通性。
    ///
    /// 成功时可能附带「可用模型约 N 个」提示。
    ///
    /// - Parameter provider: 目标服务商。
    /// - Returns: ``ConnectionTestResult``。
    ///
    func testConnection(for provider: LLMProvider) async -> ConnectionTestResult {
        let key = apiKey(for: provider.id)
        if key.isEmpty { return .failure("请先填写 API Key") }

        switch provider.protocolType {
        case .openAICompatible:
            return await testOpenAICompatible(baseURL: provider.effectiveBaseURL, apiKey: key)
        case .anthropic:
            return await testAnthropic(baseURL: provider.effectiveBaseURL, apiKey: key)
        }
    }

    /// 拉取服务商可用模型列表。
    ///
    /// OpenAI 兼容走 `GET {baseURL}/models`；Anthropic 尝试 `/v1/models`。
    ///
    /// - Parameter provider: 需已配置有效 Key。
    /// - Returns: ``FetchModelsResult``（模型 ID 去重排序）。
    ///
    /// ```swift
    /// switch await settings.fetchModels(for: provider) {
    /// case .success(let models, let message):
    ///     var p = provider; p.models = models; settings.updateProvider(p)
    /// case .failure(let err):
    ///     print(err)
    /// }
    /// ```
    ///
    /// - SeeAlso: 另有面向 ``ImageProvider`` / ``VideoProvider`` 的连通性测试。
    ///
    func fetchModels(for provider: LLMProvider) async -> FetchModelsResult {
        let key = apiKey(for: provider.id)
        if key.isEmpty { return .failure("请先填写 API Key") }

        switch provider.protocolType {
        case .openAICompatible:
            return await fetchOpenAICompatibleModels(baseURL: provider.effectiveBaseURL, apiKey: key)
        case .anthropic:
            return await fetchAnthropicModels(baseURL: provider.effectiveBaseURL, apiKey: key)
        }
    }

    /// 测试服务商连通性
    ///
    /// 测试服务商连通性。
    func testConnection(for provider: ImageProvider) async -> ConnectionTestResult {
        let key = imageAPIKey(for: provider.id)
        if key.isEmpty { return .failure("请先填写 API Key") }
        // Images 兼容网关通常也暴露 /models 或至少能鉴权
        return await testOpenAICompatible(baseURL: provider.effectiveBaseURL, apiKey: key)
    }

    /// 测试服务商连通性
    ///
    /// 测试服务商连通性。
    func testConnection(for provider: VideoProvider) async -> ConnectionTestResult {
        let key = videoAPIKey(for: provider.id)
        if key.isEmpty { return .failure("请先填写 API Key") }
        let base = provider.effectiveBaseURL
        if base.isEmpty { return .failure("请先填写 Base URL") }
        return await testOpenAICompatible(baseURL: base, apiKey: key)
    }

    // MARK: - Persistence

    /// 从磁盘加载持久化数据
    ///
    /// 从磁盘加载持久化数据。
    func load() {
        let url = AppPaths.settingsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            applyDefaults()
            save()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let persisted = try decoder.decode(PersistedSettings.self, from: data)
            providers = persisted.providers
            knowledgeEmbeddingProviderID = persisted.knowledgeEmbeddingProviderID
            knowledgeEmbeddingModel = persisted.knowledgeEmbeddingModel
            promptItems = persisted.promptItems
            imageProviders = persisted.imageProviders
            videoProviders = persisted.videoProviders
            var needsSave = false

            if promptItems.isEmpty {
                if let migrated = persisted.migratedFromLegacyPrompts, !migrated.isEmpty {
                    promptItems = migrated
                } else {
                    promptItems = DefaultPrompts.seedItems()
                }
                needsSave = true
            }

            // 补齐新增分类的预置提示词（如「物品」），不覆盖用户已有同名项
            if seedMissingBuiltInPrompts() {
                needsSave = true
            }

            // 旧版单条 imageGen → 一家 ImageProvider，并迁钥匙串
            if imageProviders.isEmpty, let legacy = persisted.legacyImageGen {
                let provider = ImageProvider(
                    name: "默认生图",
                    kind: legacy.kind,
                    baseURL: legacy.baseURL,
                    models: [legacy.model].filter { !$0.isEmpty },
                    defaultSize: legacy.size
                )
                imageProviders = [provider]
                if let oldKey = KeychainHelper.get(account: "image-provider"), !oldKey.isEmpty {
                    setImageAPIKey(oldKey, for: provider.id)
                    KeychainHelper.delete(account: "image-provider")
                }
                needsSave = true
            }

            if needsSave { save() }
        } catch {
            applyDefaults()
        }
    }

    /// 将当前状态写入磁盘
    ///
    /// 将当前状态写入磁盘。
    func save() {
        AppPaths.ensureDirectories()
        let persisted = PersistedSettings(
            providers: providers,
            promptItems: promptItems,
            imageProviders: imageProviders,
            videoProviders: videoProviders,
            knowledgeEmbeddingProviderID: knowledgeEmbeddingProviderID,
            knowledgeEmbeddingModel: knowledgeEmbeddingModel
        )
        do {
            let data = try encoder.encode(persisted)
            try data.write(to: AppPaths.settingsFileURL, options: .atomic)
        } catch {
            // ignore
        }
    }

    // MARK: - Backup (export / import)

    /// 本机配置文件路径（不含 Key）
    var localSettingsPath: String {
        AppPaths.settingsFileURL.path
    }

    /// 生成配置备份。
    ///
    /// - Parameter includeAPIKeys: 为兼容旧调用保留；新版备份始终不导出 Key。
    /// - Returns: ``SettingsBackup``。
    ///
    /// - SeeAlso: ``exportBackupData(includeAPIKeys:)``, ``importBackup(_:mode:importAPIKeys:)``
    ///
    func makeBackup(includeAPIKeys: Bool) -> SettingsBackup {
        return SettingsBackup(
            includeAPIKeys: false,
            providers: providers,
            knowledgeEmbeddingProviderID: knowledgeEmbeddingProviderID,
            knowledgeEmbeddingModel: knowledgeEmbeddingModel,
            promptItems: promptItems,
            imageProviders: imageProviders,
            videoProviders: videoProviders,
            llmAPIKeys: [:],
            imageAPIKeys: [:],
            videoAPIKeys: [:]
        )
    }

    /// 导出备份 JSON 数据
    ///
    /// 导出备份 JSON 数据。
    func exportBackupData(includeAPIKeys: Bool) throws -> Data {
        let backup = makeBackup(includeAPIKeys: includeAPIKeys)
        return try encoder.encode(backup)
    }

    /// 解码备份文件
    ///
    /// 解码备份文件。
    func decodeBackup(from data: Data) throws -> SettingsBackup {
        try decoder.decode(SettingsBackup.self, from: data)
    }

    /// 导入备份。
    ///
    /// - Parameters:
    ///   - backup: 备份数据。
    ///   - mode: 替换全部或按 ID 合并。
    ///   - importAPIKeys: 是否写入钥匙串中的 Key。
    ///
    /// 替换模式会清理旧服务商钥匙串项。
    ///
    func importBackup(_ backup: SettingsBackup, mode: SettingsImportMode, importAPIKeys: Bool) {
        switch mode {
        case .replace:
            // 清理旧 Key（避免孤儿钥匙串项）
            for provider in providers {
                KeychainHelper.delete(account: Self.llmKeyAccount(provider.id))
            }
            for provider in imageProviders {
                KeychainHelper.delete(account: Self.imageKeyAccount(provider.id))
            }
            for provider in videoProviders {
                KeychainHelper.delete(account: Self.videoKeyAccount(provider.id))
            }

            providers = backup.providers
            knowledgeEmbeddingProviderID = backup.knowledgeEmbeddingProviderID
            knowledgeEmbeddingModel = backup.knowledgeEmbeddingModel
            promptItems = backup.promptItems
            imageProviders = backup.imageProviders
            videoProviders = backup.videoProviders

            if importAPIKeys && backup.includeAPIKeys {
                applyAPIKeys(from: backup)
            }

        case .merge:
            mergeProviders(backup.providers, into: &providers)
            if backup.knowledgeEmbeddingProviderID != nil || !backup.knowledgeEmbeddingModel.isEmpty {
                knowledgeEmbeddingProviderID = backup.knowledgeEmbeddingProviderID
                knowledgeEmbeddingModel = backup.knowledgeEmbeddingModel
            }
            mergePromptItems(backup.promptItems)
            mergeProviders(backup.imageProviders, into: &imageProviders)
            mergeProviders(backup.videoProviders, into: &videoProviders)

            if importAPIKeys && backup.includeAPIKeys {
                applyAPIKeys(from: backup)
            }
        }
        _ = seedMissingBuiltInPrompts()
        save()
    }

    // MARK: - Private

    /// applyDefaults
    ///
    /// 执行 `applyDefaults` 相关逻辑。
    private func applyDefaults() {
        providers = []
        knowledgeEmbeddingProviderID = nil
        knowledgeEmbeddingModel = ""
        promptItems = DefaultPrompts.seedItems()
        imageProviders = []
        videoProviders = []
    }

    /// 返回是否写入了新项
    @discardableResult
    /// seedMissingBuiltInPrompts
    ///
    /// 执行 `seedMissingBuiltInPrompts` 相关逻辑。
    private func seedMissingBuiltInPrompts() -> Bool {
        var added = false
        let existing = Set(promptItems.map { "\($0.category.rawValue)|\($0.name)" })
        var nextOrder = (promptItems.map(\.sortOrder).max() ?? -1) + 1
        for seed in DefaultPrompts.seedItems() {
            let key = "\(seed.category.rawValue)|\(seed.name)"
            guard !existing.contains(key) else { continue }
            var item = seed
            item.sortOrder = nextOrder
            nextOrder += 1
            promptItems.append(item)
            added = true
        }
        return added
    }

    /// setKey
    ///
    /// 执行 `setKey` 相关逻辑。
    private func setKey(_ key: String, account: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainHelper.delete(account: account)
        } else {
            KeychainHelper.set(trimmed, account: account)
        }
    }

    /// applyAPIKeys
    ///
    /// 执行 `applyAPIKeys` 相关逻辑。
    private func applyAPIKeys(from backup: SettingsBackup) {
        for (idString, key) in backup.llmAPIKeys {
            guard let id = UUID(uuidString: idString), !key.isEmpty else { continue }
            setAPIKey(key, for: id)
        }
        for (idString, key) in backup.imageAPIKeys {
            guard let id = UUID(uuidString: idString), !key.isEmpty else { continue }
            setImageAPIKey(key, for: id)
        }
        for (idString, key) in backup.videoAPIKeys {
            guard let id = UUID(uuidString: idString), !key.isEmpty else { continue }
            setVideoAPIKey(key, for: id)
        }
    }

    /// mergeProviders
    ///
    /// 执行 `mergeProviders` 相关逻辑。
    private func mergeProviders<T: Identifiable>(_ incoming: [T], into existing: inout [T]) where T.ID == UUID {
        for item in incoming {
            if let index = existing.firstIndex(where: { $0.id == item.id }) {
                existing[index] = item
            } else {
                existing.append(item)
            }
        }
    }

    /// mergePromptItems
    ///
    /// 执行 `mergePromptItems` 相关逻辑。
    private func mergePromptItems(_ incoming: [PromptItem]) {
        for item in incoming {
            if let index = promptItems.firstIndex(where: { $0.id == item.id }) {
                promptItems[index] = item
            } else {
                promptItems.append(item)
            }
        }
    }

    /// llmKeyAccount
    ///
    /// 执行 `llmKeyAccount` 相关逻辑。
    private static func llmKeyAccount(_ id: UUID) -> String { "provider-\(id.uuidString)" }
    /// imageKeyAccount
    ///
    /// 执行 `imageKeyAccount` 相关逻辑。
    private static func imageKeyAccount(_ id: UUID) -> String { "image-provider-\(id.uuidString)" }
    /// videoKeyAccount
    ///
    /// 执行 `videoKeyAccount` 相关逻辑。
    private static func videoKeyAccount(_ id: UUID) -> String { "video-provider-\(id.uuidString)" }

    /// testOpenAICompatible
    ///
    /// 执行 `testOpenAICompatible` 相关逻辑。
    private func testOpenAICompatible(baseURL: String, apiKey: String) async -> ConnectionTestResult {
        switch await fetchOpenAICompatibleModels(baseURL: baseURL, apiKey: apiKey) {
        case .success(let models, _):
            return .success("连接成功，可用模型约 \(models.count) 个")
        case .failure(let message):
            // 兼容旧文案：404 仍算可达
            if message.contains("404") {
                return .success("端点可达（无 /models，请确认业务接口）")
            }
            return .failure(message)
        }
    }

    /// fetchOpenAICompatibleModels
    ///
    /// 执行 `fetchOpenAICompatibleModels` 相关逻辑。
    private func fetchOpenAICompatibleModels(baseURL: String, apiKey: String) async -> FetchModelsResult {
        guard let url = URL(string: "\(baseURL)/models") else {
            return .failure("Base URL 无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure("无效响应")
            }
            if (200...299).contains(http.statusCode) {
                let models = Self.parseOpenAIModelIDs(from: data)
                if models.isEmpty {
                    return .failure("已连接，但未解析到模型列表")
                }
                return .success(models, "已获取 \(models.count) 个模型")
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            return .failure("HTTP \(http.statusCode)：\(body.prefix(200))")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// fetchAnthropicModels
    ///
    /// 执行 `fetchAnthropicModels` 相关逻辑。
    private func fetchAnthropicModels(baseURL: String, apiKey: String) async -> FetchModelsResult {
        // 部分代理兼容 OpenAI /models；官方 Anthropic 也有 /v1/models
        if case .success(let models, let msg) = await fetchOpenAICompatibleModels(
            baseURL: baseURL.hasSuffix("/v1") ? baseURL : baseURL,
            apiKey: apiKey
        ), !models.isEmpty {
            return .success(models, msg)
        }

        guard let url = URL(string: "\(baseURL)/v1/models") else {
            return .failure("Base URL 无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure("无效响应")
            }
            if (200...299).contains(http.statusCode) {
                let models = Self.parseOpenAIModelIDs(from: data)
                if models.isEmpty {
                    return .failure("已连接，但未解析到模型列表")
                }
                return .success(models, "已获取 \(models.count) 个模型")
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            return .failure("HTTP \(http.statusCode)：\(body.prefix(200))")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// testAnthropic
    ///
    /// 执行 `testAnthropic` 相关逻辑。
    private func testAnthropic(baseURL: String, apiKey: String) async -> ConnectionTestResult {
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            return .failure("Base URL 无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        /// SwiftUI 视图内容。
        let body: [String: Any] = [
            "model": "claude-haiku-4-20250414",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure("无效响应")
            }
            if (200...299).contains(http.statusCode) {
                return .success("连接成功")
            }
            if http.statusCode == 400 {
                return .success("鉴权通过（请求参数被拒绝，但 API Key 可用）")
            }
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            return .failure("HTTP \(http.statusCode)：\(bodyText.prefix(200))")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// parseOpenAIModelIDs
    ///
    /// 执行 `parseOpenAIModelIDs` 相关逻辑。
    private static func parseOpenAIModelIDs(from data: Data) -> [String] {
        /// ModelsResponse
        ///
        /// `ModelsResponse` 类型定义。
        struct ModelsResponse: Decodable {
            /// Item
            ///
            /// `Item` 类型定义。
            struct Item: Decodable { let id: String }
            /// data。
            let data: [Item]?
        }
        let ids = (try? JSONDecoder().decode(ModelsResponse.self, from: data))?.data?.map(\.id) ?? []
        // 去重并稳定排序（忽略大小写）
        var seen = Set<String>()
        var unique: [String] = []
        for id in ids where !id.isEmpty {
            let key = id.lowercased()
            if seen.insert(key).inserted {
                unique.append(id)
            }
        }
        return unique.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}

// MARK: - Persisted shape

/// PersistedSettings
///
/// `PersistedSettings` 类型定义。
private struct PersistedSettings: Codable {
    /// LLM 服务商列表。
    var providers: [LLMProvider]
    var knowledgeEmbeddingProviderID: UUID?
    var knowledgeEmbeddingModel: String
    /// 提示词库全部条目。
    var promptItems: [PromptItem]
    /// 生图服务商列表。
    var imageProviders: [ImageProvider]
    /// 生视频服务商列表。
    var videoProviders: [VideoProvider]
    /// migratedFromLegacyPrompts。
    var migratedFromLegacyPrompts: [PromptItem]?
    /// legacyImageGen。
    var legacyImageGen: LegacyImageGen?

    /// 初始化方法
    ///
    /// 初始化方法。
    init(
        providers: [LLMProvider],
        promptItems: [PromptItem],
        imageProviders: [ImageProvider],
        videoProviders: [VideoProvider],
        knowledgeEmbeddingProviderID: UUID? = nil,
        knowledgeEmbeddingModel: String = ""
    ) {
        self.providers = providers
        self.promptItems = promptItems
        self.imageProviders = imageProviders
        self.videoProviders = videoProviders
        self.knowledgeEmbeddingProviderID = knowledgeEmbeddingProviderID
        self.knowledgeEmbeddingModel = knowledgeEmbeddingModel
        self.migratedFromLegacyPrompts = nil
        self.legacyImageGen = nil
    }

    /// 初始化方法
    ///
    /// 初始化方法。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providers = try container.decodeIfPresent([LLMProvider].self, forKey: .providers) ?? []
        knowledgeEmbeddingProviderID = try container.decodeIfPresent(UUID.self, forKey: .knowledgeEmbeddingProviderID)
        knowledgeEmbeddingModel = try container.decodeIfPresent(String.self, forKey: .knowledgeEmbeddingModel) ?? ""
        videoProviders = try container.decodeIfPresent([VideoProvider].self, forKey: .videoProviders) ?? []

        if let items = try container.decodeIfPresent([ImageProvider].self, forKey: .imageProviders) {
            imageProviders = items
            legacyImageGen = nil
        } else if let legacy = try container.decodeIfPresent(LegacyImageGen.self, forKey: .imageGen) {
            imageProviders = []
            legacyImageGen = legacy
        } else {
            imageProviders = []
            legacyImageGen = nil
        }

        if let items = try container.decodeIfPresent([PromptItem].self, forKey: .promptItems), !items.isEmpty {
            promptItems = items
            migratedFromLegacyPrompts = nil
        } else if let legacy = try container.decodeIfPresent([String: LegacyPromptConfig].self, forKey: .prompts) {
            promptItems = []
            migratedFromLegacyPrompts = Self.migrateLegacyPrompts(legacy)
        } else {
            promptItems = []
            migratedFromLegacyPrompts = nil
        }
    }

    /// encode
    ///
    /// 执行 `encode` 相关逻辑。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providers, forKey: .providers)
        try container.encodeIfPresent(knowledgeEmbeddingProviderID, forKey: .knowledgeEmbeddingProviderID)
        try container.encode(knowledgeEmbeddingModel, forKey: .knowledgeEmbeddingModel)
        try container.encode(promptItems, forKey: .promptItems)
        try container.encode(imageProviders, forKey: .imageProviders)
        try container.encode(videoProviders, forKey: .videoProviders)
    }

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// LLM 服务商列表
        ///
        /// LLM 服务商列表。
        case providers, promptItems, imageProviders, videoProviders, imageGen, prompts
        case knowledgeEmbeddingProviderID, knowledgeEmbeddingModel
    }

    /// migrateLegacyPrompts
    ///
    /// 执行 `migrateLegacyPrompts` 相关逻辑。
    private static func migrateLegacyPrompts(_ dict: [String: LegacyPromptConfig]) -> [PromptItem] {
        /// mapping。
        let mapping: [String: (PromptCategory, String)] = [
            "scriptCreation": (.script, "完整剧本"),
            "scriptConversion": (.script, "源文本改编"),
            "storyboard": (.storyboard, "分镜表"),
            "videoPrompt": (.video, "镜头视频提示词"),
            "characterExtract": (.character, "角色卡提取"),
            "sceneExtract": (.scene, "场景卡提取"),
        ]

        var items = DefaultPrompts.seedItems()
        for (key, legacy) in dict {
            guard let map = mapping[key] else { continue }
            if let index = items.firstIndex(where: { $0.category == map.0 && $0.name == map.1 }) {
                if !legacy.template.isEmpty {
                    items[index].template = legacy.template
                }
                items[index].providerID = legacy.providerID
                items[index].model = legacy.model
                items[index].temperature = legacy.temperature
            } else {
                items.append(
                    PromptItem(
                        category: map.0,
                        name: map.1,
                        template: legacy.template,
                        providerID: legacy.providerID,
                        model: legacy.model,
                        temperature: legacy.temperature,
                        isBuiltIn: false
                    )
                )
            }
        }
        return items
    }
}

/// LegacyImageGen
///
/// `LegacyImageGen` 类型定义。
private struct LegacyImageGen: Codable {
    /// 类型枚举。
    var kind: ImageProviderKind
    /// API 根地址。
    var baseURL: String
    /// 模型 ID。
    var model: String
    /// size。
    var size: String

    /// 初始化方法
    ///
    /// 初始化方法。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(ImageProviderKind.self, forKey: .kind) ?? .openAIImages
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? kind.defaultBaseURL
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? kind.defaultModels.first ?? "gpt-image-1"
        size = try container.decodeIfPresent(String.self, forKey: .size) ?? ImageProvider.defaultSize
    }

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 类型枚举。
        case kind, baseURL, model, size
    }
}

/// LegacyPromptConfig
///
/// `LegacyPromptConfig` 类型定义。
private struct LegacyPromptConfig: Codable {
    /// 模板正文。
    var template: String
    /// 绑定的服务商 ID。
    var providerID: UUID?
    /// 模型 ID。
    var model: String
    /// 采样温度。
    var temperature: Double

    /// 初始化方法
    ///
    /// 初始化方法。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        template = try container.decodeIfPresent(String.self, forKey: .template) ?? ""
        providerID = try container.decodeIfPresent(UUID.self, forKey: .providerID)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
    }

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 模板正文。
        case template, providerID, model, temperature
    }
}
