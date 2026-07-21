/// 项目引用全局知识库的选择器。

import SwiftUI

struct ProjectKnowledgePicker: View {
    @Environment(KnowledgeStore.self) private var knowledge
    @Environment(\.dismiss) private var dismiss

    let project: ProjectItem
    let onSave: (ProjectItem) -> Void

    @State private var selectedCollections: Set<UUID>
    @State private var selectedDocuments: Set<UUID>
    @State private var searchText = ""

    init(project: ProjectItem, onSave: @escaping (ProjectItem) -> Void) {
        self.project = project
        self.onSave = onSave
        _selectedCollections = State(initialValue: Set(project.knowledgeCollectionIDs))
        _selectedDocuments = State(initialValue: Set(project.knowledgeDocumentIDs))
    }

    private var filteredDocuments: [KnowledgeDocument] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return knowledge.documents }
        return knowledge.documents.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("项目知识库").font(.title2.weight(.semibold))
                    Text("选择集合或单条资料；生成时只检索这里勾选的内容。")
                        .font(.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .foregroundStyle(.black)
            }
            .padding(20)
            Divider().opacity(0.45)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("按集合引用")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                    if knowledge.collections.isEmpty {
                        Text("暂无集合")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                            .padding(14)
                    } else {
                        List(knowledge.collections) { collection in
                            toggleRow(
                                title: collection.name,
                                subtitle: "\(knowledge.documents(in: collection.id).count) 份资料",
                                selected: selectedCollections.contains(collection.id)
                            ) {
                                toggle(collection.id, in: &selectedCollections)
                            }
                        }
                        .listStyle(.inset)
                    }
                }
                .frame(width: 280)

                Divider().opacity(0.45)

                VStack(alignment: .leading, spacing: 8) {
                    Text("单条资料")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                    TextField("搜索资料", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 14)
                    List(filteredDocuments) { document in
                        let coveredByCollection = document.collectionID.map(selectedCollections.contains) ?? false
                        toggleRow(
                            title: document.title,
                            subtitle: coveredByCollection ? "已由集合包含" : document.indexStatus.title,
                            selected: selectedDocuments.contains(document.id) || coveredByCollection
                        ) {
                            if !coveredByCollection { toggle(document.id, in: &selectedDocuments) }
                        }
                        .disabled(coveredByCollection)
                    }
                    .listStyle(.inset)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(AppTheme.bgBase)
    }

    private func toggleRow(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? AppTheme.accent : AppTheme.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(AppTheme.textPrimary).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(AppTheme.textTertiary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func save() {
        var updated = project
        updated.knowledgeCollectionIDs = Array(selectedCollections)
        updated.knowledgeDocumentIDs = Array(selectedDocuments).filter { id in
            guard let document = knowledge.document(id: id) else { return false }
            return !(document.collectionID.map(selectedCollections.contains) ?? false)
        }
        onSave(updated)
    }
}
