/// 节点工作流模块入口、模板列表、运行前检查与画布编排。

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 全局节点式工作流工作台。
struct WorkflowHomeView: View {
    @Environment(WorkflowStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(KnowledgeStore.self) private var knowledge

    @State private var executor = WorkflowExecutor()
    @State private var selectedWorkflowID: UUID?
    @State private var selectedNodeID: UUID?
    @State private var selectedConnectionID: UUID?
    @State private var inspectorTab: WorkflowInspectorTab = .configuration
    @State private var selectedHistoryRunID: UUID?
    @State private var runRequest: WorkflowRunRequest?
    @State private var workflowToRename: WorkflowDefinition?
    @State private var workflowToDelete: WorkflowDefinition?
    @State private var showValidation = false
    @State private var showClearHistoryConfirmation = false

    private var workflow: WorkflowDefinition? { store.workflow(id: selectedWorkflowID) }
    private var selectedNode: WorkflowNode? {
        workflow?.nodes.first { $0.id == selectedNodeID }
    }
    private var activeRun: WorkflowRun? {
        guard store.activeRun?.workflowID == selectedWorkflowID else { return nil }
        return store.activeRun
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            HStack(spacing: 0) {
                workflowSidebar
                    .frame(width: 210)
                Divider().opacity(0.45)
                if let workflow {
                    WorkflowCanvasView(
                        workflow: workflow,
                        activeRun: activeRun,
                        selectedNodeID: $selectedNodeID,
                        selectedConnectionID: $selectedConnectionID,
                        inspectorTab: $inspectorTab,
                        onUpdateNode: { store.updateNode($0, in: workflow.id) },
                        onDeleteNode: { id in
                            store.deleteNode(id: id, in: workflow.id)
                            if selectedNodeID == id { selectedNodeID = nil }
                        },
                        onDeleteConnection: { store.deleteConnection(id: $0, in: workflow.id) },
                        onConnect: { sourceID, sourcePort, targetID, targetPort in
                            connect(
                                sourceID: sourceID,
                                sourcePort: sourcePort,
                                targetID: targetID,
                                targetPort: targetPort,
                                workflowID: workflow.id
                            )
                        },
                        onUpdateViewport: { viewport in
                            store.mutateWorkflow(id: workflow.id) { $0.viewport = viewport }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider().opacity(0.45)

                    WorkflowInspectorView(
                        workflow: workflow,
                        node: selectedNode,
                        tab: $inspectorTab,
                        selectedHistoryRunID: $selectedHistoryRunID,
                        onUpdateNode: { store.updateNode($0, in: workflow.id) },
                        onRunSelectedNode: requestSelectedNodeRun,
                        onDeleteRun: { store.deleteRun(workflowID: workflow.id, runID: $0) },
                        onDeleteAllRuns: { showClearHistoryConfirmation = true }
                    )
                    .frame(width: 340)
                } else {
                    EmptyStateView(
                        title: "还没有工作流",
                        message: "新建空白工作流，或从短剧创作入门模板开始。",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        actionTitle: "新建入门工作流",
                        action: addStarterWorkflow
                    )
                }
            }
        }
        .background(AppTheme.bgBase)
        .onAppear {
            if selectedWorkflowID == nil { selectWorkflow(store.workflows.first?.id) }
        }
        .onChange(of: selectedWorkflowID) { _, id in
            selectedNodeID = nil
            selectedConnectionID = nil
            selectedHistoryRunID = nil
            if let id { store.loadRuns(workflowID: id) }
        }
        .sheet(item: $runRequest) { request in
            if let workflow = store.workflow(id: request.workflowID) {
                WorkflowRunPreflightSheet(
                    workflow: workflow,
                    targetNodeID: request.targetNodeID,
                    onRun: { values in
                        executor.start(
                            workflow: workflow,
                            targetNodeID: request.targetNodeID,
                            runtimeInputs: values,
                            settings: settings,
                            knowledge: knowledge,
                            store: store
                        )
                        inspectorTab = .run
                    }
                )
            }
        }
        .sheet(item: $workflowToRename) { workflow in
            WorkflowNameSheet(title: "重命名工作流", initialName: workflow.name) { name in
                store.renameWorkflow(id: workflow.id, name: name)
            }
        }
        .sheet(isPresented: $showValidation) {
            if let workflow {
                WorkflowValidationSheet(
                    issues: WorkflowValidator.validate(workflow, settings: settings)
                ) { nodeID in
                    selectedNodeID = nodeID
                    inspectorTab = .configuration
                }
            }
        }
        .confirmationDialog(
            "删除工作流“\(workflowToDelete?.name ?? "")”？",
            isPresented: Binding(
                get: { workflowToDelete != nil },
                set: { if !$0 { workflowToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除工作流和全部历史", role: .destructive) {
                if let id = workflowToDelete?.id {
                    store.deleteWorkflow(id: id)
                    selectWorkflow(store.workflows.first?.id)
                }
                workflowToDelete = nil
            }
            Button("取消", role: .cancel) { workflowToDelete = nil }
        } message: {
            Text("该工作流的运行记录、图片和视频也会被删除，无法撤销。")
        }
        .confirmationDialog(
            "清空此工作流的全部运行历史？",
            isPresented: $showClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空历史和媒体", role: .destructive) {
                if let id = workflow?.id { store.deleteAllRuns(workflowID: id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("工作流模板会保留，所有运行结果和媒体文件会被删除。")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("工作流")
                    .font(.largeTitle.weight(.bold))
                Text(workflow?.name ?? "节点式创作编排")
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            if let message = executor.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(executor.validationIssues.contains { $0.severity == .error } ? AppTheme.danger : AppTheme.textTertiary)
                    .lineLimit(1)
            }
            if let workflow {
                Menu {
                    ForEach(WorkflowNodeCatalog.all) { descriptor in
                        Button {
                            addNode(descriptor.kind, workflow: workflow)
                        } label: {
                            Label(descriptor.title, systemImage: descriptor.systemImage)
                        }
                    }
                } label: {
                    Label("添加节点", systemImage: "plus.square.on.square")
                }
                .help("向画布添加原子能力节点")

                Button {
                    executor.validationIssues = WorkflowValidator.validate(workflow, settings: settings)
                    showValidation = true
                } label: {
                    Label("检查", systemImage: "checkmark.shield")
                }

                if executor.isRunning {
                    Button(role: .destructive, action: executor.cancel) {
                        Label("停止", systemImage: "stop.fill")
                    }
                } else {
                    Button(action: requestSelectedNodeRun) {
                        Label("运行节点", systemImage: "play.square")
                    }
                    .disabled(selectedNodeID == nil)

                    Button {
                        runRequest = WorkflowRunRequest(workflowID: workflow.id, targetNodeID: nil)
                    } label: {
                        Label("运行全部", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .foregroundStyle(.black)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Workflow list

    private var workflowSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("工作流模板")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                Spacer()
                Menu {
                    Button("空白工作流", action: addBlankWorkflow)
                    Button("入门工作流", action: addStarterWorkflow)
                } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton)
                .help("新建工作流")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(store.workflows) { item in
                        Button {
                            selectWorkflow(item.id)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                                    .foregroundStyle(selectedWorkflowID == item.id ? AppTheme.accent : AppTheme.textSecondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).font(.callout.weight(.medium)).lineLimit(1)
                                    Text("\(item.nodes.count) 节点 · \(store.runsByWorkflowID[item.id]?.count ?? 0) 次运行")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.textTertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 8)
                            .background(
                                selectedWorkflowID == item.id ? AppTheme.accentSoft : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("重命名") { workflowToRename = item }
                            Button("复制") {
                                if let id = store.duplicateWorkflow(id: item.id) { selectWorkflow(id) }
                            }
                            Divider()
                            Button("删除", role: .destructive) { workflowToDelete = item }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 6) {
                Label("全局模板，不属于任何项目", systemImage: "info.circle")
                Text("定义自动保存；运行媒体单独保存在 Workflows/Runs。")
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.textTertiary)
            .padding(12)
        }
        .background(AppTheme.bgSidebar.opacity(0.7))
    }

    private func selectWorkflow(_ id: UUID?) {
        selectedWorkflowID = id
        if let id { store.loadRuns(workflowID: id) }
    }

    private func addBlankWorkflow() {
        selectWorkflow(store.addWorkflow())
    }

    private func addStarterWorkflow() {
        selectWorkflow(store.addStarterWorkflow())
    }

    private func addNode(_ kind: WorkflowNodeKind, workflow: WorkflowDefinition) {
        let count = workflow.nodes.count
        let column = count % 4
        let row = count / 4
        if let id = store.addNode(
            kind: kind,
            to: workflow.id,
            at: WorkflowPoint(x: 100 + Double(column * 290), y: 100 + Double(row * 190))
        ) {
            selectedNodeID = id
            selectedConnectionID = nil
            inspectorTab = .configuration
        }
    }

    private func requestSelectedNodeRun() {
        guard let workflow, let selectedNodeID else { return }
        runRequest = WorkflowRunRequest(workflowID: workflow.id, targetNodeID: selectedNodeID)
    }

    /// 连接前把提示词库最新正文写回快照，使动态变量端口与持久化校验保持一致。
    private func connect(
        sourceID: UUID,
        sourcePort: String,
        targetID: UUID,
        targetPort: String,
        workflowID: UUID
    ) -> String? {
        for nodeID in Set([sourceID, targetID]) {
            guard let node = store.workflow(id: workflowID)?.nodes.first(where: { $0.id == nodeID }),
                  node.kind == .promptTemplate,
                  node.configuration.usesPromptLibrary
            else { continue }
            let effective = WorkflowValidator.effectiveNode(node, settings: settings)
            if effective.configuration.promptSnapshot != node.configuration.promptSnapshot {
                store.updateNode(effective, in: workflowID)
            }
        }
        switch store.addConnection(
            sourceNodeID: sourceID,
            sourcePortID: sourcePort,
            targetNodeID: targetID,
            targetPortID: targetPort,
            in: workflowID
        ) {
        case .success: return nil
        case .failure(let error): return error.localizedDescription
        }
    }
}

/// 一次等待用户确认的运行请求。
private struct WorkflowRunRequest: Identifiable {
    var id = UUID()
    var workflowID: UUID
    var targetNodeID: UUID?
}

// MARK: - Preflight

private struct WorkflowRunPreflightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @Environment(KnowledgeStore.self) private var knowledge

    let workflow: WorkflowDefinition
    let targetNodeID: UUID?
    let onRun: ([String: WorkflowValue]) -> Void

    @State private var values: [String: WorkflowValue]
    @State private var promptSelections: [UUID: UUID] = [:]

    init(
        workflow: WorkflowDefinition,
        targetNodeID: UUID?,
        onRun: @escaping ([String: WorkflowValue]) -> Void
    ) {
        self.workflow = workflow
        self.targetNodeID = targetNodeID
        self.onRun = onRun
        let relevant = WorkflowGraphAnalysis.upstreamClosure(targetNodeID: targetNodeID, in: workflow)
        let ids = targetNodeID == nil ? Set(workflow.nodes.map(\.id)) : relevant
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: workflow.nodes.compactMap { node in
            guard ids.contains(node.id), node.kind == .runtimeInput else { return nil }
            switch node.configuration.runtimeInputType {
            case .text:
                return (node.id.uuidString, WorkflowValue.text(node.configuration.text))
            case .knowledgeCollection:
                return (
                    node.id.uuidString,
                    WorkflowValue.knowledgeCollection(node.configuration.collectionID?.uuidString ?? "")
                )
            case .prompt, .image, .video, .audio, .folder:
                return nil
            }
        }))
    }

    private var issues: [WorkflowValidationIssue] {
        WorkflowValidator.validate(
            WorkflowGraphAnalysis.scopedWorkflow(targetNodeID: targetNodeID, in: workflow),
            settings: settings
        )
    }

    private var estimate: WorkflowCostEstimate {
        WorkflowValidator.estimateCosts(
            WorkflowGraphAnalysis.scopedWorkflow(targetNodeID: targetNodeID, in: workflow)
        )
    }

    private var inputNodes: [WorkflowNode] {
        let ids: Set<UUID> = targetNodeID.map {
            WorkflowGraphAnalysis.upstreamClosure(targetNodeID: $0, in: workflow)
        } ?? Set(workflow.nodes.map(\.id))
        return workflow.nodes.filter { ids.contains($0.id) && $0.kind == .runtimeInput }
    }

    private var hasBlockingError: Bool {
        issues.contains { $0.severity == .error } || inputNodes.contains { node in
            node.configuration.isRequired &&
            (runtimeValue(for: node)?.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(targetNodeID == nil ? "运行工作流" : "运行选中节点")
                        .font(.title2.weight(.semibold))
                    Text(workflow.name).foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("开始运行") {
                    onRun(valuesWithPromptInputs())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .foregroundStyle(.black)
                .disabled(hasBlockingError)
            }
            .padding(18)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !inputNodes.isEmpty {
                        preflightSection("本次输入") {
                            ForEach(inputNodes) { node in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(node.configuration.parameterName).font(.callout.weight(.semibold))
                                        if node.configuration.isRequired {
                                            Text("必填").font(.caption2).foregroundStyle(AppTheme.danger)
                                        }
                                    }
                                    if node.configuration.runtimeInputType == .prompt {
                                        Picker("提示词", selection: promptSelectionBinding(for: node.id)) {
                                            Text(defaultPromptLabel(for: node)).tag(Optional<UUID>.none)
                                            ForEach(settings.prompts(in: node.configuration.promptCategory)) { item in
                                                Text(item.name).tag(Optional(item.id))
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        Text(promptPreview(for: node))
                                            .font(.caption.monospaced())
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .lineLimit(5)
                                            .textSelection(.enabled)
                                        Text("本次选择从这个输入节点输出，不会修改节点默认值。")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.textTertiary)
                                    } else if node.configuration.runtimeInputType == .knowledgeCollection {
                                        Picker("知识集合", selection: collectionSelectionBinding(for: node.id)) {
                                            Text("未分类").tag(Optional<UUID>.none)
                                            ForEach(knowledge.collections) { collection in
                                                Text(collection.name).tag(Optional(collection.id))
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        Text("本次选择从这个输入节点输出，不会修改节点默认值。")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.textTertiary)
                                    } else if node.configuration.runtimeInputType == .text {
                                        TextEditor(text: Binding(
                                            get: {
                                                guard case .text(let text) = values[node.id.uuidString] else { return "" }
                                                return text
                                            },
                                            set: { values[node.id.uuidString] = .text($0) }
                                        ))
                                        .font(.callout)
                                        .frame(minHeight: 74)
                                        .padding(5)
                                        .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 7))
                                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.stroke))
                                    } else {
                                        HStack {
                                            Image(systemName: mediaIcon(node.configuration.runtimeInputType))
                                                .foregroundStyle(AppTheme.accent)
                                            Text(selectedItemName(node))
                                                .foregroundStyle(values[node.id.uuidString] == nil ? AppTheme.textTertiary : AppTheme.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            Button(values[node.id.uuidString] == nil
                                                   ? (node.configuration.runtimeInputType == .folder ? "选择文件夹" : "选择文件")
                                                   : "重新选择") {
                                                chooseMedia(for: node)
                                            }
                                        }
                                        .padding(10)
                                        .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 7))
                                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.stroke))
                                        Text(node.configuration.runtimeInputType == .folder
                                             ? "文件夹会复制到本次运行的 Assets；运行记录不会保存原始绝对路径。"
                                             : "文件会复制到本次运行的 Assets；运行记录不会保存原始绝对路径。")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.textTertiary)
                                    }
                                }
                            }
                        }
                    }

                    preflightSection("最大调用次数估计") {
                        HStack(spacing: 18) {
                            costBadge("LLM", estimate.llmCalls, "sparkles")
                            costBadge("生图", estimate.imageCalls, "photo")
                            costBadge("视频", estimate.videoCalls, "video")
                        }
                        Text("循环中的节点按最大次数计算。这里显示调用次数，不代表实际金额。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    preflightSection("检查结果") {
                        if issues.isEmpty {
                            Label("配置和图结构检查通过", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.success)
                        } else {
                            ForEach(issues) { issue in
                                Label(issue.message, systemImage: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(issue.severity == .error ? AppTheme.danger : .orange)
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 620, height: 620)
    }

    private func costBadge(_ title: String, _ count: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption)
            Text("最多 \(count) 次").font(.headline.monospacedDigit())
        }
        .padding(10)
        .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 8))
    }

