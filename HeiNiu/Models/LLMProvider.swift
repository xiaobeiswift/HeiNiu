/// LLM 服务商与协议模型。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// LLM 接入协议类型。
///
/// - ``openAICompatible``: OpenAI 兼容 HTTP 接口（含多数国内网关）
/// - ``anthropic``: Anthropic Messages API
enum ProviderProtocolType: String, Codable, CaseIterable, Identifiable, Hashable {
    /// OpenAI 兼容协议（`/chat/completions` 或 `/responses`）。
    case openAICompatible
    /// Anthropic 官方 Messages 协议。
    case anthropic

    /// 稳定标识符。
    var id: String { rawValue }

    /// 界面显示名称。
    var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI 兼容"
        case .anthropic: "Anthropic"
        }
    }

    /// 该协议的默认 Base URL。
    var defaultBaseURL: String {
        switch self {
        case .openAICompatible: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        }
    }

    /// 新建服务商时的默认模型列表。
    var defaultModels: [String] {
        switch self {
        case .openAICompatible: ["gpt-4o", "gpt-4o-mini"]
        case .anthropic: ["claude-sonnet-4-20250514", "claude-haiku-4-20250414"]
        }
    }
}

/// OpenAI 兼容调用模式。
///
/// - ``chatCompletions``：`/chat/completions`（多数网关）
/// - ``responses``：`/responses`
///
enum OpenAICompatibleAPIMode: String, Codable, CaseIterable, Identifiable, Hashable {
    /// 经典 Chat Completions：`POST /chat/completions`。
    case chatCompletions
    /// 新版 Responses API：`POST /responses`。
    case responses

    /// 稳定标识符。
    var id: String { rawValue }

    /// 完整显示名。
    var displayName: String {
        switch self {
        case .chatCompletions: "Chat Completions"
        case .responses: "Responses"
        }
    }

    /// 徽章用简称。
    var shortName: String {
        switch self {
        case .chatCompletions: "Chat"
        case .responses: "Responses"
        }
    }

    /// 相对 Base URL 的路径。
    var endpointPath: String {
        switch self {
        case .chatCompletions: "/chat/completions"
        case .responses: "/responses"
        }
    }

    /// 设置页说明文案。
    var endpointHint: String {
        switch self {
        case .chatCompletions: "POST /chat/completions · 多数第三方兼容"
        case .responses: "POST /responses · OpenAI 新接口"
        }
    }
}

/// 一家 LLM 服务商配置。
///
/// 持久化在 `settings.json`；Key 在钥匙串。
///
/// ## 示例
///
/// ```swift
/// var p = LLMProvider(
///     name: "OpenAI",
///     protocolType: .openAICompatible,
///     openAIAPIMode: .responses,
///     models: ["gpt-4o"]
/// )
/// settings.addProvider(p)
/// settings.setAPIKey(secret, for: p.id)
/// ```
///
/// - SeeAlso: ``SettingsStore``, ``OpenAICompatibleAPIMode``, ``LLMClientFactory``
///
struct LLMProvider: Identifiable, Codable, Hashable {
    /// 唯一 ID（钥匙串账户与提示词绑定使用）。
    var id: UUID
    /// 显示名称。
    var name: String
    /// 协议类型。
    var protocolType: ProviderProtocolType
    /// OpenAI 兼容时的接口模式；Anthropic 时忽略。
    var openAIAPIMode: OpenAICompatibleAPIMode
    /// API 根地址。
    var baseURL: String
    /// 用户维护的模型 ID 列表。
    var models: [String]
    /// 是否支持视觉（多模态图片输入）。
    var supportsVision: Bool

    /// 创建服务商。
    /// - Parameters:
    ///   - id: 唯一 ID，默认自动生成。
    ///   - name: 显示名称。
    ///   - protocolType: 协议。
    ///   - openAIAPIMode: OpenAI 兼容模式，默认 Chat Completions。
    ///   - baseURL: 为空时使用协议默认地址。
    ///   - models: 为空时使用协议默认模型。
    ///   - supportsVision: 是否支持视觉。
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

    /// 去掉首尾空白与尾部 `/` 后的有效 Base URL。
    var effectiveBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return protocolType.defaultBaseURL }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    /// 列表徽章文案（OpenAI 兼容时带模式简称）。
    var protocolBadgeText: String {
        switch protocolType {
        case .openAICompatible:
            return "OpenAI · \(openAIAPIMode.shortName)"
        case .anthropic:
            return protocolType.displayName
        }
    }

    /// 容错解码：缺字段时使用安全默认值，避免冲掉用户配置。
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

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 唯一标识符。
        case id, name, protocolType, openAIAPIMode, baseURL, models, supportsVision
    }
}
