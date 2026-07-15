/// OpenAI 兼容 Chat Completions / Responses 客户端。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// OpenAI 兼容 HTTP 客户端。
///
/// 支持：
///
/// - Chat Completions：`POST /chat/completions`
/// - Responses：`POST /responses`
///
/// 由 ``LLMClientFactory`` 在 `protocolType == openAICompatible` 时创建。
///
/// ## 设计原则
///
/// - 仅依赖 `URLSession`
/// - 不持久化任何密钥
/// - Responses 模式将 system 合并为 `instructions` 字段
///
struct OpenAICompatibleClient: LLMClient {
    /// API 根地址。
    let baseURL: String
    /// 模式。
    let mode: OpenAICompatibleAPIMode

    /// 发起补全请求并返回文本结果
    ///
    /// 发起补全请求并返回文本结果。
    func complete(
        messages: [LLMChatMessage],
        model: String,
        temperature: Double,
        apiKey: String
    ) async throws -> String {
        switch mode {
        case .chatCompletions:
            return try await chatCompletions(
                messages: messages,
                model: model,
                temperature: temperature,
                apiKey: apiKey
            )
        case .responses:
            return try await responses(
                messages: messages,
                model: model,
                temperature: temperature,
                apiKey: apiKey
            )
        }
    }

    /// chatCompletions
    ///
    /// 执行 `chatCompletions` 相关逻辑。
    private func chatCompletions(
        messages: [LLMChatMessage],
        model: String,
        temperature: Double,
        apiKey: String
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        /// payload。
        let payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.throwIfNeeded(data: data, response: response)

        /// ChatResponse
        ///
        /// `ChatResponse` 类型定义。
        struct ChatResponse: Decodable {
            /// Choice
            ///
            /// `Choice` 类型定义。
            struct Choice: Decodable {
                /// Message
                ///
                /// `Message` 类型定义。
                struct Message: Decodable { let content: String? }
                /// message。
                let message: Message?
            }
            /// choices。
            let choices: [Choice]?
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            throw LLMError.emptyResponse
        }
        return text
    }

    /// responses
    ///
    /// 执行 `responses` 相关逻辑。
    private func responses(
        messages: [LLMChatMessage],
        model: String,
        temperature: Double,
        apiKey: String
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/responses") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        // 简化：system 合并进 instructions，其余按 input 消息
        let systemText = messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")
        let input = messages
            .filter { $0.role != .system }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        var payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "input": input,
        ]
        if !systemText.isEmpty {
            payload["instructions"] = systemText
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.throwIfNeeded(data: data, response: response)

        if let text = Self.extractResponsesText(from: data) {
            return text
        }
        throw LLMError.emptyResponse
    }

    /// throwIfNeeded
    ///
    /// 执行 `throwIfNeeded` 相关逻辑。
    private static func throwIfNeeded(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.underlying("无效响应")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.http(http.statusCode, body)
        }
    }

    /// extractResponsesText
    ///
    /// 执行 `extractResponsesText` 相关逻辑。
    private static func extractResponsesText(from data: Data) -> String? {
        // 优先 output_text
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = obj["output_text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let output = obj["output"] as? [[String: Any]] {
                var parts: [String] = []
                for item in output {
                    if let content = item["content"] as? [[String: Any]] {
                        for c in content {
                            if let t = c["text"] as? String { parts.append(t) }
                        }
                    }
                }
                let joined = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty { return joined }
            }
        }
        return nil
    }
}
