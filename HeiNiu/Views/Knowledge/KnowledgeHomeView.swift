/// 全局知识库工作台。

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum KnowledgeCollectionFilter: Hashable {
    case all
    case uncategorized
    case collection(UUID)
}

struct KnowledgeHomeView: View {
    @Environment(KnowledgeStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    @State private var filter: KnowledgeCollectionFilter = .all
    @State private var selectedDocumentID: UUID?
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var showCollectionSheet = false
    @State private var renamingCollection: KnowledgeCollection?
    @State private var showNoteSheet = false
    @State private var statusMessage: String?

    private var filteredDocuments: [KnowledgeDocument] {
        store.documents.filter { document in
            let inCollection: Bool = {
                switch filter {
                case .all: true
                case .uncategorized: document.collectionID == nil
                case .collection(let id): document.collectionID == id
                }
            }()
            let matchesTag = selectedTag == nil || document.tags.contains(selectedTag!)
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || document.title.localizedCaseInsensitiveContains(query)
                || document.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
                || document.content.localizedCaseInsensitiveContains(query)
            return inCollection && matchesTag && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            HStack(spacing: 0) {
                collectionSidebar
                    .frame(width: 190)
                Divider().opacity(0.45)
                documentList
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 390)
                Divider().opacity(0.45)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppTheme.bgBase)
        .sheet(isPresented: $showCollectionSheet) {
            CollectionEditorSheet(title: "新建集合", actionTitle: "创建") { name in
                if let item = store.addCollection(named: name) {
                    filter = .collection(item.id)
                }
            }
        }
        .sheet(item: $renamingCollection) { collection in
            CollectionEditorSheet(
                title: "重命名集合",
                actionTitle: "保存",
                initialName: collection.name
            ) { name in
                store.renameCollection(id: collection.id, name: name)
            }
        }
        .sheet(isPresented: $showNoteSheet) {
            KnowledgeNoteSheet(collections: store.collections, initialCollectionID: selectedCollectionID) { title, content, collectionID, tags in
                if let id = store.addNote(title: title, content: content, collectionID: collectionID, tags: tags) {
                    selectedDocumentID = id
                    Task { await store.indexDocument(id: id, settings: settings) }
                }
            }
        }
    }

    private var selectedCollectionID: UUID? {
        if case .collection(let id) = filter { return id }
        return nil
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("知识库")
                    .font(.largeTitle.weight(.bold))
                Text("全局资料 · 本地向量索引 · 独立归档")
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }
            Menu {
                Button("导出知识库归档", action: exportArchive)
                Divider()
                Button("合并导入归档") { importArchive(mode: .merge) }
                Button("替换导入归档", role: .destructive) { importArchive(mode: .replace) }
            } label: {
                Label("迁移", systemImage: "arrow.up.arrow.down.circle")
            }
            Button {
                importFiles()
            } label: {
                Label("导入文件或图片", systemImage: "square.and.arrow.down")
            }
            Button {
                showNoteSheet = true
            } label: {
                Label("新建笔记", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .foregroundStyle(.black)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var collectionSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("集合")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                Spacer()
                Button { showCollectionSheet = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .help("新建集合")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 4) {
                    collectionRow(title: "全部资料", count: store.documents.count, value: .all, systemImage: "books.vertical")
                    collectionRow(title: "未分类", count: store.documents.filter { $0.collectionID == nil }.count, value: .uncategorized, systemImage: "tray")
                    ForEach(store.collections) { collection in
                        collectionRow(
                            title: collection.name,
                            count: store.documents.filter { $0.collectionID == collection.id }.count,
                            value: .collection(collection.id),
                            systemImage: "folder"
                        )
                        .contextMenu {
                            Button("重命名") { renamingCollection = collection }
                            Divider()
                            Button("删除集合", role: .destructive) {
                                store.deleteCollection(id: collection.id)
                                filter = .all
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            if !store.allTags.isEmpty {
                Divider().opacity(0.4)
                Text("标签")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.horizontal, 12)
                ScrollView {
                    VStack(spacing: 3) {
                        tagRow("全部标签", tag: nil)
                        ForEach(store.allTags, id: \.self) { tag in tagRow(tag, tag: tag) }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: 180)
            }
        }
        .background(AppTheme.bgSidebar.opacity(0.55))
    }

    private func collectionRow(title: String, count: Int, value: KnowledgeCollectionFilter, systemImage: String) -> some View {
        Button {
            filter = value
            selectedDocumentID = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 16)
                Text(title).lineLimit(1)
                Spacer()
                Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(filter == value ? AppTheme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func tagRow(_ title: String, tag: String?) -> some View {
        Button {
            selectedTag = tag
            selectedDocumentID = nil
        } label: {
            HStack {
                Image(systemName: "tag").font(.caption)
                Text(title).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selectedTag == tag ? AppTheme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var documentList: some View {
        VStack(spacing: 0) {
            TextField("搜索标题、标签或正文", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            Divider().opacity(0.4)
            if filteredDocuments.isEmpty {
                EmptyStateView(
                    title: "没有资料",
                    message: "导入文件、图片或新建一条笔记。",
                    systemImage: "doc.text.magnifyingglass"
                )
            } else {
                List(filteredDocuments, selection: $selectedDocumentID) { document in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: document.sourceKind == .note ? "note.text" : (isImageDocument(document) ? "photo" : "doc"))
                                .foregroundStyle(AppTheme.accent)
                            Text(document.title).font(.callout.weight(.medium)).lineLimit(1)
                            Spacer()
                            indexBadge(document.indexStatus)
                        }
                        if !document.tags.isEmpty {
                            Text(document.tags.map { "#\($0)" }.joined(separator: "  "))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(document.id)
                }
                .listStyle(.inset)
            }
        }
        .background(AppTheme.bgBase)
    }

    @ViewBuilder
    private var detail: some View {
        if let document = store.document(id: selectedDocumentID) {
            KnowledgeDocumentDetail(document: document) {
                store.deleteDocument(id: document.id)
                selectedDocumentID = nil
            }
            .id(document.id)
        } else {
            EmptyStateView(
                title: "选择一份资料",
                message: "可查看正文、编辑标签、打开原文件或重建索引。",
                systemImage: "books.vertical"
            )
        }
    }

    private func indexBadge(_ status: KnowledgeIndexStatus) -> some View {
        HStack(spacing: 4) {
            if status == .indexing { ProgressView().controlSize(.mini) }
            Circle()
                .fill(status == .ready ? AppTheme.success : (status == .failed ? Color.red : AppTheme.textTertiary))
                .frame(width: 6, height: 6)
        }
        .help(status.title)
    }

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .plainText, .json, .commaSeparatedText, .pdf, .rtf, .image,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "srt") ?? .plainText,
            UTType(filenameExtension: "vtt") ?? .plainText,
            UTType(filenameExtension: "fountain") ?? .plainText,
            UTType(filenameExtension: "docx") ?? .data,
        ]
        panel.prompt = "导入"
        guard panel.runModal() == .OK else { return }
        let summary = store.importFiles(panel.urls, collectionID: selectedCollectionID)
        statusMessage = "已导入 \(summary.createdIDs.count) 份，跳过 \(summary.skippedDuplicates) 份重复，失败 \(summary.failures.count) 份"
        if let first = summary.createdIDs.first { selectedDocumentID = first }
        Task {
            for id in summary.createdIDs { await store.indexDocument(id: id, settings: settings) }
        }
    }

    private func exportArchive() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "heiniukb") ?? .archive]
        panel.nameFieldStringValue = "黑妞短剧-知识库.heiniukb"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportArchive(to: url, settings: settings)
            statusMessage = "知识库归档已导出"
        } catch { statusMessage = error.localizedDescription }
    }

    private func importArchive(mode: KnowledgeArchiveImportMode) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "heiniukb") ?? .archive, .zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importArchive(from: url, mode: mode, settings: settings)
            selectedDocumentID = nil
            filter = .all
            statusMessage = mode == .merge ? "知识库已合并导入" : "知识库已替换"
        } catch { statusMessage = error.localizedDescription }
    }
}

