import Foundation

/// 导出/导入用的配置包（可含或不含 API Key）
struct SettingsBackup: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var appVersion: String
    var includeAPIKeys: Bool

    var providers: [LLMProvider]
    var promptItems: [PromptItem]
    var imageProviders: [ImageProvider]
    var videoProviders: [VideoProvider]

    /// Key 仅在 includeAPIKeys == true 时写入；键为 provider UUID 字符串
    var llmAPIKeys: [String: String]
    var imageAPIKeys: [String: String]
    var videoAPIKeys: [String: String]

    static let currentFormatVersion = 1

    init(
        formatVersion: Int = SettingsBackup.currentFormatVersion,
        exportedAt: Date = Date(),
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
        includeAPIKeys: Bool,
        providers: [LLMProvider],
        promptItems: [PromptItem],
        imageProviders: [ImageProvider],
        videoProviders: [VideoProvider],
        llmAPIKeys: [String: String] = [:],
        imageAPIKeys: [String: String] = [:],
        videoAPIKeys: [String: String] = [:]
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.includeAPIKeys = includeAPIKeys
        self.providers = providers
        self.promptItems = promptItems
        self.imageProviders = imageProviders
        self.videoProviders = videoProviders
        self.llmAPIKeys = llmAPIKeys
        self.imageAPIKeys = imageAPIKeys
        self.videoAPIKeys = videoAPIKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "1.0"
        includeAPIKeys = try container.decodeIfPresent(Bool.self, forKey: .includeAPIKeys) ?? false
        providers = try container.decodeIfPresent([LLMProvider].self, forKey: .providers) ?? []
        promptItems = try container.decodeIfPresent([PromptItem].self, forKey: .promptItems) ?? []
        imageProviders = try container.decodeIfPresent([ImageProvider].self, forKey: .imageProviders) ?? []
        videoProviders = try container.decodeIfPresent([VideoProvider].self, forKey: .videoProviders) ?? []
        llmAPIKeys = try container.decodeIfPresent([String: String].self, forKey: .llmAPIKeys) ?? [:]
        imageAPIKeys = try container.decodeIfPresent([String: String].self, forKey: .imageAPIKeys) ?? [:]
        videoAPIKeys = try container.decodeIfPresent([String: String].self, forKey: .videoAPIKeys) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt, appVersion, includeAPIKeys
        case providers, promptItems, imageProviders, videoProviders
        case llmAPIKeys, imageAPIKeys, videoAPIKeys
    }
}

enum SettingsImportMode: String, CaseIterable, Identifiable {
    /// 完全替换当前配置
    case replace
    /// 合并：同 ID 覆盖，新 ID 追加
    case merge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .replace: "替换全部"
        case .merge: "合并"
        }
    }

    var detail: String {
        switch self {
        case .replace: "用备份覆盖本机全部配置"
        case .merge: "保留本机已有项，按 ID 更新/追加备份内容"
        }
    }
}
