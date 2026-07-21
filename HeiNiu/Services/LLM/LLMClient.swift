/// LLM 客户端协议、错误与工厂。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// LLM 调用错误。
///
/// 用于模型接口与连通性流程的用户可读失败原因。
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
        case .missingProvider: "请先绑定服务商"
        case .missingModel: "请先选择或填写模型"
        case .invalidURL: "Base URL 无效"
        case .http(let code, let body): "HTTP \(code)：\(body.prefix(240))"
        case .emptyResponse: "模型返回为空"
        case .decoding: "无法解析模型响应"
        case .underlying(let message): message
        }
    }
}

/// 模型思考 / 推理强度。
///
/// 对支持 reasoning 的模型或兼容网关生效；``none`` 不写入相关字段。
enum ReasoningEffort: String, Codable, CaseIterable, Identifiable, Hashable {
    case none
    case low
    case medium
    case high

    var id: String { rawValue }

    /// 写入 API 的 effort 字符串；``none`` 为 `nil`。
    var apiValue: String? {
        switch self {
        case .none: nil
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        }
    }
}

/// 发往视觉模型的一张内嵌图片。
struct LLMImageAttachment: Hashable, Sendable {
    /// 图片二进制数据。
    var data: Data
    /// IANA 媒体类型，例如 `image/jpeg`。
    var mediaType: String

    /// 可直接写入 OpenAI 兼容接口的 Data URL。
    var dataURL: String {
        "data:\(mediaType);base64,\(data.base64EncodedString())"
    }
}

/// 发往模型的单条消息，可同时携带文本与内嵌图片。
struct LLMChatMessage: Hashable, Sendable {
    /// Role
    ///
    /// `Role` 类型定义。
    enum Role: String, Sendable {
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
    /// 与正文一同发送的图片；纯文本调用保持为空。
    var images: [LLMImageAttachment] = []
}

/// 一次补全结果：最终回答 + 可选思考过程。
struct LLMCompletion: Hashable, Sendable {
    /// 助手最终回答。
    var content: String
    /// 思考 / 推理文本（若模型或网关提供）。
    var reasoning: String?

