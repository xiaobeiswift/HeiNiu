import Foundation

enum ImageProviderKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case openAIImages

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAIImages: "OpenAI Images"
        }
    }

    var endpointHint: String {
        switch self {
        case .openAIImages: "POST /images/generations"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAIImages: "https://api.openai.com/v1"
        }
    }

    var defaultModels: [String] {
        switch self {
        case .openAIImages: ["gpt-image-1", "dall-e-3"]
        }
    }
}

/// 一家生图服务商（可配置多家）
struct ImageProvider: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: ImageProviderKind
    var baseURL: String
    var models: [String]
    var defaultSize: String

    static let availableSizes = ["1024x1024", "1024x1536", "1536x1024"]
    static let defaultSize = "1024x1024"

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

    var effectiveBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return kind.defaultBaseURL }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(models, forKey: .models)
        try container.encode(defaultSize, forKey: .defaultSize)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, baseURL, models, defaultSize, size
    }
}
