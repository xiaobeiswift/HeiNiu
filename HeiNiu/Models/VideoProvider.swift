/// 生视频服务商模型。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// VideoProviderKind
///
/// `VideoProviderKind` 类型定义。
enum VideoProviderKind: String, Codable, CaseIterable, Identifiable, Hashable {
    /// OpenAI 风格或兼容网关
    case openAICompatible
    /// 自定义 HTTP 端点（可填任意 Base URL / 模型名）
    case generic

    /// 唯一标识符。
    var id: String { rawValue }

    /// 对应源码适配器的稳定 ID。
    var adapterID: String {
        switch self {
        case .openAICompatible: VideoProvider.openAIAdapterID
        case .generic: VideoProvider.unconfiguredGenericAdapterID
        }
    }

    /// 界面显示名称。
    var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI 兼容"
        case .generic: "通用 HTTP"
        }
    }

    /// 接口说明文案。
    var endpointHint: String {
        switch self {
        case .openAICompatible: "视频生成兼容网关"
        case .generic: "自定义 API"
        }
    }

    /// 默认 Base URL。
    var defaultBaseURL: String {
        switch self {
        case .openAICompatible: "https://api.openai.com/v1"
        case .generic: ""
        }
    }

    /// 默认模型列表。
    var defaultModels: [String] {
        switch self {
        case .openAICompatible: ["sora-2", "sora-2-pro"]
        case .generic: []
        }
    }
}

/// 一家生视频服务商（可配置多家）
struct VideoProvider: Identifiable, Codable, Hashable {
    /// 内置 OpenAI Videos 源码适配器 ID。
    static let openAIAdapterID = "openai.videos.v1"
    /// 旧通用 HTTP 配置迁移后的占位 ID；实现适配器前不可执行。
    static let unconfiguredGenericAdapterID = "generic.unconfigured"
    /// 唯一标识符。
    var id: UUID
    /// 显示名称。
    var name: String
    /// 类型枚举。
    var kind: VideoProviderKind
    /// 执行请求时解析源码适配器的稳定 ID。
    var adapterID: String
    /// 由特定适配器解释的额外配置，不包含密钥。
    var adapterSettings: [String: String]
    /// API 根地址。
    var baseURL: String
    /// 模型 ID 列表。
    var models: [String]
    /// 如 9:16 / 16:9 / 1:1
    var defaultAspectRatio: String
    /// 默认时长（秒）
    var defaultDurationSeconds: Int

    static let availableAspectRatios = ["9:16", "16:9", "1:1"]
    static let availableDurations = [4, 8, 12, 16, 20]

    /// 初始化方法
    ///
    /// 初始化方法。
    init(
        id: UUID = UUID(),
        name: String,
        kind: VideoProviderKind = .openAICompatible,
        adapterID: String? = nil,
        adapterSettings: [String: String] = [:],
        baseURL: String? = nil,
        models: [String]? = nil,
        defaultAspectRatio: String = "9:16",
        defaultDurationSeconds: Int = 4
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.adapterID = adapterID ?? kind.adapterID
        self.adapterSettings = adapterSettings
        self.baseURL = baseURL ?? kind.defaultBaseURL
        self.models = models ?? kind.defaultModels
        self.defaultAspectRatio = defaultAspectRatio
        self.defaultDurationSeconds = defaultDurationSeconds
    }

    /// 规范化后的 Base URL。
    var effectiveBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return kind.defaultBaseURL }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    /// 初始化方法
    ///
    /// 初始化方法。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名生视频服务商"
        kind = try container.decodeIfPresent(VideoProviderKind.self, forKey: .kind) ?? .openAICompatible
        adapterID = try container.decodeIfPresent(String.self, forKey: .adapterID) ?? kind.adapterID
        adapterSettings = try container.decodeIfPresent([String: String].self, forKey: .adapterSettings) ?? [:]
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? kind.defaultBaseURL
        models = try container.decodeIfPresent([String].self, forKey: .models) ?? kind.defaultModels
        defaultAspectRatio = try container.decodeIfPresent(String.self, forKey: .defaultAspectRatio) ?? "9:16"
        defaultDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .defaultDurationSeconds) ?? 4
    }

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 唯一标识符。
        case id, name, kind, adapterID, adapterSettings, baseURL, models, defaultAspectRatio, defaultDurationSeconds
    }
}