    /// 是否有可展示的思考过程。
    var hasReasoning: Bool {
        !(reasoning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// 规范化空白：空字符串视为 `nil`。
    static func make(content: String, reasoning: String?) -> LLMCompletion {
        let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = reasoning?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LLMCompletion(
            content: c,
            reasoning: (r?.isEmpty == false) ? r : nil
        )
    }
}

/// 流式补全事件。
enum LLMStreamEvent: Sendable {
    /// 思考过程增量。
    case reasoningDelta(String)
    /// 最终回答增量。
    case contentDelta(String)
}

/// 大模型补全客户端协议。
///
/// 实现方：``OpenAICompatibleClient``、``AnthropicClient``。
///
/// 支持一次性补全与流式补全（见协议方法）。
///
/// - SeeAlso: ``LLMClientFactory``
///
protocol LLMClient: Sendable {
    /// 执行一次文本补全（非流式）。
    ///
    /// - Returns: ``LLMCompletion``（含可选思考过程）。
    /// - Throws: ``LLMError`` 或传输错误。
    ///
    func complete(
        messages: [LLMChatMessage],
        model: String,
        temperature: Double,
        reasoningEffort: ReasoningEffort,
        apiKey: String
    ) async throws -> LLMCompletion

    /// 流式补全：边收边产出增量事件，结束时仍可通过累计文本得到完整结果。
    ///
    /// 默认实现：调用非流式补全后一次性发出 delta（兼容未实现 SSE 的客户端）。
    ///
    func stream(
        messages: [LLMChatMessage],
        model: String,
        temperature: Double,
        reasoningEffort: ReasoningEffort,
        apiKey: String
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>
}

extension LLMClient {
    /// 默认流式：退化为一次非流式补全，再拆成 reasoning / content 事件。
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
                    let result = try await complete(
                        messages: messages,
                        model: model,
                        temperature: temperature,
                        reasoningEffort: reasoningEffort,
                        apiKey: apiKey
                    )
                    if let reasoning = result.reasoning, !reasoning.isEmpty {
                        continuation.yield(.reasoningDelta(reasoning))
                    }
                    if !result.content.isEmpty {
                        continuation.yield(.contentDelta(result.content))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// 流式文本累计：兼容「真 delta」与「整段快照」两种网关风格。
///
/// 有的兼容层每个 SSE 事件塞的是目前为止的全文，而不是增量；
/// 直接 `+=` 会变成同一段话重复 N 遍（界面上像鬼畜「思考过程」）。
struct LLMStreamTextBuffer: Sendable {
    private(set) var text: String = ""

    /// 写入一段新文本；返回本次相对旧缓冲的「新增」部分（可能为空）。
    @discardableResult
    mutating func absorb(_ incoming: String) -> String {
        let chunk = incoming
        guard !chunk.isEmpty else { return "" }

        if text.isEmpty {
            text = chunk
            return chunk
        }
        if chunk == text {
            return ""
        }
        // 累计快照：新文本以旧缓冲为前缀
        if chunk.hasPrefix(text) {
            let added = String(chunk.dropFirst(text.count))
            text = chunk
            return added
        }
        // 乱序/回退的短快照
        if text.hasPrefix(chunk) {
            return ""
        }
        // 整段重复粘贴（中间夹空白）
        if text.contains(chunk), chunk.count >= 24 {
            return ""
        }
        text += chunk
        return chunk
    }

    mutating func reset() {
        text = ""
    }
}

/// 从模型正文中拆出思考块。
///
/// 支持：
/// - XML 标签：`<think>` / `<thinking>` / `<reasoning>`
/// - Markdown 标题段：`**思考过程…**` / `### 思考过程` 等到分隔线或正文
/// - API 字段：`reasoning_content` / `thinking` 等
///
/// 统一进 ``LLMCompletion/reasoning``，正文只留最终回答。
enum LLMReasoningExtractor {
    /// 拆分正文与思考。
    ///
    /// - Parameters:
    ///   - content: 原始正文。
    ///   - reasoning: API 已提供的思考（优先保留，并与标签内容合并）。
    /// - Returns: 清洗后的正文 + 合并后的思考。
    static func split(content: String, reasoning: String? = nil) -> (content: String, reasoning: String?) {
        var body = content
        var parts: [String] = []
        if let reasoning, !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(reasoning.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // 1) XML 风格
        let tagPatterns = [
            #"<think>\s*([\s\S]*?)\s*</think>"#,
            #"<thinking>\s*([\s\S]*?)\s*</thinking>"#,
            #"<reasoning>\s*([\s\S]*?)\s*</reasoning>"#,
        ]
        for pattern in tagPatterns {
            extractRegexCaptures(pattern: pattern, from: &body, into: &parts)
        }

        // 2) Markdown / 中文标题风格（Grok 常把「思考过程」写进正文）
        let markdownPatterns = [
            // **思考过程...**： ... --- 或到文末
            #"\*{0,2}思考过程[^\n*]{0,40}\*{0,2}\s*[:：]?\s*\n+([\s\S]*?)(?:\n\s*-{3,}\s*\n|\n\s*#{1,3}\s|\z)"#,
            #"\*{0,2}Thinking\s*Process[^\n*]{0,40}\*{0,2}\s*[:：]?\s*\n+([\s\S]*?)(?:\n\s*-{3,}\s*\n|\n\s*#{1,3}\s|\z)"#,
            #"(?m)^#{1,3}\s*思考过程[^\n]*\n+([\s\S]*?)(?:\n\s*-{3,}\s*\n|\n\s*#{1,3}\s|\z)"#,
            #"(?m)^#{1,3}\s*Thinking[^\n]*\n+([\s\S]*?)(?:\n\s*-{3,}\s*\n|\n\s*#{1,3}\s|\z)"#,
        ]
        for pattern in markdownPatterns {
            extractRegexCaptures(pattern: pattern, from: &body, into: &parts, options: [.caseInsensitive])
        }

        // 若正文仍以「思考过程」开头且后面有明显分隔，再兜底切一刀
        if let cut = cutLeadingThinkingSection(body) {
            if !cut.reasoning.isEmpty { parts.insert(cut.reasoning, at: 0) }
            body = cut.content
        }

        let cleanedBody = body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // 去掉思考段后残留的 ---
            .replacingOccurrences(of: #"^\s*-{3,}\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let mergedReasoning = sanitizeReasoning(
            parts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        )
        return (cleanedBody, mergedReasoning)
    }

    /// 用正则从正文抽出捕获组 1，并删除整段匹配。
    private static func extractRegexCaptures(
        pattern: String,
        from body: inout String,
        into parts: inout [String],
        options: NSRegularExpression.Options = [.caseInsensitive]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let ns = body as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: body, options: [], range: full)
        guard !matches.isEmpty else { return }
        for match in matches.reversed() {
            if match.numberOfRanges > 1 {
                let r = match.range(at: 1)
                if r.location != NSNotFound {
                    let chunk = ns.substring(with: r)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chunk.isEmpty { parts.insert(chunk, at: 0) }
                }
            }
            if let range = Range(match.range, in: body) {
                body.removeSubrange(range)
            }
        }
    }

    /// 兜底：正文以「思考过程」起头，到 `---` / 「剧本」/「第x集」等再切开。
    private static func cutLeadingThinkingSection(_ text: String) -> (content: String, reasoning: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let header = #"^[\*#\s]*思考过程[^\n]{0,60}\n+"#
        guard let headerRegex = try? NSRegularExpression(pattern: header, options: [.caseInsensitive]),
              let headerMatch = headerRegex.firstMatch(
                in: trimmed,
                options: [],
                range: NSRange(location: 0, length: (trimmed as NSString).length)
              ),
              headerMatch.range.location == 0,
              let headerRange = Range(headerMatch.range, in: trimmed)
        else { return nil }

        let afterHeader = String(trimmed[headerRange.upperBound...])
        // 分隔：--- 或 明显进入成稿
        let splitters = [
            #"\n\s*-{3,}\s*\n"#,
            #"\n\s*(?:#{1,3}\s*)?(?:剧本|正文|成稿|第\s*\d+\s*集|Episode)\b"#,
        ]
        var cutIndex: String.Index?
        for pattern in splitters {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let ns = afterHeader as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = regex.firstMatch(in: afterHeader, options: [], range: range),
               let r = Range(m.range, in: afterHeader) {
                if cutIndex == nil || r.lowerBound < cutIndex! {
                    cutIndex = r.lowerBound
                }
            }
        }
        // 没有明确分隔时：若思考段很长且后面还有不少内容，不强行切，避免误伤
        guard let cutIndex else { return nil }
        let reasoning = String(afterHeader[..<cutIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        var content = String(afterHeader[cutIndex...])
            .replacingOccurrences(of: #"^\s*-{3,}\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if reasoning.isEmpty { return nil }
        if content.isEmpty { content = "" }
        return (content, reasoning)
    }

    /// 从任意 JSON 字典抽取**明确的**思考字段（避免把普通 content 误判成思考）。
    static func reasoning(from object: [String: Any]) -> String? {
        // 仅认明确字段；不要扫 analysis 等易误伤键
        let keys = [
            "reasoning_content", "reasoningContent",
            "thinking", "thought", "reasoning_text",
        ]
        for key in keys {
            if let s = object[key] as? String,
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return sanitizeReasoning(s)
            }
        }
        // reasoning 可能是 string 或 object；string 时要警惕网关把正文塞进来
        if let s = object["reasoning"] as? String,
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sanitizeReasoning(s)
        }
        // OpenAI Responses: reasoning.summary / content 数组
        if let reasoning = object["reasoning"] as? [String: Any] {
            if let s = reasoning["summary"] as? String,
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return sanitizeReasoning(s)
            }
            if let content = reasoning["content"] as? [[String: Any]] {
                let texts = content.compactMap { item -> String? in
                    if let t = item["text"] as? String { return t }
                    if let t = item["content"] as? String { return t }
                    return nil
                }
                let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty { return sanitizeReasoning(joined) }
            }
        }
        return nil
    }

    /// 去掉连续重复段，过滤空结果。
    static func sanitizeReasoning(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        // 连续相同段落折叠（流式重复拼接的典型症状）
        let paragraphs = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let echoLineHints = [
            "the user said", "user said", "user request",
            "用户说", "用户输入", "用户要求", "用户的要求",
        ]
        var collapsed: [String] = []
        for line in paragraphs {
            if line.isEmpty {
                if collapsed.last != "" { collapsed.append("") }
                continue
            }
            if collapsed.last == line { continue }
            // 丢掉纯复读行：用户要求：“…”
            let lower = line.lowercased()
            if echoLineHints.contains(where: { lower.hasPrefix($0) || lower.contains("\($0)：") || lower.contains("\($0):") }),
               line.count < 180 {
                continue
            }
            collapsed.append(line)
        }
        text = collapsed.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 同一长句无换行重复：AABB → AB
        if text.count >= 48 {
            let half = text.count / 2
            let a = String(text.prefix(half))
            let b = String(text.suffix(text.count - half))
            if a == b { text = a }
        }
        // 再压一轮：整段重复两遍（中间可能有换行）
        if text.count >= 48 {
            let compact = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            if compact.count >= 48, compact.count % 2 == 0 {
                let mid = compact.count / 2
                let a = String(compact.prefix(mid))
                let b = String(compact.suffix(mid))
                if a == b {
                    // 尽量按原换行取前半
                    let approx = text.count / 2
                    text = String(text.prefix(approx)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return text.isEmpty ? nil : text
    }

    /// 是否像「复读用户输入」的假思考。
    static func looksLikeUserEcho(_ reasoning: String, userText: String?) -> Bool {
        let text = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let lower = text.lowercased()
        let echoHints = [
            "the user said", "user said", "user request",
            "用户说", "用户输入", "用户要求", "用户的要求", "用户让",
        ]
        let echoHits = echoHints.reduce(0) { $0 + lower.components(separatedBy: $1).count - 1 }

        // 几乎全是「用户要求：…」复读
        if echoHits >= 1 {
            let lines = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty {
                let echoLines = lines.filter { line in
                    let l = line.lowercased()
                    return echoHints.contains { l.contains($0) }
                }
                if Double(echoLines.count) / Double(lines.count) >= 0.6 {
                    return true
                }
            }
        }

        guard let userText, !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return echoHits >= 2 && text.count < 200
        }
        let userCompact = compact(userText)
        let reasonCompact = compact(text)
        if userCompact.isEmpty { return false }
        if reasonCompact == userCompact { return true }
        if reasonCompact.contains(userCompact), reasonCompact.count <= userCompact.count + 40 {
            return true
        }
        // 复读用户句两次以上
        if userCompact.count >= 8 {
            let occurrences = reasonCompact.components(separatedBy: userCompact).count - 1
            if occurrences >= 2 { return true }
        }
        return false
    }

    private static func compact(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined()
            .replacingOccurrences(of: #"[“”\"'：:，,。.!？?]"#, with: "", options: .regularExpression)
    }
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
