import Foundation

enum ProviderProtocolType: String, Codable, CaseIterable, Identifiable, Hashable {
    case openAICompatible
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI 兼容"
        case .anthropic: "Anthropic"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAICompatible: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        }
    }

    var defaultModels: [String] {
        switch self {
        case .openAICompatible: ["gpt-4o", "gpt-4o-mini"]
        case .anthropic: ["claude-sonnet-4-20250514", "claude-haiku-4-20250414"]
        }
    }
}

/// OpenAI 兼容接口的两种常见调用模式
enum OpenAICompatibleAPIMode: String, Codable, CaseIterable, Identifiable, Hashable {
    /// 经典 Chat Completions：POST /chat/completions
    case chatCompletions
    /// 新版 Responses API：POST /responses
    case responses

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chatCompletions: "Chat Completions"
        case .responses: "Responses"
        }
    }

    var shortName: String {
        switch self {
        case .chatCompletions: "Chat"
        case .responses: "Responses"
        }
    }

    var endpointPath: String {
        switch self {
        case .chatCompletions: "/chat/completions"
        case .responses: "/responses"
        }
    }

    var endpointHint: String {
        switch self {
        case .chatCompletions: "POST /chat/completions · 多数第三方兼容"
        case .responses: "POST /responses · OpenAI 新接口"
        }
    }
}

struct LLMProvider: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var protocolType: ProviderProtocolType
    /// 仅在 openAICompatible 时生效
    var openAIAPIMode: OpenAICompatibleAPIMode
    var baseURL: String
    var models: [String]
    var supportsVision: Bool

    init(
        id: UUID = UUID(),
        name: String,
        protocolType: ProviderProtocolType,
        openAIAPIMode: OpenAICompatibleAPIMode = .chatCompletions,
        baseURL: String? = nil,
        models: [String]? = nil,
        supportsVision: Bool = true
    ) {
        self.id = id
        self.name = name
        self.protocolType = protocolType
        self.openAIAPIMode = openAIAPIMode
        self.baseURL = baseURL ?? protocolType.defaultBaseURL
        self.models = models ?? protocolType.defaultModels
        self.supportsVision = supportsVision
    }

    var effectiveBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return protocolType.defaultBaseURL }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    /// 展示用协议标签（OpenAI 兼容时带上模式简称）
    var protocolBadgeText: String {
        switch protocolType {
        case .openAICompatible:
            return "OpenAI · \(openAIAPIMode.shortName)"
        case .anthropic:
            return protocolType.displayName
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名服务商"
        protocolType = try container.decodeIfPresent(ProviderProtocolType.self, forKey: .protocolType) ?? .openAICompatible
        openAIAPIMode = try container.decodeIfPresent(OpenAICompatibleAPIMode.self, forKey: .openAIAPIMode) ?? .chatCompletions
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? protocolType.defaultBaseURL
        models = try container.decodeIfPresent([String].self, forKey: .models) ?? protocolType.defaultModels
        supportsVision = try container.decodeIfPresent(Bool.self, forKey: .supportsVision) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, protocolType, openAIAPIMode, baseURL, models, supportsVision
    }
}
