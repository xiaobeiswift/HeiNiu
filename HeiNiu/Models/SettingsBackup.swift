/// 设置备份包与导入模式。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// 导出/导入用的配置包（可含或不含 API Key）
struct SettingsBackup: Codable {
    /// 备份格式版本。
    var formatVersion: Int
    /// 导出时间。
    var exportedAt: Date
    /// 导出时应用版本。
    var appVersion: String
    /// 备份是否包含 API Key。
    var includeAPIKeys: Bool

    /// LLM 服务商列表
    ///
    /// LLM 服务商列表。
    var providers: [LLMProvider]
    /// 提示词库全部条目。
    var promptItems: [PromptItem]
    /// 生图服务商列表。
    var imageProviders: [ImageProvider]
    /// 生视频服务商列表。
    var videoProviders: [VideoProvider]
    /// Key 仅在 includeAPIKeys == true 时写入；键为 provider UUID 字符串
    var llmAPIKeys: [String: String]
    /// 生图 Key 字典。
    var imageAPIKeys: [String: String]
    /// 生视频 Key 字典。
    var videoAPIKeys: [String: String]

    static let currentFormatVersion = 1

    /// 初始化方法
    ///
    /// 初始化方法。
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

    /// 初始化方法
    ///
    /// 初始化方法。
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

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 备份格式版本。
        case formatVersion, exportedAt, appVersion, includeAPIKeys
        /// LLM 服务商列表
        ///
        /// LLM 服务商列表。
        case providers, promptItems, imageProviders, videoProviders
        /// LLM Key 字典。
        case llmAPIKeys, imageAPIKeys, videoAPIKeys
    }
}

/// SettingsImportMode
///
/// `SettingsImportMode` 类型定义。
enum SettingsImportMode: String, CaseIterable, Identifiable {
    /// 完全替换当前配置
    case replace
    /// 合并：同 ID 覆盖，新 ID 追加
    case merge

    /// 唯一标识符。
    var id: String { rawValue }

    /// 界面显示名称。
    var displayName: String {
        switch self {
        case .replace: "替换全部"
        case .merge: "合并"
        }
    }

    /// 详细说明。
    var detail: String {
        switch self {
        case .replace: "用备份覆盖本机全部配置"
        case .merge: "保留本机已有项，按 ID 更新/追加备份内容"
        }
    }
}