    private func promptSelectionBinding(for nodeID: UUID) -> Binding<UUID?> {
        Binding(
            get: { promptSelections[nodeID] },
            set: { selection in
                if let selection {
                    promptSelections[nodeID] = selection
                } else {
                    promptSelections.removeValue(forKey: nodeID)
                }
            }
        )
    }

    private func collectionSelectionBinding(for nodeID: UUID) -> Binding<UUID?> {
        Binding(
            get: {
                guard case .knowledgeCollection(let raw) = values[nodeID.uuidString] else { return nil }
                return UUID(uuidString: raw)
            },
            set: { selection in
                values[nodeID.uuidString] = .knowledgeCollection(selection?.uuidString ?? "")
            }
        )
    }

    private func defaultPromptLabel(for node: WorkflowNode) -> String {
        if let item = settings.promptItem(id: node.configuration.promptItemID) {
            return "使用节点默认 · \(item.name)"
        }
        if node.configuration.promptItemID == nil {
            let items = settings.prompts(in: node.configuration.promptCategory)
            let preferred = node.configuration.promptCategory == .knowledgeImport
                ? items.first(where: { $0.name == DefaultPrompts.knowledgeImportPromptName }) ?? items.first
                : items.first
            if let preferred { return "使用节点默认 · \(preferred.name)" }
        }
        return "使用节点保存的提示词快照"
    }