private struct KnowledgeDocumentDetail: View {
    @Environment(KnowledgeStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    let document: KnowledgeDocument
    let onDelete: () -> Void

    @State private var title: String
    @State private var content: String
    @State private var collectionID: UUID?
    @State private var tags: String
    @State private var indexing = false

    init(document: KnowledgeDocument, onDelete: @escaping () -> Void) {
        self.document = document
        self.onDelete = onDelete
        _title = State(initialValue: document.title)
        _content = State(initialValue: document.content)
        _collectionID = State(initialValue: document.collectionID)
        _tags = State(initialValue: document.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(document.sourceKind == .note ? "知识笔记" : (document.sourceFileName ?? "知识文件"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(document.indexStatus.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(document.indexStatus == .ready ? AppTheme.success : AppTheme.textSecondary)
                }
                Spacer()
                if let file = store.originalFileURL(for: document) {
                    Button("打开原文件") { NSWorkspace.shared.open(file) }
                }
                Button(indexing ? "索引中…" : "重建索引") {
                    save(reindexIfContentChanged: false)
                    Task {
                        indexing = true
                        await store.indexDocument(id: document.id, settings: settings)
                        indexing = false
                    }
                }
                .disabled(indexing)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .foregroundStyle(.black)
                Button("删除", role: .destructive, action: onDelete)
            }
            .padding(16)
            Divider().opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("标题", text: $title)
                        .font(.title3.weight(.semibold))
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Picker("集合", selection: $collectionID) {
                            Text("未分类").tag(Optional<UUID>.none)
                            ForEach(store.collections) { collection in
                                Text(collection.name).tag(Optional(collection.id))
                            }
                        }
                        TextField("标签，用逗号分隔", text: $tags)
                            .textFieldStyle(.roundedBorder)
                    }
                    if let error = document.indexError, !error.isEmpty {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    if let image = originalImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 360)
                            .padding(10)
                            .background(AppTheme.bgCard, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.stroke))
                            .accessibilityLabel("原始图片预览")
                    }
                    TextEditor(text: $content)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 420)
                        .background(AppTheme.bgCard, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.stroke))
                }
                .padding(20)
            }
        }
    }

    private var originalImage: NSImage? {
        guard isImageDocument(document),
              let file = store.originalFileURL(for: document)
        else { return nil }
        return NSImage(contentsOf: file)
    }

    private func save(reindexIfContentChanged: Bool = true) {
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentChanged = cleaned != document.content
        store.updateDocument(
            id: document.id,
            title: title,
            content: content,
            collectionID: collectionID,
            tags: tags.components(separatedBy: CharacterSet(charactersIn: ",，"))
        )
        if reindexIfContentChanged && contentChanged {
            Task {
                indexing = true
                await store.indexDocument(id: document.id, settings: settings)
                indexing = false
            }
        }
    }
}

