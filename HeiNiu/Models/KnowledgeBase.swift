/// 全局知识库的集合、资料、索引与引用模型。

import Foundation

/// 知识库嵌入接口的请求格式。
nonisolated enum KnowledgeEmbeddingAPIMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// OpenAI 兼容文本向量：`POST /embeddings`，`input` 为字符串数组。
    case openAIText
    /// 火山方舟图文向量：`POST /embeddings/multimodal`，`input` 为多模态对象数组。
    case doubaoMultimodal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAIText: "标准文本向量"
        case .doubaoMultimodal: "豆包多模态向量"
        }
    }

    var endpointPath: String {
        switch self {
        case .openAIText: "/embeddings"
        case .doubaoMultimodal: "/embeddings/multimodal"
        }
    }
}

/// 资料的来源类型。
nonisolated enum KnowledgeSourceKind: String, Codable, Sendable {
    case file
    case note
}

/// 资料向量索引状态。
nonisolated enum KnowledgeIndexStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case indexing
    case ready
    case failed

    var title: String {
        switch self {
        case .pending: "等待索引"
        case .indexing: "索引中"
        case .ready: "可检索"
        case .failed: "索引失败"
        }
    }
}

/// 用于组织全局资料的集合。
nonisolated struct KnowledgeCollection: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 一条全局知识资料。
nonisolated struct KnowledgeDocument: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var collectionID: UUID?
    var tags: [String]
    var sourceKind: KnowledgeSourceKind
    var sourceFileName: String?
    var storedRelativePath: String?
    var content: String
    var checksum: String
    var indexStatus: KnowledgeIndexStatus
    var indexError: String?
    var embeddingFingerprint: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        collectionID: UUID? = nil,
        tags: [String] = [],
        sourceKind: KnowledgeSourceKind,
        sourceFileName: String? = nil,
        storedRelativePath: String? = nil,
        content: String,
        checksum: String,
        indexStatus: KnowledgeIndexStatus = .pending,
        indexError: String? = nil,
        embeddingFingerprint: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.collectionID = collectionID
        self.tags = tags
        self.sourceKind = sourceKind
        self.sourceFileName = sourceFileName
        self.storedRelativePath = storedRelativePath
        self.content = content
        self.checksum = checksum
        self.indexStatus = indexStatus
        self.indexError = indexError
        self.embeddingFingerprint = embeddingFingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 一段可检索文本及其向量。
nonisolated struct KnowledgeChunk: Identifiable, Hashable, Sendable {
    var id: UUID
    var documentID: UUID
    var ordinal: Int
    var text: String
    var vector: [Float]
    var embeddingFingerprint: String
}

/// 工作流知识检索返回的一条相似片段。
nonisolated struct KnowledgeSearchResult: Identifiable, Hashable, Sendable {
    /// 使用知识分块 ID 作为稳定标识符。
    var id: UUID { chunkID }
    /// 分块 ID。
    var chunkID: UUID
    /// 所属资料 ID。
    var documentID: UUID
    /// 资料标题。
    var documentTitle: String
    /// 分块序号。
    var ordinal: Int
    /// 分块正文。
    var text: String
    /// 余弦相似度。
    var score: Double
}

/// 知识库导入汇总。
nonisolated struct KnowledgeImportSummary: Sendable {
    var createdIDs: [UUID] = []
    var skippedDuplicates: Int = 0
    var failures: [String] = []
}

/// 知识库归档导入模式。
nonisolated enum KnowledgeArchiveImportMode: String, CaseIterable, Identifiable {
    case merge
    case replace

    var id: String { rawValue }
    var title: String { self == .merge ? "合并" : "替换全部" }
}
