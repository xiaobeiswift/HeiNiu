/// 全局知识库的数据管理、索引、检索与归档。

import CryptoKit
import Foundation
import Observation

@Observable
@MainActor
final class KnowledgeStore {
    var collections: [KnowledgeCollection] = []
    var documents: [KnowledgeDocument] = []
    var lastError: String?

    @ObservationIgnored private var database: KnowledgeDatabase?

    init() {
        AppPaths.ensureDirectories()
        reopenDatabase()
    }

    var allTags: [String] {
        Array(Set(documents.flatMap(\.tags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func collection(id: UUID?) -> KnowledgeCollection? {
        guard let id else { return nil }
        return collections.first { $0.id == id }
    }

    func document(id: UUID?) -> KnowledgeDocument? {
        guard let id else { return nil }
        return documents.first { $0.id == id }
    }

    func documents(in collectionID: UUID?) -> [KnowledgeDocument] {
        documents.filter { $0.collectionID == collectionID }
    }

    @discardableResult
    func addCollection(named name: String) -> KnowledgeCollection? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let database else { return nil }
        var item = KnowledgeCollection(name: clean)
        if collections.contains(where: { $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame }) {
            lastError = "集合名称已存在"
            return nil
        }
        do {
            item.updatedAt = Date()
            try database.upsertCollection(item)
            collections.append(item)
            sortCollections()
            return item
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func renameCollection(id: UUID, name: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }), let database else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        collections[index].name = clean
        collections[index].updatedAt = Date()
        do {
            try database.upsertCollection(collections[index])
            sortCollections()
        } catch { lastError = error.localizedDescription }
    }

    /// 删除集合但保留资料，资料自动移至未分类。
    func deleteCollection(id: UUID) {
        guard let database else { return }
        do {
            try database.deleteCollection(id: id)
            collections.removeAll { $0.id == id }
            for index in documents.indices where documents[index].collectionID == id {
                documents[index].collectionID = nil
            }
        } catch { lastError = error.localizedDescription }
    }

    @discardableResult
    func addNote(title: String, content: String, collectionID: UUID?, tags: [String]) -> UUID? {
        guard let database else { return nil }
        let id = UUID()
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty else {
            lastError = "笔记正文不能为空"
            return nil
        }
        let cleanTitle = normalizedTitle(title, fallback: "未命名笔记")
        let item = KnowledgeDocument(
            id: id,
            title: cleanTitle,
            collectionID: collectionID,
            tags: normalizeTags(tags),
            sourceKind: .note,
            content: cleanContent,
            checksum: "note-\(id.uuidString)-\(Self.sha256(cleanContent))"
        )
        do {
            try database.upsertDocument(item)
            documents.insert(item, at: 0)
            return id
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// 保存一张原始图片及其由视觉模型生成的知识正文。
    ///
    /// 图片会复制到 `KnowledgeBase/Files/<documentID>/`，数据库只记录相对路径。
    /// 重复判断同时包含图片字节与生成正文，因此同图在不同整理要求下可以形成不同资料。
    ///
    /// - Returns: 新建资料，或已存在的相同资料。
    func addGeneratedFile(
        sourceURL: URL,
        title: String,
        content: String,
        collectionID: UUID?,
        tags: [String]
    ) throws -> KnowledgeWriteResult {
        guard let database else { throw KnowledgeDatabaseError.open("数据库不可用") }
        var isDirectory: ObjCBool = false
        guard sourceURL.isFileURL,
              FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: sourceURL.path)
        else { throw LLMError.underlying("原始图片不可读：\(sourceURL.lastPathComponent)") }

        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty else { throw LLMError.underlying("模型生成的知识正文为空") }
        let sourceData = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        var checksumData = Data(cleanContent.utf8)
        checksumData.append(0)
        checksumData.append(sourceData)
        let checksum = Self.sha256(checksumData)
        if let existing = documents.first(where: { $0.sourceKind == .file && $0.checksum == checksum }) {
            return KnowledgeWriteResult(documentID: existing.id, wasCreated: false)
        }

        let id = UUID()
        let directory = AppPaths.knowledgeFilesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let target = directory.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: target)
            let item = KnowledgeDocument(
                id: id,
                title: normalizedTitle(title, fallback: sourceURL.deletingPathExtension().lastPathComponent),
                collectionID: collectionID,
                tags: normalizeTags(tags),
                sourceKind: .file,
                sourceFileName: sourceURL.lastPathComponent,
                storedRelativePath: "Files/\(id.uuidString)/\(sourceURL.lastPathComponent)",
                content: cleanContent,
                checksum: checksum
            )
            try database.upsertDocument(item)
            documents.insert(item, at: 0)
            return KnowledgeWriteResult(documentID: id, wasCreated: true)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            lastError = error.localizedDescription
            throw error
        }
    }

    func updateDocument(id: UUID, title: String, content: String, collectionID: UUID?, tags: [String]) {
        guard let index = documents.firstIndex(where: { $0.id == id }), let database else { return }
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty else {
            lastError = "资料正文不能为空"
            return
        }
        let contentChanged = documents[index].content != cleanContent
        documents[index].title = normalizedTitle(title, fallback: documents[index].title)
        documents[index].content = cleanContent
        documents[index].collectionID = collectionID
        documents[index].tags = normalizeTags(tags)
        documents[index].updatedAt = Date()
        if contentChanged {
            documents[index].checksum = documents[index].sourceKind == .note
                ? "note-\(id.uuidString)-\(Self.sha256(cleanContent))"
                : Self.sha256(cleanContent)
            documents[index].indexStatus = .pending
            documents[index].indexError = nil
            documents[index].embeddingFingerprint = nil
        }
        do { try database.upsertDocument(documents[index]) }
        catch { lastError = error.localizedDescription }
    }

    func deleteDocument(id: UUID) {
        guard let item = document(id: id), let database else { return }
        do {
            try database.deleteDocument(id: id)
            if let relative = item.storedRelativePath {
                let file = AppPaths.knowledgeBaseRoot.appendingPathComponent(relative)
                try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            }
            documents.removeAll { $0.id == id }
        } catch { lastError = error.localizedDescription }
    }

    func importFiles(_ urls: [URL], collectionID: UUID?) -> KnowledgeImportSummary {
        var summary = KnowledgeImportSummary()
        guard let database else {
            summary.failures.append("知识库数据库不可用")
            return summary
        }
        for url in urls {
            let extraction = TextExtractor.extractDetailed(from: url, maxCharacters: 2_000_000)
            guard extraction.didExtractContent else {
                summary.failures.append("\(url.lastPathComponent)：\(extraction.errorMessage ?? "无法抽取正文")")
                continue
            }
            let content = extraction.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let checksum = Self.sha256(content)
            if documents.contains(where: { $0.sourceKind == .file && $0.checksum == checksum }) {
                summary.skippedDuplicates += 1
                continue
            }
            let id = UUID()
            let directory = AppPaths.knowledgeFilesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
            let target = directory.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try FileManager.default.copyItem(at: url, to: target)
                let item = KnowledgeDocument(
                    id: id,
                    title: normalizedTitle(url.deletingPathExtension().lastPathComponent, fallback: url.lastPathComponent),
                    collectionID: collectionID,
                    sourceKind: .file,
                    sourceFileName: url.lastPathComponent,
                    storedRelativePath: "Files/\(id.uuidString)/\(url.lastPathComponent)",
                    content: content,
                    checksum: checksum
                )
                try database.upsertDocument(item)
                documents.insert(item, at: 0)
                summary.createdIDs.append(id)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                summary.failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        return summary
    }

    func originalFileURL(for document: KnowledgeDocument) -> URL? {
        guard let relative = document.storedRelativePath else { return nil }
        let url = AppPaths.knowledgeBaseRoot.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Indexing

    func markAllPending() {
        guard let database else { return }
        do {
            try database.markAllPending()
            for index in documents.indices {
                documents[index].indexStatus = .pending
                documents[index].indexError = nil
                documents[index].embeddingFingerprint = nil
            }
        } catch { lastError = error.localizedDescription }
    }

    func indexDocument(id: UUID, settings: SettingsStore) async {
        guard let index = documents.firstIndex(where: { $0.id == id }), let database else { return }
        do {
            let target = try embeddingTarget(settings: settings)
            documents[index].indexStatus = .indexing
            documents[index].indexError = nil
            try database.upsertDocument(documents[index])

            let textChunks = Self.chunkText(documents[index].content)
            guard !textChunks.isEmpty else { throw LLMError.underlying("资料没有可索引正文") }
            var vectors: [[Float]] = []
            for start in stride(from: 0, to: textChunks.count, by: 32) {
                let end = min(start + 32, textChunks.count)
                let batch = Array(textChunks[start..<end])
                let result = try await OpenAIEmbeddingClient.embed(
                    inputs: batch,
                    provider: target.provider,
                    model: target.model,
                    apiKey: target.apiKey,
                    apiMode: target.apiMode
                )
                vectors.append(contentsOf: result)
            }
            guard let dimension = vectors.first?.count,
                  dimension > 0,
                  vectors.allSatisfy({ $0.count == dimension })
            else { throw LLMError.underlying("嵌入向量维度不一致") }

            let chunks = zip(textChunks, vectors).enumerated().map { ordinal, pair in
                KnowledgeChunk(
                    id: UUID(),
                    documentID: id,
                    ordinal: ordinal,
                    text: pair.0,
                    vector: pair.1,
                    embeddingFingerprint: target.fingerprint
                )
            }
            try database.replaceChunks(documentID: id, chunks: chunks)
            guard let refreshed = documents.firstIndex(where: { $0.id == id }) else { return }
            documents[refreshed].indexStatus = .ready
            documents[refreshed].indexError = nil
            documents[refreshed].embeddingFingerprint = target.fingerprint
            documents[refreshed].updatedAt = Date()
            try database.upsertDocument(documents[refreshed])
        } catch {
            if let failed = documents.firstIndex(where: { $0.id == id }) {
                documents[failed].indexStatus = .failed
                documents[failed].indexError = error.localizedDescription
                try? database.upsertDocument(documents[failed])
            }
            lastError = error.localizedDescription
        }
    }

    func reindexAll(settings: SettingsStore) async {
        markAllPending()
        for id in documents.map(\.id) {
            await indexDocument(id: id, settings: settings)
        }
    }

    func testEmbedding(settings: SettingsStore) async throws -> Int {
        let target = try embeddingTarget(settings: settings)
        let vectors = try await OpenAIEmbeddingClient.embed(
            inputs: ["黑妞短剧知识库连接测试"],
            provider: target.provider,
            model: target.model,
            apiKey: target.apiKey,
            apiMode: target.apiMode
        )
        return vectors.first?.count ?? 0
    }

    // MARK: - Retrieval

    /// 为工作流执行一次向量检索。
    ///
    /// - Parameters:
    ///   - query: 语义查询文本。
    ///   - settings: 嵌入服务配置与钥匙串入口。
    ///   - collectionID: 可选知识集合。
    ///   - tags: 资料必须同时包含的标签。
    ///   - limit: 返回数量，限制为 1...20。
    /// - Returns: 按余弦相似度从高到低排序的片段。
    func search(
        query: String,
        settings: SettingsStore,
        collectionID: UUID?,
        tags: [String],
        limit: Int
    ) async throws -> [KnowledgeSearchResult] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { throw LLMError.underlying("知识检索查询不能为空") }
        guard let database else { throw KnowledgeDatabaseError.open("数据库不可用") }
        let target = try embeddingTarget(settings: settings)
        let vectors = try await OpenAIEmbeddingClient.embed(
            inputs: [cleanQuery],
            provider: target.provider,
            model: target.model,
            apiKey: target.apiKey,
            apiMode: target.apiMode
        )
        guard let queryVector = vectors.first, !queryVector.isEmpty else {
            throw LLMError.underlying("查询嵌入结果为空")
        }

        let normalizedTags = Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let candidates = documents.filter { document in
            guard document.indexStatus == .ready,
                  document.embeddingFingerprint == target.fingerprint
            else { return false }
            if let collectionID, document.collectionID != collectionID { return false }
            return normalizedTags.isSubset(of: Set(document.tags))
        }
        guard !candidates.isEmpty else {
            throw LLMError.underlying("筛选范围内没有使用当前嵌入配置完成索引的资料")
        }
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let chunks = try database.loadChunks(
            documentIDs: Set(candidates.map(\.id)),
            fingerprint: target.fingerprint
        )
        let result = chunks.compactMap { chunk -> KnowledgeSearchResult? in
            guard let document = byID[chunk.documentID],
                  chunk.vector.count == queryVector.count
            else { return nil }
            return KnowledgeSearchResult(
                chunkID: chunk.id,
                documentID: document.id,
                documentTitle: document.title,
                ordinal: chunk.ordinal,
                text: chunk.text,
                score: Self.cosineSimilarity(queryVector, chunk.vector)
            )
        }
        return Array(result.sorted { $0.score > $1.score }.prefix(max(1, min(20, limit))))
    }

    // MARK: - Archive

    func exportArchive(to destination: URL, settings: SettingsStore) throws {
        guard let database else { throw KnowledgeDatabaseError.open("数据库不可用") }
        try database.checkpoint()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("heiniu-kb-export-\(UUID().uuidString)", isDirectory: true)
        let bundle = temp.appendingPathComponent("KnowledgeBase", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: AppPaths.knowledgeDatabaseURL, to: bundle.appendingPathComponent("knowledge.sqlite"))
        if FileManager.default.fileExists(atPath: AppPaths.knowledgeFilesRoot.path) {
            try FileManager.default.copyItem(at: AppPaths.knowledgeFilesRoot, to: bundle.appendingPathComponent("Files", isDirectory: true))
        }
        let manifest = KnowledgeArchiveManifest(
            formatVersion: 1,
            exportedAt: Date(),
            embeddingFingerprint: currentFingerprint(settings: settings)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: bundle.appendingPathComponent("manifest.json"), options: .atomic)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try Self.runDitto(arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", bundle.path, destination.path])
    }

    func importArchive(from source: URL, mode: KnowledgeArchiveImportMode, settings: SettingsStore) throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("heiniu-kb-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        try Self.runDitto(arguments: ["-x", "-k", source.path, temp.path])
        guard let manifestURL = FileManager.default.enumerator(at: temp, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL })
            .first(where: { $0.lastPathComponent == "manifest.json" }),
              let root = Optional(manifestURL.deletingLastPathComponent()),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("knowledge.sqlite").path)
        else { throw LLMError.underlying("知识库归档缺少有效清单或数据库") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(KnowledgeArchiveManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.formatVersion == 1 else { throw LLMError.underlying("不支持的知识库归档版本") }

        switch mode {
        case .replace:
            database = nil
            try? FileManager.default.removeItem(at: AppPaths.knowledgeBaseRoot)
            try FileManager.default.createDirectory(at: AppPaths.knowledgeBaseRoot, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: root.appendingPathComponent("knowledge.sqlite"), to: AppPaths.knowledgeDatabaseURL)
            let files = root.appendingPathComponent("Files", isDirectory: true)
            if FileManager.default.fileExists(atPath: files.path) {
                try FileManager.default.copyItem(at: files, to: AppPaths.knowledgeFilesRoot)
            } else {
                try FileManager.default.createDirectory(at: AppPaths.knowledgeFilesRoot, withIntermediateDirectories: true)
            }
            reopenDatabase()
        case .merge:
            let imported = try KnowledgeDatabase(url: root.appendingPathComponent("knowledge.sqlite"))
            guard let database else { throw KnowledgeDatabaseError.open("数据库不可用") }
            for collection in try imported.loadCollections() { try database.upsertCollection(collection) }
            let existingChecksums = Set(documents.filter { $0.sourceKind == .file }.map(\.checksum))
            let importedDocuments = try imported.loadDocuments()
            for document in importedDocuments where !existingChecksums.contains(document.checksum) {
                try database.upsertDocument(document)
                let chunks = try imported.loadChunks(documentIDs: [document.id])
                try database.replaceChunks(documentID: document.id, chunks: chunks)
                if let relative = document.storedRelativePath {
                    let from = root.appendingPathComponent(relative)
                    let to = AppPaths.knowledgeBaseRoot.appendingPathComponent(relative)
                    if FileManager.default.fileExists(atPath: from.path) {
                        try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                        if FileManager.default.fileExists(atPath: to.path) { try FileManager.default.removeItem(at: to) }
                        try FileManager.default.copyItem(at: from, to: to)
                    }
                }
            }
            reload()
        }

        if manifest.embeddingFingerprint != currentFingerprint(settings: settings) {
            markAllPending()
        }
    }

    // MARK: - Helpers

    private func reopenDatabase() {
        do {
            database = try KnowledgeDatabase(url: AppPaths.knowledgeDatabaseURL)
            reload()
        } catch {
            database = nil
            collections = []
            documents = []
            lastError = error.localizedDescription
        }
    }

    private func reload() {
        guard let database else { return }
        do {
            collections = try database.loadCollections()
            documents = try database.loadDocuments()
            sortCollections()
        } catch { lastError = error.localizedDescription }
    }

    private func sortCollections() {
        collections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func embeddingTarget(settings: SettingsStore) throws -> (
        provider: LLMProvider,
        model: String,
        apiKey: String,
        apiMode: KnowledgeEmbeddingAPIMode,
        fingerprint: String
    ) {
        guard let provider = settings.provider(id: settings.knowledgeEmbeddingProviderID),
              provider.protocolType == .openAICompatible
        else { throw LLMError.underlying("请在设置中选择 OpenAI 兼容的知识库嵌入服务商") }
        let model = settings.knowledgeEmbeddingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw EmbeddingError.emptyModel }
        let apiKey = settings.apiKey(for: provider.id)
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        let apiMode = settings.knowledgeEmbeddingAPIMode
        return (
            provider,
            model,
            apiKey,
            apiMode,
            "\(provider.id.uuidString)|\(provider.effectiveBaseURL)|\(apiMode.rawValue)|\(model)"
        )
    }

    private func currentFingerprint(settings: SettingsStore) -> String? {
        let model = settings.knowledgeEmbeddingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let provider = settings.provider(id: settings.knowledgeEmbeddingProviderID),
              !model.isEmpty else { return nil }
        return "\(provider.id.uuidString)|\(provider.effectiveBaseURL)|\(settings.knowledgeEmbeddingAPIMode.rawValue)|\(model)"
    }

    private func normalizedTitle(_ value: String, fallback: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? fallback : clean
    }

    private func normalizeTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    nonisolated private static func sha256(_ text: String) -> String {
        sha256(Data(text.utf8))
    }

    nonisolated private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return -1 }
        var dot: Double = 0
        var lhsNorm: Double = 0
        var rhsNorm: Double = 0
        for index in lhs.indices {
            let a = Double(lhs[index])
            let b = Double(rhs[index])
            dot += a * b
            lhsNorm += a * a
            rhsNorm += b * b
        }
        let denominator = sqrt(lhsNorm) * sqrt(rhsNorm)
        return denominator > 0 ? dot / denominator : -1
    }

    nonisolated private static func chunkText(_ text: String, target: Int = 1_000, overlap: Int = 150) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let paragraphs = normalized.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var chunks: [String] = []
        var current = ""
        func appendCurrent() {
            let clean = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { chunks.append(clean) }
        }
        for paragraph in paragraphs {
            if paragraph.count > target {
                appendCurrent()
                current = ""
                var start = paragraph.startIndex
                while start < paragraph.endIndex {
                    let end = paragraph.index(start, offsetBy: target, limitedBy: paragraph.endIndex) ?? paragraph.endIndex
                    chunks.append(String(paragraph[start..<end]))
                    if end == paragraph.endIndex { break }
                    start = paragraph.index(end, offsetBy: -min(overlap, paragraph.distance(from: start, to: end)))
                }
            } else if current.count + paragraph.count + 2 <= target {
                current += current.isEmpty ? paragraph : "\n\n\(paragraph)"
            } else {
                let tail = String(current.suffix(overlap))
                appendCurrent()
                current = tail.isEmpty ? paragraph : "\(tail)\n\n\(paragraph)"
            }
        }
        appendCurrent()
        return chunks
    }

    nonisolated private static func runDitto(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw LLMError.underlying("知识库归档操作失败") }
    }
}

private struct KnowledgeArchiveManifest: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var embeddingFingerprint: String?
}