    private func promptPreview(for node: WorkflowNode) -> String {
        if let itemID = promptSelections[node.id], let item = settings.promptItem(id: itemID) {
            return item.template
        }
        return WorkflowValidator.resolvedRuntimePrompt(for: node, settings: settings).template
    }

    private func valuesWithPromptInputs() -> [String: WorkflowValue] {
        var result = values
        for node in inputNodes where node.configuration.runtimeInputType == .prompt {
            if let value = runtimeValue(for: node) {
                result[node.id.uuidString] = value
            }
        }
        return result
    }

    private func runtimeValue(for node: WorkflowNode) -> WorkflowValue? {
        if node.configuration.runtimeInputType == .prompt {
            if let itemID = promptSelections[node.id], let item = settings.promptItem(id: itemID) {
                return .text(item.template)
            }
            return .text(WorkflowValidator.resolvedRuntimePrompt(for: node, settings: settings).template)
        }
        return values[node.id.uuidString]
    }

    private func selectedItemName(_ node: WorkflowNode) -> String {
        guard let value = values[node.id.uuidString] else {
            return node.configuration.runtimeInputType == .folder ? "尚未选择文件夹" : "尚未选择文件"
        }
        return URL(fileURLWithPath: value.payload).lastPathComponent
    }

    private func mediaIcon(_ type: WorkflowRuntimeInputType) -> String {
        switch type {
        case .text: "text.cursor"
        case .prompt: "text.quote"
        case .knowledgeCollection: "books.vertical"
        case .image: "photo"
        case .video: "video"
        case .audio: "waveform"
        case .folder: "folder"
        }
    }

