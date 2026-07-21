/// OpenAI 兼容向量接口。

import Foundation

enum EmbeddingError: LocalizedError {
    case invalidURL
    case emptyModel
    case invalidResponse
    case http(Int, String)
    case countMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "嵌入服务 Base URL 无效"
        case .emptyModel: "请先填写嵌入模型 ID"
        case .invalidResponse: "无法解析嵌入接口响应"
        case .http(let code, let body): "嵌入接口 HTTP \(code)：\(body.prefix(240))"
        case .countMismatch(let expected, let actual): "嵌入数量不匹配（请求 \(expected)，返回 \(actual)）"
        }
    }
}

/// 标准 OpenAI 文本向量与火山方舟豆包多模态向量请求客户端。
enum OpenAIEmbeddingClient {
    static func embed(
        inputs: [String],
        provider: LLMProvider,
        model: String,
        apiKey: String,
        apiMode: KnowledgeEmbeddingAPIMode
    ) async throws -> [[Float]] {
        guard !inputs.isEmpty else { return [] }
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanModel.isEmpty else { throw EmbeddingError.emptyModel }

        switch apiMode {
        case .openAIText:
            return try await embedOpenAIText(
                inputs: inputs,
                provider: provider,
                model: cleanModel,
                apiKey: apiKey
            )
        case .doubaoMultimodal:
            return try await embedDoubaoMultimodal(
                inputs: inputs,
                provider: provider,
                model: cleanModel,
                apiKey: apiKey
            )
        }
    }

    private static func embedOpenAIText(
        inputs: [String],
        provider: LLMProvider,
        model: String,
        apiKey: String
    ) async throws -> [[Float]] {
        let data = try await request(
            provider: provider,
            apiKey: apiKey,
            apiMode: .openAIText,
            body: [
                "model": model,
                "input": inputs,
                "encoding_format": "float",
            ]
        )
        struct Response: Decodable {
            struct Item: Decodable {
                var index: Int
                var embedding: [Float]
            }
            var data: [Item]
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw EmbeddingError.invalidResponse
        }
        let sorted = decoded.data.sorted { $0.index < $1.index }.map(\.embedding)
        guard sorted.count == inputs.count else {
            throw EmbeddingError.countMismatch(expected: inputs.count, actual: sorted.count)
        }
        guard sorted.allSatisfy({ !$0.isEmpty }) else { throw EmbeddingError.invalidResponse }
        return sorted
    }

    /// 豆包图文向量接口每次请求至多包含一个 text 输入，因此按原顺序逐条请求。
    private static func embedDoubaoMultimodal(
        inputs: [String],
        provider: LLMProvider,
        model: String,
        apiKey: String
    ) async throws -> [[Float]] {
        var result: [[Float]] = []
        result.reserveCapacity(inputs.count)
        for input in inputs {
            let data = try await request(
                provider: provider,
                apiKey: apiKey,
                apiMode: .doubaoMultimodal,
                body: [
                    "model": model,
                    "input": [["type": "text", "text": input]],
                    "encoding_format": "float",
                ]
            )
            let vectors = try parseMultimodalVectors(data)
            guard vectors.count == 1, let vector = vectors.first, !vector.isEmpty else {
                throw EmbeddingError.countMismatch(expected: 1, actual: vectors.count)
            }
            result.append(vector)
        }
        return result
    }

    private static func request(
        provider: LLMProvider,
        apiKey: String,
        apiMode: KnowledgeEmbeddingAPIMode,
        body: [String: Any]
    ) async throws -> Data {
        guard let url = URL(string: "\(provider.effectiveBaseURL)\(apiMode.endpointPath)") else {
            throw EmbeddingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EmbeddingError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw EmbeddingError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// 兼容方舟返回的单向量 `[Float]` 与多模态嵌套向量 `[[Float]]`。
    private static func parseMultimodalVectors(_ data: Data) throws -> [[Float]] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawData = root["data"]
        else { throw EmbeddingError.invalidResponse }

        let items: [[String: Any]]
        if let array = rawData as? [[String: Any]] {
            items = array
        } else if let object = rawData as? [String: Any] {
            items = [object]
        } else {
            throw EmbeddingError.invalidResponse
        }

        var vectors: [[Float]] = []
        for item in items {
            if let values = item["embedding"] as? [NSNumber] {
                vectors.append(values.map { $0.floatValue })
            } else if let groups = item["embedding"] as? [[NSNumber]] {
                vectors.append(contentsOf: groups.map { $0.map { $0.floatValue } })
            }
        }
        guard !vectors.isEmpty, vectors.allSatisfy({ !$0.isEmpty }) else {
            throw EmbeddingError.invalidResponse
        }
        return vectors
    }
}
