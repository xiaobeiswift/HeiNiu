/// LLM 客户端协议、错误与工厂。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// LLM 调用错误。
///
/// 用于聊天发送与连通性流程的用户可读失败原因。
///
/// ## 用例
///
/// | Case | 含义 |
/// |------|------|
/// | `missingAPIKey` | 钥匙串无 Key |
/// | `missingProvider` | 未绑定服务商 |
/// | `missingModel` | 模型为空 |
/// | `http` | HTTP 非 2xx |
/// | `emptyResponse` | 响应无文本 |
///
/// ```swift
/// do {
///     _ = try await client.complete(...)
/// } catch let error as LLMError {
///     print(error.errorDescription ?? "")
/// }
/// ```
///
enum LLMError: LocalizedError {
    /// missingAPIKey。
    case missingAPIKey
    /// missingProvider。
    case missingProvider
    /// missingModel。
    case missingModel
    /// invalidURL。
    case invalidURL
    /// http。
    case http(Int, String)
    /// emptyResponse。
    case emptyResponse
    /// decoding。
    case decoding
    /// underlying。
    case underlying(String)

    /// errorDescription。
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "请先配置 API Key"
        case .missingProvider: "请先为该黑妞绑定服务商"
        case .missingModel: "请先选择或填写模型"
        case .invalidURL: "Base URL 无效"
        case .http(let code, let body): "HTTP \(code)：\(body.prefix(240))"
        case .emptyResponse: "模型返回为空"
        case .decoding: "无法解析模型响应"
        case .underlying(let message): message
        }
    }
}

/// 发往模型的单条消息。
///
/// 与 UI 层 ``ChatTurn`` 分离，便于在发送前重写 system/user 内容。
///
struct LLMChatMessage: Hashable {
    /// Role
    ///
    /// `Role` 类型定义。
    enum Role: String {
        /// system。
        case system
        /// user。
        case user
        /// assistant。
        case assistant
    }

    /// 消息角色。
    var role: Role
    /// 消息正文。
    var content: String
}

/// 大模型补全客户端协议。
///
/// 实现方：``OpenAICompatibleClient``、``AnthropicClient``。
///
/// ```swift
/// let client = LLMClientFactory.make(for: provider)
/// let text = try await client.complete(
///     messages: [
///         .init(role: .system, content: "你是编剧"),
///         .init(role: .user, content: "写大纲")
///     ],
///     model: "gpt-4o",
///     temperature: 0.8,
///     apiKey: key
/// )
/// ```
///
/// - SeeAlso: ``LLMClientFactory``
///
protocol LLMClient: Sendable {
    /// 执行一次文本补全。
    ///
    /// - Parameters:
    ///   - messages: 对话消息（可含 system）。
    ///   - model: 模型 ID。
    ///   - temperature: 温度。
    ///   - apiKey: 明文 Key。
    /// - Returns: 助手文本。
    /// - Throws: ``LLMError`` 或传输错误。
    ///
    func complete(
        messages: [LLMChatMessage],
        model: String,
        temperature: Double,
        apiKey: String
    ) async throws -> String
}

/// 按 ``LLMProvider`` 创建具体客户端。
///
/// 根据 `protocolType` 与 `openAIAPIMode` 分支。
///
/// ```swift
/// let client = LLMClientFactory.make(for: provider)
/// ```
///
enum LLMClientFactory {
    /// 创建与服务商协议匹配的 ``LLMClient``。
    ///
    /// - Parameter provider: 服务商配置（含 Base URL 与模式）。
    /// - Returns: 可并发使用的客户端实例。
    ///
    static func make(for provider: LLMProvider) -> LLMClient {
        switch provider.protocolType {
        case .openAICompatible:
            return OpenAICompatibleClient(
                baseURL: provider.effectiveBaseURL,
                mode: provider.openAIAPIMode
            )
        case .anthropic:
            return AnthropicClient(baseURL: provider.effectiveBaseURL)
        }
    }
}