    private func chooseMedia(for node: WorkflowNode) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        let choosesFolder = node.configuration.runtimeInputType == .folder
        panel.canChooseDirectories = choosesFolder
        panel.canChooseFiles = !choosesFolder
        switch node.configuration.runtimeInputType {
        case .text, .prompt, .knowledgeCollection:
            return
        case .image:
            panel.allowedContentTypes = [.image]
        case .video:
            panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        case .audio:
            panel.allowedContentTypes = [.audio]
        case .folder:
            break
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch node.configuration.runtimeInputType {
        case .text, .prompt, .knowledgeCollection: break
        case .image: values[node.id.uuidString] = .image(url.path)
        case .video: values[node.id.uuidString] = .video(url.path)
        case .audio: values[node.id.uuidString] = .audio(url.path)
        case .folder: values[node.id.uuidString] = .folder(url.path)
        }
    }
}

// MARK: - Supporting sheets

private struct WorkflowNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (String) -> Void
    @State private var name: String

    init(title: String, initialName: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.semibold))
            TextField("工作流名称", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct WorkflowValidationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let issues: [WorkflowValidationIssue]
    let onSelectNode: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("工作流检查").font(.title2.weight(.semibold))
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(18)
            Divider()
            if issues.isEmpty {
                EmptyStateView(
                    title: "检查通过",
                    message: "端口、配置和环路结构均可运行。",
                    systemImage: "checkmark.shield.fill"
                )
            } else {
                List(issues) { issue in
                    Button {
                        if let id = issue.nodeIDs.first {
                            onSelectNode(id)
                            dismiss()
                        }
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(issue.severity == .error ? AppTheme.danger : .orange)
                            Text(issue.message).multilineTextAlignment(.leading)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 560, height: 440)
    }
}

private func preflightSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title).font(.headline)
        content()
    }
    .padding(13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppTheme.bgCard, in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.stroke))
}

#Preview {
    WorkflowHomeView()
        .environment(SettingsStore())
        .environment(KnowledgeStore())
        .environment(WorkflowStore())
        .frame(width: 1400, height: 820)
}