/// 判断知识资料的原文件是否为图片。
private func isImageDocument(_ document: KnowledgeDocument) -> Bool {
    guard let sourceFileName = document.sourceFileName,
          let type = UTType(filenameExtension: URL(fileURLWithPath: sourceFileName).pathExtension)
    else { return false }
    return type.conforms(to: .image)
}

private struct CollectionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actionTitle: String
    @State private var name: String
    let onSave: (String) -> Void

    init(title: String, actionTitle: String, initialName: String = "", onSave: @escaping (String) -> Void) {
        self.title = title
        self.actionTitle = actionTitle
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField("集合名称", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(actionTitle) { onSave(name); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 380)
    }
}

private struct KnowledgeNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let collections: [KnowledgeCollection]
    let initialCollectionID: UUID?
    let onSave: (String, String, UUID?, [String]) -> Void

    @State private var title = ""
    @State private var content = ""
    @State private var collectionID: UUID?
    @State private var tags = ""

    init(collections: [KnowledgeCollection], initialCollectionID: UUID?, onSave: @escaping (String, String, UUID?, [String]) -> Void) {
        self.collections = collections
        self.initialCollectionID = initialCollectionID
        self.onSave = onSave
        _collectionID = State(initialValue: initialCollectionID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建知识笔记").font(.headline)
            TextField("标题", text: $title).textFieldStyle(.roundedBorder)
            HStack {
                Picker("集合", selection: $collectionID) {
                    Text("未分类").tag(Optional<UUID>.none)
                    ForEach(collections) { item in Text(item.name).tag(Optional(item.id)) }
                }
                TextField("标签，用逗号分隔", text: $tags).textFieldStyle(.roundedBorder)
            }
            TextEditor(text: $content)
                .font(.body)
                .frame(minHeight: 300)
                .padding(8)
                .background(AppTheme.bgCard, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    onSave(title, content, collectionID, tags.components(separatedBy: CharacterSet(charactersIn: ",，")))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 680, height: 520)
    }
}
