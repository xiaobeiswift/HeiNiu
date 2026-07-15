import Foundation

enum VideoProviderKind: String, Codable, CaseIterable, Identifiable, Hashable {
    /// OpenAI 风格或兼容网关
    case openAICompatible
    /// 自定义 HTTP 端点（可填任意 Base URL / 模型名）
    case generic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI 兼容"
        case .generic: "通用 HTTP"
        }
    }

    var endpointHint: String {
        switch self {
        case .openAICompatible: "视频生成兼容网关"
        case .generic: "自定义 API"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAICompatible: "https://api.openai.com/v1"
        case .generic: ""
        }
    }

    var defaultModels: [String] {
        switch self {
        case .openAICompatible: ["sora-2", "sora-2-pro"]
        case .generic: []
        }
    }
}

/// 一家生视频服务商（可配置多家）
struct VideoProvider: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: VideoProviderKind
    var baseURL: String
    var models: [String]
    /// 如 9:16 / 16:9 / 1:1
    var defaultAspectRatio: String
    /// 默认时长（秒）
    var defaultDurationSeconds: Int

    static let availableAspectRatios = ["9:16", "16:9", "1:1"]
    static let availableDurations = [4, 5, 8, 10, 12, 15]

    init(
        id: UUID = UUID(),
        name: String,
        kind: VideoProviderKind = .openAICompatible,
        baseURL: String? = nil,
        models: [String]? = nil,
        defaultAspectRatio: String = "9:16",
        defaultDurationSeconds: Int = 5
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL ?? kind.defaultBaseURL
        self.models = models ?? kind.defaultModels
        self.defaultAspectRatio = defaultAspectRatio
        self.defaultDurationSeconds = defaultDurationSeconds
    }

    var effectiveBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return kind.defaultBaseURL }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名生视频服务商"
        kind = try container.decodeIfPresent(VideoProviderKind.self, forKey: .kind) ?? .openAICompatible
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? kind.defaultBaseURL
        models = try container.decodeIfPresent([String].self, forKey: .models) ?? kind.defaultModels
        defaultAspectRatio = try container.decodeIfPresent(String.self, forKey: .defaultAspectRatio) ?? "9:16"
        defaultDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .defaultDurationSeconds) ?? 5
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, baseURL, models, defaultAspectRatio, defaultDurationSeconds
    }
}
