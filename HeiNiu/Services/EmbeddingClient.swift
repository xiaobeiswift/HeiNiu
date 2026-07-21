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

/// OpenAI `/embeddings` 请求客户端。
enum OpenAIEmbeddingClient {
    static func embed(
        inputs: [String],
        provider: LLMProvider,
        model: String,
        apiKey: String
    ) async throws -> [[Float]] {
        guard !inputs.isEmpty else { return [] }
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanModel.isEmpty else { throw EmbeddingError.emptyModel }
        guard let url = URL(string: "\(provider.effectiveBaseURL)/embeddings") else {
            throw EmbeddingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": cleanModel,
            "input": inputs,
            "encoding_format": "float",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EmbeddingError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw EmbeddingError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

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
}
