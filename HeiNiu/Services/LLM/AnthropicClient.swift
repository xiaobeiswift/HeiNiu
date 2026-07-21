/// Anthropic Messages API 客户端。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// Anthropic Messages API 客户端。
///
/// 请求 `POST {baseURL}/v1/messages`，使用 `x-api-key` 与 `anthropic-version` 头。
/// 支持扩展 thinking（`thinking` 块）与 SSE 流式输出。
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
        reasoningEffort: ReasoningEffort,
        apiKey: String
    ) async throws -> LLMCompletion {
        let request = try makeRequest(
            messages: messages,
            model: model,
            temperature: temperature,
            reasoningEffort: reasoningEffort,
            apiKey: apiKey,
            stream: false
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.throwIfNeeded(data: data, response: response)
        return try Self.parseMessage(data: data)
    }

    /// 流式补全（SSE event-stream）。
    func stream(
        messages: [LLMChatMessage],
        model: String,
        temperature: Double,
        reasoningEffort: ReasoningEffort,
        apiKey: String
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try makeRequest(
                        messages: messages,
                        model: model,
                        temperature: temperature,
                        reasoningEffort: reasoningEffort,
                        apiKey: apiKey,
                        stream: true
                    )
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try Self.throwIfNeeded(data: Data(), response: response, allowEmptyBody: true)

                    var sawAny = false
                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let payloadText = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payloadText == "[DONE]" { break }
                        guard let data = payloadText.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        let type = (obj["type"] as? String) ?? ""

                        if type == "error" {
                            let msg = ((obj["error"] as? [String: Any])?["message"] as? String) ?? "流式错误"
                            throw LLMError.underlying(msg)
                        }

                        // content_block_delta
                        if type == "content_block_delta" {
                            if let delta = obj["delta"] as? [String: Any] {
                                let dtype = (delta["type"] as? String) ?? ""
                                if dtype == "thinking_delta" || dtype == "reasoning_delta" {
                                    if let t = delta["thinking"] as? String ?? delta["text"] as? String,
                                       !t.isEmpty {
                                        continuation.yield(.reasoningDelta(t))
                                        sawAny = true
                                    }
                                } else if dtype == "text_delta" || delta["text"] != nil {
                                    if let t = delta["text"] as? String, !t.isEmpty {
                                        continuation.yield(.contentDelta(t))
                                        sawAny = true
                                    }
                                }
                            }
                            continue
                        }

                        // content_block_start：thinking 块
                        if type == "content_block_start" {
                            if let block = obj["content_block"] as? [String: Any] {
                                let btype = (block["type"] as? String) ?? ""
                                if btype == "thinking" {
                                    if let t = block["thinking"] as? String, !t.isEmpty {
                                        continuation.yield(.reasoningDelta(t))
                                        sawAny = true
                                    }
                                } else if btype == "text" {
                                    if let t = block["text"] as? String, !t.isEmpty {
                                        continuation.yield(.contentDelta(t))
                                        sawAny = true
                                    }
                                }
                            }
                        }
                    }

                    if !sawAny {
                        // 回退非流式
                        let fallback = try await complete(
                            messages: messages,
                            model: model,
                            temperature: temperature,
                            reasoningEffort: reasoningEffort,
                            apiKey: apiKey
                        )
                        if let r = fallback.reasoning, !r.isEmpty {
                            continuation.yield(.reasoningDelta(r))
                        }
                        if !fallback.content.isEmpty {
                            continuation.yield(.contentDelta(fallback.content))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Request

    private func makeRequest(
        messages: [LLMChatMessage],
        model: String,
        temperature: Double,
        reasoningEffort: ReasoningEffort,
        apiKey: String,
        stream: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        request.timeoutInterval = 300

        let system = messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")

        let chatMessages: [[String: Any]] = messages
            .filter { $0.role != .system }
            .map(Self.messagePayload)

        var payload: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "temperature": temperature,
            "messages": chatMessages,
        ]
        if stream {
            payload["stream"] = true
        }
        if !system.isEmpty {
            payload["system"] = system
        }

        // 扩展 thinking：按思考等级给 budget
        if let budget = Self.thinkingBudget(for: reasoningEffort) {
            payload["thinking"] = [
                "type": "enabled",
                "budget_tokens": budget,
            ]
            // Anthropic：启用 thinking 时 temperature 需为 1（部分版本）
            payload["temperature"] = 1
            // max_tokens 必须大于 budget
            payload["max_tokens"] = max(8192, budget + 4096)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    /// 把统一消息转换为 Anthropic 的文本或 `image` / `text` 内容块。
    static func messagePayload(_ message: LLMChatMessage) -> [String: Any] {
        let role = message.role == .assistant ? "assistant" : "user"
        guard !message.images.isEmpty else {
            return ["role": role, "content": message.content]
        }
        var blocks: [[String: Any]] = message.images.map { image in
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": image.mediaType,
                    "data": image.data.base64EncodedString(),
                ],
            ]
        }
        if !message.content.isEmpty {
            blocks.append(["type": "text", "text": message.content])
        }
        return ["role": role, "content": blocks]
    }

    private static func thinkingBudget(for effort: ReasoningEffort) -> Int? {
        switch effort {
        case .none: nil
        case .low: 2_048
        case .medium: 8_192
        case .high: 16_384
        }
    }

    // MARK: - Parse

    private static func parseMessage(data: Data) throws -> LLMCompletion {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decoding
        }
        let blocks = obj["content"] as? [[String: Any]] ?? []
        var contentParts: [String] = []
        var reasoningParts: [String] = []

        for block in blocks {
            let type = (block["type"] as? String) ?? ""
            if type == "thinking" {
                if let t = block["thinking"] as? String { reasoningParts.append(t) }
                else if let t = block["text"] as? String { reasoningParts.append(t) }
            } else if type == "text" {
                if let t = block["text"] as? String { contentParts.append(t) }
            } else if type == "reasoning" {
                if let t = block["text"] as? String ?? block["reasoning"] as? String {
                    reasoningParts.append(t)
                }
            }
        }

        let rawContent = contentParts.joined()
        let rawReasoning = reasoningParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let split = LLMReasoningExtractor.split(
            content: rawContent,
            reasoning: rawReasoning.isEmpty ? nil : rawReasoning
        )
        let completion = LLMCompletion.make(content: split.content, reasoning: split.reasoning)
        if completion.content.isEmpty && completion.reasoning == nil {
            throw LLMError.emptyResponse
        }
        if completion.content.isEmpty, let r = completion.reasoning {
            return LLMCompletion.make(content: r, reasoning: r)
        }
        return completion
    }

    private static func throwIfNeeded(
        data: Data,
        response: URLResponse,
        allowEmptyBody: Bool = false
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.underlying("无效响应")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.isEmpty && allowEmptyBody {
                throw LLMError.http(http.statusCode, "流式请求失败")
            }
            throw LLMError.http(http.statusCode, body)
        }
    }
}
