/// SQLite 知识库持久化层。

import Foundation
import SQLite3

enum KnowledgeDatabaseError: LocalizedError {
    case open(String)
    case execute(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): "无法打开知识库：\(message)"
        case .execute(let message): "知识库操作失败：\(message)"
        }
    }
}

/// 单机知识库数据库。调用方由 ``KnowledgeStore`` 主线程隔离。
final class KnowledgeDatabase {
    nonisolated(unsafe) private var handle: OpaquePointer?
    let url: URL

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
            sqlite3_close(handle)
            handle = nil
            throw KnowledgeDatabaseError.open(message)
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try migrate()
    }

    deinit { sqlite3_close(handle) }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS collections (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS documents (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            collection_id TEXT,
            tags_json TEXT NOT NULL,
            source_kind TEXT NOT NULL,
            source_file_name TEXT,
            stored_relative_path TEXT,
            content TEXT NOT NULL,
            checksum TEXT NOT NULL,
            index_status TEXT NOT NULL,
            index_error TEXT,
            embedding_fingerprint TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            FOREIGN KEY(collection_id) REFERENCES collections(id) ON DELETE SET NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_documents_checksum ON documents(checksum);
        CREATE INDEX IF NOT EXISTS idx_documents_collection ON documents(collection_id);
        CREATE TABLE IF NOT EXISTS chunks (
            id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL,
            ordinal INTEGER NOT NULL,
            text TEXT NOT NULL,
            vector BLOB NOT NULL,
            embedding_fingerprint TEXT NOT NULL,
            FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_chunks_document ON chunks(document_id);
        CREATE INDEX IF NOT EXISTS idx_chunks_fingerprint ON chunks(embedding_fingerprint);
        """)
    }

    func loadCollections() throws -> [KnowledgeCollection] {
        let statement = try prepare("SELECT id,name,created_at,updated_at FROM collections ORDER BY name COLLATE NOCASE;")
        defer { sqlite3_finalize(statement) }
        var result: [KnowledgeCollection] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0) ?? "") else { continue }
            result.append(KnowledgeCollection(
                id: id,
                name: text(statement, 1) ?? "未命名集合",
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            ))
        }
        return result
    }

    func loadDocuments() throws -> [KnowledgeDocument] {
        let statement = try prepare("""
        SELECT id,title,collection_id,tags_json,source_kind,source_file_name,
               stored_relative_path,content,checksum,index_status,index_error,
               embedding_fingerprint,created_at,updated_at
        FROM documents ORDER BY updated_at DESC;
        """)
        defer { sqlite3_finalize(statement) }
        var result: [KnowledgeDocument] = []
        let decoder = JSONDecoder()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0) ?? "") else { continue }
            let collectionID = text(statement, 2).flatMap(UUID.init(uuidString:))
            let tagsData = Data((text(statement, 3) ?? "[]").utf8)
            let tags = (try? decoder.decode([String].self, from: tagsData)) ?? []
            result.append(KnowledgeDocument(
                id: id,
                title: text(statement, 1) ?? "未命名资料",
                collectionID: collectionID,
                tags: tags,
                sourceKind: KnowledgeSourceKind(rawValue: text(statement, 4) ?? "") ?? .note,
                sourceFileName: text(statement, 5),
                storedRelativePath: text(statement, 6),
                content: text(statement, 7) ?? "",
                checksum: text(statement, 8) ?? "",
                indexStatus: KnowledgeIndexStatus(rawValue: text(statement, 9) ?? "") ?? .pending,
                indexError: text(statement, 10),
                embeddingFingerprint: text(statement, 11),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 12)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 13))
            ))
        }
        return result
    }

    func upsertCollection(_ item: KnowledgeCollection) throws {
        let statement = try prepare("""
        INSERT INTO collections(id,name,created_at,updated_at) VALUES(?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET name=excluded.name,updated_at=excluded.updated_at;
        """)
        defer { sqlite3_finalize(statement) }
        bind(item.id.uuidString, to: 1, in: statement)
        bind(item.name, to: 2, in: statement)
        sqlite3_bind_double(statement, 3, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 4, item.updatedAt.timeIntervalSince1970)
        try finish(statement)
    }

    func deleteCollection(id: UUID) throws {
        let statement = try prepare("DELETE FROM collections WHERE id=?;")
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: 1, in: statement)
        try finish(statement)
    }

    func upsertDocument(_ item: KnowledgeDocument) throws {
        let statement = try prepare("""
        INSERT INTO documents(
          id,title,collection_id,tags_json,source_kind,source_file_name,stored_relative_path,
          content,checksum,index_status,index_error,embedding_fingerprint,created_at,updated_at
        ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
          title=excluded.title,collection_id=excluded.collection_id,tags_json=excluded.tags_json,
          source_kind=excluded.source_kind,source_file_name=excluded.source_file_name,
          stored_relative_path=excluded.stored_relative_path,content=excluded.content,
          checksum=excluded.checksum,index_status=excluded.index_status,
          index_error=excluded.index_error,embedding_fingerprint=excluded.embedding_fingerprint,
          updated_at=excluded.updated_at;
        """)
        defer { sqlite3_finalize(statement) }
        let tagsData = (try? JSONEncoder().encode(item.tags)) ?? Data("[]".utf8)
        bind(item.id.uuidString, to: 1, in: statement)
        bind(item.title, to: 2, in: statement)
        bind(item.collectionID?.uuidString, to: 3, in: statement)
        bind(String(decoding: tagsData, as: UTF8.self), to: 4, in: statement)
        bind(item.sourceKind.rawValue, to: 5, in: statement)
        bind(item.sourceFileName, to: 6, in: statement)
        bind(item.storedRelativePath, to: 7, in: statement)
        bind(item.content, to: 8, in: statement)
        bind(item.checksum, to: 9, in: statement)
        bind(item.indexStatus.rawValue, to: 10, in: statement)
        bind(item.indexError, to: 11, in: statement)
        bind(item.embeddingFingerprint, to: 12, in: statement)
        sqlite3_bind_double(statement, 13, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 14, item.updatedAt.timeIntervalSince1970)
        try finish(statement)
    }

    func deleteDocument(id: UUID) throws {
        let statement = try prepare("DELETE FROM documents WHERE id=?;")
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: 1, in: statement)
        try finish(statement)
    }

    func replaceChunks(documentID: UUID, chunks: [KnowledgeChunk]) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            let deletion = try prepare("DELETE FROM chunks WHERE document_id=?;")
            bind(documentID.uuidString, to: 1, in: deletion)
            try finish(deletion)
            sqlite3_finalize(deletion)

            for chunk in chunks {
                let statement = try prepare("INSERT INTO chunks(id,document_id,ordinal,text,vector,embedding_fingerprint) VALUES(?,?,?,?,?,?);")
                bind(chunk.id.uuidString, to: 1, in: statement)
                bind(chunk.documentID.uuidString, to: 2, in: statement)
                sqlite3_bind_int(statement, 3, Int32(chunk.ordinal))
                bind(chunk.text, to: 4, in: statement)
                let data = Self.vectorData(chunk.vector)
                _ = data.withUnsafeBytes { raw in
                    sqlite3_bind_blob(statement, 5, raw.baseAddress, Int32(raw.count), Self.transient)
                }
                bind(chunk.embeddingFingerprint, to: 6, in: statement)
                try finish(statement)
                sqlite3_finalize(statement)
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func loadChunks(documentIDs: Set<UUID>, fingerprint: String? = nil) throws -> [KnowledgeChunk] {
        guard !documentIDs.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: documentIDs.count).joined(separator: ",")
        let suffix = fingerprint == nil ? "" : " AND embedding_fingerprint=?"
        let statement = try prepare("SELECT id,document_id,ordinal,text,vector,embedding_fingerprint FROM chunks WHERE document_id IN (\(placeholders))\(suffix) ORDER BY document_id,ordinal;")
        defer { sqlite3_finalize(statement) }
        var index: Int32 = 1
        for id in documentIDs {
            bind(id.uuidString, to: index, in: statement)
            index += 1
        }
        if let fingerprint { bind(fingerprint, to: index, in: statement) }
        var result: [KnowledgeChunk] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0) ?? ""),
                  let documentID = UUID(uuidString: text(statement, 1) ?? "")
            else { continue }
            let length = Int(sqlite3_column_bytes(statement, 4))
            let bytes = sqlite3_column_blob(statement, 4)
            let data = bytes.map { Data(bytes: $0, count: length) } ?? Data()
            result.append(KnowledgeChunk(
                id: id,
                documentID: documentID,
                ordinal: Int(sqlite3_column_int(statement, 2)),
                text: text(statement, 3) ?? "",
                vector: Self.vectorArray(data),
                embeddingFingerprint: text(statement, 5) ?? ""
            ))
        }
        return result
    }

    func markAllPending() throws {
        try execute("UPDATE documents SET index_status='pending',index_error=NULL,embedding_fingerprint=NULL;")
    }

    func checkpoint() throws {
        try execute("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? lastError
            sqlite3_free(error)
            throw KnowledgeDatabaseError.execute(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw KnowledgeDatabaseError.execute(lastError) }
        return statement
    }

    private func finish(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw KnowledgeDatabaseError.execute(lastError)
        }
    }

    private var lastError: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "数据库未打开"
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func vectorData(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func vectorArray(_ data: Data) -> [Float] {
        guard data.count.isMultiple(of: MemoryLayout<Float>.size) else { return [] }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }
}
