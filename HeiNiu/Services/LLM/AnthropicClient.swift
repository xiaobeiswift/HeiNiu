/// Anthropic Messages API 客户端。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// Anthropic Messages API 客户端。
///
/// 请求 `POST {baseURL}/v1/messages`，使用 `x-api-key` 与 `anthropic-version` 头。
///
/// - SeeAlso: ``LLMClient``, ``LLMClientFactory``
///
struct AnthropicClient: LLMClient {
    /// API 根地址。
    let baseURL: String

    /// 发起补全请求并返回文本结果
    ///
    /// 发起补全请求并返回文本结果。
    func complete(
        messages: [LLMChatMessage],
        model: String,
        temperature: Double,
        apiKey: String
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let system = messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")

        /// chatMessages。
        let chatMessages: [[String: String]] = messages
            .filter { $0.role != .system }
            .map { msg in
                let role = msg.role == .assistant ? "assistant" : "user"
                return ["role": role, "content": msg.content]
            }

        var payload: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "temperature": temperature,
            "messages": chatMessages,
        ]
        if !system.isEmpty {
            payload["system"] = system
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.underlying("无效响应")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.http(http.statusCode, body)
        }

        /// AnthropicResponse
        ///
        /// `AnthropicResponse` 类型定义。
        struct AnthropicResponse: Decodable {
            /// Content
            ///
            /// `Content` 类型定义。
            struct Content: Decodable {
                /// type。
                let type: String?
                /// text。
                let text: String?
            }
            /// 消息正文。
            let content: [Content]?
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let text = decoded.content?
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else {
            throw LLMError.emptyResponse
        }
        return text
    }
}
