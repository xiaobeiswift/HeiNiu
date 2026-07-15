/// OpenAI 兼容 Chat Completions / Responses 客户端。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// OpenAI 兼容 HTTP 客户端。
///
/// 支持：
///
/// - Chat Completions：`POST /chat/completions`（含 `stream: true` SSE）
/// - Responses：`POST /responses`（含流式 SSE）
///
/// 会解析多种思考字段：`reasoning_content` / `reasoning` / `thinking`，
/// 以及正文中的 `<think>` 标签。
///
/// 由 ``LLMClientFactory`` 在 `protocolType == openAICompatible` 时创建。
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
        reasoningEffort: ReasoningEffort,
        apiKey: String
    ) async throws -> LLMCompletion {
        switch mode {
        case .chatCompletions:
            return try await chatCompletions(
                messages: messages,
                model: model,
                temperature: temperature,
                reasoningEffort: reasoningEffort,
                apiKey: apiKey,
                stream: false
            )
        case .responses:
            return try await responses(
                messages: messages,
                model: model,
                temperature: temperature,
                reasoningEffort: reasoningEffort,
                apiKey: apiKey,
                stream: false
            )
        }
    }

    /// 流式补全（SSE）。
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
                    switch mode {
                    case .chatCompletions:
                        try await streamChatCompletions(
                            messages: messages,
                            model: model,
                            temperature: temperature,
                            reasoningEffort: reasoningEffort,
                            apiKey: apiKey,
                            continuation: continuation
                        )
                    case .responses:
                        try await streamResponses(
                            messages: messages,
                            model: model,
                            temperature: temperature,
                            reasoningEffort: reasoningEffort,
                            apiKey: apiKey,
                            continuation: continuation
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Chat Completions

    private func chatCompletions(
        messages: [LLMChatMessage],
        model: String,
        temperature: Double,
        reasoningEffort: ReasoningEffort,
        apiKey: String,
        stream: Bool
    ) async throws -> LLMCompletion {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        var payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        if stream {
            payload["stream"] = true
        }
        // 部分兼容网关/o 系列支持 reasoning_effort
        if let effort = reasoningEffort.apiValue {
            payload["reasoning_effort"] = effort
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.throwIfNeeded(data: data, response: response)

        return try Self.parseChatCompletion(data: data)
    }

    private func streamChatCompletions(
        messages: [LLMChatMessage],
        model: String,
        temperature: Double,
        reasoningEffort: ReasoningEffort,
        apiKey: String,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300

        var payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "stream": true,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        if let effort = reasoningEffort.apiValue {
            payload["reasoning_effort"] = effort
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try Self.throwIfNeeded(data: Data(), response: response, allowEmptyBody: true)

        var contentParts: [String] = []
        var reasoningParts: [String] = []
        var sawAny = false

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payloadText = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payloadText == "[DONE]" { break }
            guard let data = payloadText.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // 错误帧
            if let err = obj["error"] as? [String: Any] {
                let msg = (err["message"] as? String) ?? "流式错误"
                throw LLMError.underlying(msg)
            }

            let choices = obj["choices"] as? [[String: Any]] ?? []
            for choice in choices {
                let delta = (choice["delta"] as? [String: Any])
                    ?? (choice["message"] as? [String: Any])
                    ?? [:]

                if let r = Self.extractReasoningText(from: delta), !r.isEmpty {
                    reasoningParts.append(r)
                    continuation.yield(.reasoningDelta(r))
                    sawAny = true
                }
                if let c = Self.extractContentText(from: delta), !c.isEmpty {
                    contentParts.append(c)
                    continuation.yield(.contentDelta(c))
                    sawAny = true
                }
            }
        }

        // 若流式未产出任何文本，回退非流式（部分网关假支持 stream）
        if !sawAny {
            let fallback = try await chatCompletions(
                messages: messages,
                model: model,
                temperature: temperature,
                reasoningEffort: reasoningEffort,
                apiKey: apiKey,
                stream: false
            )
            if let r = fallback.reasoning, !r.isEmpty {
                continuation.yield(.reasoningDelta(r))
            }
            if !fallback.content.isEmpty {
                continuation.yield(.contentDelta(fallback.content))
            }
            return
        }

        // 流结束后若正文里仍带 <think>，补一次拆分提示（UI 侧也会再拆）
        _ = contentParts
        _ = reasoningParts
    }

    // MARK: - Responses

    private func responses(
        messages: [LLMChatMessage],
        model: String,
        temperature: Double,
        reasoningEffort: ReasoningEffort,
        apiKey: String,
        stream: Bool
    ) async throws -> LLMCompletion {
        guard let url = URL(string: "\(baseURL)/responses") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

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
        if stream {
            payload["stream"] = true
        }
        if !systemText.isEmpty {
            payload["instructions"] = systemText
        }
        // Responses / 推理模型常用 reasoning.effort；尽量请求可见摘要
        if let effort = reasoningEffort.apiValue {
            payload["reasoning"] = [
                "effort": effort,
                "summary": "auto",
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.throwIfNeeded(data: data, response: response)

        if let completion = Self.extractResponsesCompletion(from: data) {
            return completion
        }
        throw LLMError.emptyResponse
    }

    private func streamResponses(
        messages: [LLMChatMessage],
        model: String,
        temperature: Double,
        reasoningEffort: ReasoningEffort,
        apiKey: String,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        guard let url = URL(string: "\(baseURL)/responses") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300

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
            "stream": true,
            "input": input,
        ]
        if !systemText.isEmpty {
            payload["instructions"] = systemText
        }
        if let effort = reasoningEffort.apiValue {
            payload["reasoning"] = [
                "effort": effort,
                "summary": "auto",
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

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

            if let err = obj["error"] as? [String: Any] {
                let msg = (err["message"] as? String) ?? "流式错误"
                throw LLMError.underlying(msg)
            }

            let type = (obj["type"] as? String) ?? ""

            // 文本增量
            if type.contains("output_text.delta") || type == "response.output_text.delta" {
                if let delta = obj["delta"] as? String, !delta.isEmpty {
                    continuation.yield(.contentDelta(delta))
                    sawAny = true
                } else if let text = obj["text"] as? String, !text.isEmpty {
                    continuation.yield(.contentDelta(text))
                    sawAny = true
                }
                continue
            }

            // 思考 / reasoning 摘要增量
            if type.contains("reasoning") && (type.contains("delta") || type.contains("summary")) {
                if let delta = obj["delta"] as? String, !delta.isEmpty {
                    continuation.yield(.reasoningDelta(delta))
                    sawAny = true
                } else if let text = obj["text"] as? String, !text.isEmpty {
                    continuation.yield(.reasoningDelta(text))
                    sawAny = true
                } else if let summary = obj["summary"] as? [[String: Any]] {
                    let joined = summary.compactMap { $0["text"] as? String }.joined()
                    if !joined.isEmpty {
                        continuation.yield(.reasoningDelta(joined))
                        sawAny = true
                    }
                }
                continue
            }

            // 完整 output 项
            if type == "response.output_item.done" || type == "response.completed" {
                if let item = obj["item"] as? [String: Any] {
                    Self.emitResponsesItem(item, continuation: continuation, sawAny: &sawAny)
                }
                if let responseObj = obj["response"] as? [String: Any],
                   let output = responseObj["output"] as? [[String: Any]] {
                    for item in output {
                        Self.emitResponsesItem(item, continuation: continuation, sawAny: &sawAny)
                    }
                }
            }
        }

        if !sawAny {
            let fallback = try await responses(
                messages: messages,
                model: model,
                temperature: temperature,
                reasoningEffort: reasoningEffort,
                apiKey: apiKey,
                stream: false
            )
            if let r = fallback.reasoning, !r.isEmpty {
                continuation.yield(.reasoningDelta(r))
            }
            if !fallback.content.isEmpty {
                continuation.yield(.contentDelta(fallback.content))
            }
        }
    }

    // MARK: - Parsing helpers

    private static func parseChatCompletion(data: Data) throws -> LLMCompletion {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decoding
        }
        let choices = obj["choices"] as? [[String: Any]] ?? []
        guard let first = choices.first else { throw LLMError.emptyResponse }

        let message = (first["message"] as? [String: Any])
            ?? (first["delta"] as? [String: Any])
            ?? [:]

        let rawContent = extractContentText(from: message) ?? ""
        let rawReasoning = extractReasoningText(from: message)
            ?? LLMReasoningExtractor.reasoning(from: message)
            ?? LLMReasoningExtractor.reasoning(from: first)

        let split = LLMReasoningExtractor.split(content: rawContent, reasoning: rawReasoning)
        let completion = LLMCompletion.make(content: split.content, reasoning: split.reasoning)
        if completion.content.isEmpty && !(completion.reasoning?.isEmpty == false) {
            throw LLMError.emptyResponse
        }
        // 允许仅有思考暂无正文的极端情况：用思考占位，避免整轮失败
        if completion.content.isEmpty, let r = completion.reasoning {
            return LLMCompletion.make(content: r, reasoning: r)
        }
        return completion
    }

    private static func extractResponsesCompletion(from data: Data) -> LLMCompletion? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var contentParts: [String] = []
        var reasoningParts: [String] = []

        if let text = obj["output_text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contentParts.append(text)
        }

        if let r = LLMReasoningExtractor.reasoning(from: obj) {
            reasoningParts.append(r)
        }

        if let output = obj["output"] as? [[String: Any]] {
            for item in output {
                let type = (item["type"] as? String) ?? ""
                if type == "reasoning" || type.contains("reasoning") {
                    if let r = extractReasoningFromResponsesItem(item) {
                        reasoningParts.append(r)
                    }
                } else if let content = item["content"] as? [[String: Any]] {
                    for c in content {
                        let ctype = (c["type"] as? String) ?? ""
                        if ctype.contains("reasoning") || ctype.contains("thinking") {
                            if let t = c["text"] as? String { reasoningParts.append(t) }
                            if let t = c["thinking"] as? String { reasoningParts.append(t) }
                        } else if let t = c["text"] as? String {
                            contentParts.append(t)
                        }
                    }
                } else if let t = item["text"] as? String {
                    contentParts.append(t)
                }
            }
        }

        let rawContent = contentParts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
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
            return nil
        }
        if completion.content.isEmpty, let r = completion.reasoning {
            return LLMCompletion.make(content: r, reasoning: r)
        }
        return completion
    }

    private static func emitResponsesItem(
        _ item: [String: Any],
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation,
        sawAny: inout Bool
    ) {
        let type = (item["type"] as? String) ?? ""
        if type == "reasoning" || type.contains("reasoning") {
            if let r = extractReasoningFromResponsesItem(item), !r.isEmpty {
                continuation.yield(.reasoningDelta(r))
                sawAny = true
            }
            return
        }
        if let content = item["content"] as? [[String: Any]] {
            for c in content {
                let ctype = (c["type"] as? String) ?? ""
                if ctype.contains("reasoning") || ctype.contains("thinking") {
                    if let t = c["text"] as? String, !t.isEmpty {
                        continuation.yield(.reasoningDelta(t))
                        sawAny = true
                    }
                } else if let t = c["text"] as? String, !t.isEmpty {
                    continuation.yield(.contentDelta(t))
                    sawAny = true
                }
            }
        } else if let t = item["text"] as? String, !t.isEmpty {
            continuation.yield(.contentDelta(t))
            sawAny = true
        }
    }

    private static func extractReasoningFromResponsesItem(_ item: [String: Any]) -> String? {
        if let s = LLMReasoningExtractor.reasoning(from: item) { return s }
        if let summary = item["summary"] as? [[String: Any]] {
            let joined = summary.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return joined
            }
        }
        if let content = item["content"] as? [[String: Any]] {
            let texts = content.compactMap { c -> String? in
                if let t = c["text"] as? String { return t }
                if let t = c["thinking"] as? String { return t }
                return nil
            }
            let joined = texts.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return joined
            }
        }
        return nil
    }

    private static func extractContentText(from message: [String: Any]) -> String? {
        if let s = message["content"] as? String {
            return s
        }
        // 多段 content 数组
        if let arr = message["content"] as? [[String: Any]] {
            let texts = arr.compactMap { item -> String? in
                let type = (item["type"] as? String) ?? "text"
                if type.contains("reasoning") || type.contains("thinking") { return nil }
                if let t = item["text"] as? String { return t }
                if let t = item["content"] as? String { return t }
                return nil
            }
            let joined = texts.joined()
            return joined.isEmpty ? nil : joined
        }
        if let s = message["text"] as? String { return s }
        return nil
    }

    private static func extractReasoningText(from message: [String: Any]) -> String? {
        // 绝不把 message.content 当思考；只认明确 reasoning/thinking 字段或带类型的 content 段
        if let s = LLMReasoningExtractor.reasoning(from: message) { return s }
        if let arr = message["content"] as? [[String: Any]] {
            let texts = arr.compactMap { item -> String? in
                let type = (item["type"] as? String) ?? ""
                guard type == "reasoning" || type == "thinking"
                        || type.contains("reasoning")
                        || type.contains("thinking")
                else { return nil }
                if let t = item["thinking"] as? String { return t }
                if let t = item["text"] as? String { return t }
                return nil
            }
            let joined = texts.joined(separator: "\n")
            return LLMReasoningExtractor.sanitizeReasoning(joined)
        }
        return nil
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
