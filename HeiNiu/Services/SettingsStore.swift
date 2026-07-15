import Foundation
import Observation

@Observable
@MainActor
final class SettingsStore {
    var providers: [LLMProvider] = []
    var promptItems: [PromptItem] = []
    var imageProviders: [ImageProvider] = []
    var videoProviders: [VideoProvider] = []

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        AppPaths.ensureDirectories()
        load()
    }

    // MARK: - LLM Provider CRUD

    func addProvider(_ provider: LLMProvider) {
        providers.append(provider)
        save()
    }

    func updateProvider(_ provider: LLMProvider) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[index] = provider
        save()
    }

    func deleteProvider(id: UUID) {
        providers.removeAll { $0.id == id }
        KeychainHelper.delete(account: Self.llmKeyAccount(id))

        for index in promptItems.indices where promptItems[index].providerID == id {
            promptItems[index].providerID = nil
            promptItems[index].model = ""
            promptItems[index].updatedAt = Date()
        }
        save()
    }

    func provider(id: UUID?) -> LLMProvider? {
        guard let id else { return nil }
        return providers.first { $0.id == id }
    }

    // MARK: - Image Provider CRUD

    func addImageProvider(_ provider: ImageProvider) {
        imageProviders.append(provider)
        save()
    }

    func updateImageProvider(_ provider: ImageProvider) {
        guard let index = imageProviders.firstIndex(where: { $0.id == provider.id }) else { return }
        imageProviders[index] = provider
        save()
    }

    func deleteImageProvider(id: UUID) {
        imageProviders.removeAll { $0.id == id }
        KeychainHelper.delete(account: Self.imageKeyAccount(id))
        save()
    }

    func imageProvider(id: UUID?) -> ImageProvider? {
        guard let id else { return nil }
        return imageProviders.first { $0.id == id }
    }

    // MARK: - Video Provider CRUD

    func addVideoProvider(_ provider: VideoProvider) {
        videoProviders.append(provider)
        save()
    }

    func updateVideoProvider(_ provider: VideoProvider) {
        guard let index = videoProviders.firstIndex(where: { $0.id == provider.id }) else { return }
        videoProviders[index] = provider
        save()
    }

    func deleteVideoProvider(id: UUID) {
        videoProviders.removeAll { $0.id == id }
        KeychainHelper.delete(account: Self.videoKeyAccount(id))
        save()
    }

    func videoProvider(id: UUID?) -> VideoProvider? {
        guard let id else { return nil }
        return videoProviders.first { $0.id == id }
    }

    // MARK: - API Keys

    func apiKey(for providerID: UUID) -> String {
        KeychainHelper.get(account: Self.llmKeyAccount(providerID)) ?? ""
    }

    func setAPIKey(_ key: String, for providerID: UUID) {
        setKey(key, account: Self.llmKeyAccount(providerID))
    }

    func imageAPIKey(for providerID: UUID) -> String {
        KeychainHelper.get(account: Self.imageKeyAccount(providerID)) ?? ""
    }

    func setImageAPIKey(_ key: String, for providerID: UUID) {
        setKey(key, account: Self.imageKeyAccount(providerID))
    }

    func videoAPIKey(for providerID: UUID) -> String {
        KeychainHelper.get(account: Self.videoKeyAccount(providerID)) ?? ""
    }

    func setVideoAPIKey(_ key: String, for providerID: UUID) {
        setKey(key, account: Self.videoKeyAccount(providerID))
    }

    // MARK: - Prompt library

    func prompts(in category: PromptCategory) -> [PromptItem] {
        promptItems
            .filter { $0.category == category }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    func promptItem(id: UUID?) -> PromptItem? {
        guard let id else { return nil }
        return promptItems.first { $0.id == id }
    }

    func count(in category: PromptCategory) -> Int {
        promptItems.filter { $0.category == category }.count
    }

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

    func updatePrompt(_ item: PromptItem) {
        guard let index = promptItems.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.updatedAt = Date()
        promptItems[index] = updated
        save()
    }

    func deletePrompt(id: UUID) {
        promptItems.removeAll { $0.id == id }
        save()
    }

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

    enum ConnectionTestResult: Equatable {
        case success(String)
        case failure(String)
    }

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

    func testConnection(for provider: ImageProvider) async -> ConnectionTestResult {
        let key = imageAPIKey(for: provider.id)
        if key.isEmpty { return .failure("请先填写 API Key") }
        // Images 兼容网关通常也暴露 /models 或至少能鉴权
        return await testOpenAICompatible(baseURL: provider.effectiveBaseURL, apiKey: key)
    }

    func testConnection(for provider: VideoProvider) async -> ConnectionTestResult {
        let key = videoAPIKey(for: provider.id)
        if key.isEmpty { return .failure("请先填写 API Key") }
        let base = provider.effectiveBaseURL
        if base.isEmpty { return .failure("请先填写 Base URL") }
        return await testOpenAICompatible(baseURL: base, apiKey: key)
    }

    // MARK: - Persistence

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

    func save() {
        AppPaths.ensureDirectories()
        let persisted = PersistedSettings(
            providers: providers,
            promptItems: promptItems,
            imageProviders: imageProviders,
            videoProviders: videoProviders
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

    func makeBackup(includeAPIKeys: Bool) -> SettingsBackup {
        var llmKeys: [String: String] = [:]
        var imageKeys: [String: String] = [:]
        var videoKeys: [String: String] = [:]

        if includeAPIKeys {
            for provider in providers {
                let key = apiKey(for: provider.id)
                if !key.isEmpty {
                    llmKeys[provider.id.uuidString] = key
                }
            }
            for provider in imageProviders {
                let key = imageAPIKey(for: provider.id)
                if !key.isEmpty {
                    imageKeys[provider.id.uuidString] = key
                }
            }
            for provider in videoProviders {
                let key = videoAPIKey(for: provider.id)
                if !key.isEmpty {
                    videoKeys[provider.id.uuidString] = key
                }
            }
        }

        return SettingsBackup(
            includeAPIKeys: includeAPIKeys,
            providers: providers,
            promptItems: promptItems,
            imageProviders: imageProviders,
            videoProviders: videoProviders,
            llmAPIKeys: llmKeys,
            imageAPIKeys: imageKeys,
            videoAPIKeys: videoKeys
        )
    }

    func exportBackupData(includeAPIKeys: Bool) throws -> Data {
        let backup = makeBackup(includeAPIKeys: includeAPIKeys)
        return try encoder.encode(backup)
    }

    func decodeBackup(from data: Data) throws -> SettingsBackup {
        try decoder.decode(SettingsBackup.self, from: data)
    }

    /// 将备份应用到本机
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
            promptItems = backup.promptItems
            imageProviders = backup.imageProviders
            videoProviders = backup.videoProviders

            if importAPIKeys && backup.includeAPIKeys {
                applyAPIKeys(from: backup)
            }

        case .merge:
            mergeProviders(backup.providers, into: &providers)
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

    private func applyDefaults() {
        providers = []
        promptItems = DefaultPrompts.seedItems()
        imageProviders = []
        videoProviders = []
    }

    /// 返回是否写入了新项
    @discardableResult
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

    private func setKey(_ key: String, account: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainHelper.delete(account: account)
        } else {
            KeychainHelper.set(trimmed, account: account)
        }
    }

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

    private func mergeProviders<T: Identifiable>(_ incoming: [T], into existing: inout [T]) where T.ID == UUID {
        for item in incoming {
            if let index = existing.firstIndex(where: { $0.id == item.id }) {
                existing[index] = item
            } else {
                existing.append(item)
            }
        }
    }

    private func mergePromptItems(_ incoming: [PromptItem]) {
        for item in incoming {
            if let index = promptItems.firstIndex(where: { $0.id == item.id }) {
                promptItems[index] = item
            } else {
                promptItems.append(item)
            }
        }
    }

    private static func llmKeyAccount(_ id: UUID) -> String { "provider-\(id.uuidString)" }
    private static func imageKeyAccount(_ id: UUID) -> String { "image-provider-\(id.uuidString)" }
    private static func videoKeyAccount(_ id: UUID) -> String { "video-provider-\(id.uuidString)" }

    private func testOpenAICompatible(baseURL: String, apiKey: String) async -> ConnectionTestResult {
        guard let url = URL(string: "\(baseURL)/models") else {
            return .failure("Base URL 无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure("无效响应")
            }
            if (200...299).contains(http.statusCode) {
                let count = Self.parseOpenAIModelCount(from: data)
                if let count {
                    return .success("连接成功，可用模型约 \(count) 个")
                }
                return .success("连接成功")
            }
            // 部分视频网关没有 /models，404 但 Key 可能仍有效
            if http.statusCode == 404 {
                return .success("端点可达（无 /models，请确认业务接口）")
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            return .failure("HTTP \(http.statusCode)：\(body.prefix(200))")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

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

    private static func parseOpenAIModelCount(from data: Data) -> Int? {
        struct ModelsResponse: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]?
        }
        return try? JSONDecoder().decode(ModelsResponse.self, from: data).data?.count
    }
}

// MARK: - Persisted shape

private struct PersistedSettings: Codable {
    var providers: [LLMProvider]
    var promptItems: [PromptItem]
    var imageProviders: [ImageProvider]
    var videoProviders: [VideoProvider]

    var migratedFromLegacyPrompts: [PromptItem]?
    var legacyImageGen: LegacyImageGen?

    init(
        providers: [LLMProvider],
        promptItems: [PromptItem],
        imageProviders: [ImageProvider],
        videoProviders: [VideoProvider]
    ) {
        self.providers = providers
        self.promptItems = promptItems
        self.imageProviders = imageProviders
        self.videoProviders = videoProviders
        self.migratedFromLegacyPrompts = nil
        self.legacyImageGen = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providers = try container.decodeIfPresent([LLMProvider].self, forKey: .providers) ?? []
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providers, forKey: .providers)
        try container.encode(promptItems, forKey: .promptItems)
        try container.encode(imageProviders, forKey: .imageProviders)
        try container.encode(videoProviders, forKey: .videoProviders)
    }

    private enum CodingKeys: String, CodingKey {
        case providers, promptItems, imageProviders, videoProviders, imageGen, prompts
    }

    private static func migrateLegacyPrompts(_ dict: [String: LegacyPromptConfig]) -> [PromptItem] {
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

private struct LegacyImageGen: Codable {
    var kind: ImageProviderKind
    var baseURL: String
    var model: String
    var size: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(ImageProviderKind.self, forKey: .kind) ?? .openAIImages
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? kind.defaultBaseURL
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? kind.defaultModels.first ?? "gpt-image-1"
        size = try container.decodeIfPresent(String.self, forKey: .size) ?? ImageProvider.defaultSize
    }

    private enum CodingKeys: String, CodingKey {
        case kind, baseURL, model, size
    }
}

private struct LegacyPromptConfig: Codable {
    var template: String
    var providerID: UUID?
    var model: String
    var temperature: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        template = try container.decodeIfPresent(String.self, forKey: .template) ?? ""
        providerID = try container.decodeIfPresent(UUID.self, forKey: .providerID)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
    }

    private enum CodingKeys: String, CodingKey {
        case template, providerID, model, temperature
    }
}
