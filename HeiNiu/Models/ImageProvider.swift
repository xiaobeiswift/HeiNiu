/// 生图服务商模型。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// ImageProviderKind
///
/// `ImageProviderKind` 类型定义。
enum ImageProviderKind: String, Codable, CaseIterable, Identifiable, Hashable {
    /// openAIImages。
    case openAIImages

    /// 唯一标识符。
    var id: String { rawValue }

    /// 界面显示名称。
    var displayName: String {
        switch self {
        case .openAIImages: "OpenAI Images"
        }
    }

    /// 接口说明文案。
    var endpointHint: String {
        switch self {
        case .openAIImages: "POST /images/generations"
        }
    }

    /// 默认 Base URL。
    var defaultBaseURL: String {
        switch self {
        case .openAIImages: "https://api.openai.com/v1"
        }
    }

    /// 默认模型列表。
    var defaultModels: [String] {
        switch self {
        case .openAIImages: ["gpt-image-1", "dall-e-3"]
        }
    }
}

/// 一家生图服务商（可配置多家）
struct ImageProvider: Identifiable, Codable, Hashable {
    /// 唯一标识符。
    var id: UUID
    /// 显示名称。
    var name: String
    /// 类型枚举。
    var kind: ImageProviderKind
    /// API 根地址。
    var baseURL: String
    /// 模型 ID 列表。
    var models: [String]
    /// 默认图片尺寸。
    var defaultSize: String

    static let availableSizes = ["1024x1024", "1024x1536", "1536x1024"]
    static let defaultSize = "1024x1024"

    /// 初始化方法
    ///
    /// 初始化方法。
    init(
        id: UUID = UUID(),
        name: String,
        kind: ImageProviderKind = .openAIImages,
        baseURL: String? = nil,
        models: [String]? = nil,
        defaultSize: String = ImageProvider.defaultSize
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL ?? kind.defaultBaseURL
        self.models = models ?? kind.defaultModels
        self.defaultSize = defaultSize
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
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名生图服务商"
        kind = try container.decodeIfPresent(ImageProviderKind.self, forKey: .kind) ?? .openAIImages
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? kind.defaultBaseURL
        models = try container.decodeIfPresent([String].self, forKey: .models) ?? kind.defaultModels
        // 兼容旧字段 size
        if let size = try container.decodeIfPresent(String.self, forKey: .defaultSize) {
            defaultSize = size
        } else if let size = try container.decodeIfPresent(String.self, forKey: .size) {
            defaultSize = size
        } else {
            defaultSize = Self.defaultSize
        }
    }

    /// encode
    ///
    /// 执行 `encode` 相关逻辑。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(models, forKey: .models)
        try container.encode(defaultSize, forKey: .defaultSize)
    }

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 唯一标识符。
        case id, name, kind, baseURL, models, defaultSize, size
    }
}
