/// 工作流模板、画布状态和完整运行历史的本地仓库。

import Foundation
import Observation

/// 工作流持久化或编辑错误。
enum WorkflowStoreError: LocalizedError {
    case missingWorkflow
    case missingNode
    case readOnlyBuiltIn
    case invalidConnection(String)

    var errorDescription: String? {
        switch self {
        case .missingWorkflow: "工作流不存在"
        case .missingNode: "节点不存在"
        case .readOnlyBuiltIn: "内置工作流不可编辑，请先复制"
        case .invalidConnection(let message): message
        }
    }
}

/// 全局工作流仓库。
@Observable
@MainActor
final class WorkflowStore {
    /// 全部可复用工作流模板。
    var workflows: [WorkflowDefinition] = []
    /// 按工作流分组的运行历史，最新记录在前。
    var runsByWorkflowID: [UUID: [WorkflowRun]] = [:]
    /// 当前正在执行或刚完成的运行。
    var activeRun: WorkflowRun?
    /// 最近一次可展示错误。
    var lastError: String?

    @ObservationIgnored private let debouncer = DebouncedAction()
    @ObservationIgnored private let definitionsURL: URL
    @ObservationIgnored private let runsRootURL: URL
    @ObservationIgnored private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    @ObservationIgnored private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// 加载模板；首次启动创建一个可编辑的入门模板。
    ///
    /// - Parameter rootURL: 测试可注入隔离目录；生产环境默认使用 `Application Support/HeiNiu/Workflows`。
    init(rootURL: URL? = nil) {
        let resolvedRoot = rootURL ?? AppPaths.workflowsRoot
        definitionsURL = resolvedRoot.appendingPathComponent("workflows.json", isDirectory: false)
        runsRootURL = resolvedRoot.appendingPathComponent("Runs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: runsRootURL, withIntermediateDirectories: true)
        } catch {
            lastError = error.localizedDescription
        }
        loadDefinitions()
    }

    /// 按 ID 查找工作流。
    func workflow(id: UUID?) -> WorkflowDefinition? {
        guard let id else { return nil }
        return workflows.first { $0.id == id }
    }

    /// 新建空白工作流。
    @discardableResult
    func addWorkflow(named name: String = "新工作流") -> UUID {
        let uniqueName = availableName(base: name)
        let item = WorkflowDefinition(name: uniqueName)
        workflows.append(item)
        scheduleSave()
        return item.id
    }

    /// 新建带入门节点的工作流。
    @discardableResult
    func addStarterWorkflow() -> UUID {
        var item = WorkflowDefinition.starter(named: availableName(base: "短剧创作入门"))
        item.updatedAt = Date()
        workflows.append(item)
        scheduleSave()
        return item.id
    }

    /// 重命名工作流。
    func renameWorkflow(id: UUID, name: String) {
        guard let index = editableWorkflowIndex(id: id) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        workflows[index].name = clean
        workflows[index].updatedAt = Date()
        scheduleSave()
    }

    /// 复制定义但不复制运行历史。
    @discardableResult
    func duplicateWorkflow(id: UUID) -> UUID? {
        guard let source = workflow(id: id) else { return nil }
        let newID = UUID()
        let nodeMap = Dictionary(uniqueKeysWithValues: source.nodes.map { ($0.id, UUID()) })
        let nodes = source.nodes.map { node -> WorkflowNode in
            var copy = node
            copy.id = nodeMap[node.id]!
            copy.createdAt = Date()
            return copy
        }
        let connections = source.connections.compactMap { connection -> WorkflowConnection? in
            guard let sourceID = nodeMap[connection.sourceNodeID],
                  let targetID = nodeMap[connection.targetNodeID]
            else { return nil }
            return WorkflowConnection(
                sourceNodeID: sourceID,
                sourcePortID: connection.sourcePortID,
                targetNodeID: targetID,
                targetPortID: connection.targetPortID,
                targetOrder: connection.targetOrder
            )
        }
        let copy = WorkflowDefinition(
            id: newID,
            name: availableName(base: source.name + " 副本"),
            isBuiltIn: false,
            nodes: nodes,
            connections: connections,
            viewport: source.viewport
        )
        workflows.append(copy)
        scheduleSave()
        return newID
    }

    /// 删除工作流及其全部运行历史和媒体。
    func deleteWorkflow(id: UUID) {
        guard editableWorkflowIndex(id: id) != nil else { return }
        workflows.removeAll { $0.id == id }
        runsByWorkflowID[id] = nil
        if activeRun?.workflowID == id { activeRun = nil }
        let directory = runsRootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        } catch {
            lastError = error.localizedDescription
        }
        scheduleSave()
    }

    /// 用一份完整的新定义替换工作流。
    func updateWorkflow(_ workflow: WorkflowDefinition) {
        guard let index = editableWorkflowIndex(id: workflow.id) else { return }
        var updated = workflow
        updated.isBuiltIn = false
        updated.updatedAt = Date()
        workflows[index] = updated
        scheduleSave()
    }

    /// 修改工作流定义并自动保存。
    func mutateWorkflow(id: UUID, _ mutation: (inout WorkflowDefinition) -> Void) {
        guard let index = editableWorkflowIndex(id: id) else { return }
        mutation(&workflows[index])
        workflows[index].updatedAt = Date()
        scheduleSave()
    }

    /// 添加节点并返回 ID。
    @discardableResult
    func addNode(kind: WorkflowNodeKind, to workflowID: UUID, at position: WorkflowPoint) -> UUID? {
        guard let index = editableWorkflowIndex(id: workflowID) else { return nil }
        var configuration = WorkflowNodeConfiguration()
        switch kind {
        case .runtimeInput:
            configuration.parameterName = "输入 \(workflows[index].nodes.filter { $0.kind == .runtimeInput }.count + 1)"
        case .promptTemplate:
            configuration.text = "请处理以下内容：\n\n{{input}}"
        case .llm:
            configuration.temperature = PromptItem.defaultTemperature
        case .knowledgeImport:
            configuration.temperature = 0.2
            configuration.maxFiles = 50
        case .imageGeneration:
            configuration.mediaSize = ImageProvider.defaultSize
        case .videoGeneration:
            configuration.mediaSize = "720x1280"
            configuration.videoResolution = "720P"
            configuration.durationSeconds = 4
        case .loop:
            configuration.comparison = .contains
            configuration.comparisonValue = "完成"
            configuration.maxIterations = 3
        default:
            break
        }
        let node = WorkflowNode(kind: kind, position: position, configuration: configuration)
        workflows[index].nodes.append(node)
        workflows[index].updatedAt = Date()
        scheduleSave()
        return node.id
    }

    /// 更新节点配置或位置。
    func updateNode(_ node: WorkflowNode, in workflowID: UUID) {
        mutateWorkflow(id: workflowID) { workflow in
            guard let index = workflow.nodes.firstIndex(where: { $0.id == node.id }) else { return }
            let oldInputPortIDs = Set(workflow.nodes[index].descriptor.ports(for: workflow.nodes[index]).filter { $0.direction == .input }.map(\.id))
            let oldOutputPortIDs = Set(workflow.nodes[index].descriptor.ports(for: workflow.nodes[index]).filter { $0.direction == .output }.map(\.id))
            workflow.nodes[index] = node
            let newInputPortIDs = Set(node.descriptor.ports(for: node).filter { $0.direction == .input }.map(\.id))
            let newOutputPortIDs = Set(node.descriptor.ports(for: node).filter { $0.direction == .output }.map(\.id))
            if oldInputPortIDs != newInputPortIDs {
                workflow.connections.removeAll {
                    $0.targetNodeID == node.id && !newInputPortIDs.contains($0.targetPortID)
                }
            }
            if oldOutputPortIDs != newOutputPortIDs {
                workflow.connections.removeAll {
                    $0.sourceNodeID == node.id && !newOutputPortIDs.contains($0.sourcePortID)
                }
            }
        }
    }

    /// 删除节点和所有相关连线。
    func deleteNode(id nodeID: UUID, in workflowID: UUID) {
        mutateWorkflow(id: workflowID) { workflow in
            workflow.nodes.removeAll { $0.id == nodeID }
            workflow.connections.removeAll { $0.sourceNodeID == nodeID || $0.targetNodeID == nodeID }
        }
    }

    /// 添加经过端口类型检查的连线。
    @discardableResult
    func addConnection(
        sourceNodeID: UUID,
        sourcePortID: String,
        targetNodeID: UUID,
        targetPortID: String,
        in workflowID: UUID
    ) -> Result<UUID, WorkflowStoreError> {
        guard let workflowIndex = workflows.firstIndex(where: { $0.id == workflowID }) else {
            return .failure(.missingWorkflow)
        }
        var workflow = workflows[workflowIndex]
        guard !workflow.isBuiltIn else {
            lastError = WorkflowStoreError.readOnlyBuiltIn.localizedDescription
            return .failure(.readOnlyBuiltIn)
        }
        guard sourceNodeID != targetNodeID,
              let source = workflow.nodes.first(where: { $0.id == sourceNodeID }),
              let target = workflow.nodes.first(where: { $0.id == targetNodeID })
        else { return .failure(.invalidConnection("不能把节点连接到自身")) }
        guard let sourcePort = source.descriptor.ports(for: source).first(where: { $0.id == sourcePortID && $0.direction == .output }),
              let targetPort = target.descriptor.ports(for: target).first(where: { $0.id == targetPortID && $0.direction == .input })
        else { return .failure(.invalidConnection("端口不存在或方向错误")) }
        guard sourcePort.valueType.canConnect(to: targetPort.valueType) else {
            return .failure(.invalidConnection("\(sourcePort.valueType.title)不能连接到\(targetPort.valueType.title)"))
        }
        guard !workflow.connections.contains(where: {
            $0.sourceNodeID == sourceNodeID && $0.sourcePortID == sourcePortID &&
            $0.targetNodeID == targetNodeID && $0.targetPortID == targetPortID
        }) else { return .failure(.invalidConnection("这条连线已经存在")) }

        let siblings = workflow.connections.filter {
            $0.targetNodeID == targetNodeID && $0.targetPortID == targetPortID
        }
        guard siblings.count < targetPort.maxConnections else {
            return .failure(.invalidConnection(
                targetPort.maxConnections == 1
                    ? "每个输入端口只能连接一条线"
                    : "“\(targetPort.title)”最多连接 \(targetPort.maxConnections) 条线"
            ))
        }
        let nextOrder = (siblings.map(\.targetOrder).max() ?? -1) + 1

        let connection = WorkflowConnection(
            sourceNodeID: sourceNodeID,
            sourcePortID: sourcePortID,
            targetNodeID: targetNodeID,
            targetPortID: targetPortID,
            targetOrder: nextOrder
        )
        workflow.connections.append(connection)
        workflow.updatedAt = Date()
        workflows[workflowIndex] = workflow
        scheduleSave()
        return .success(connection.id)
    }

    /// 删除一条连线。
    func deleteConnection(id: UUID, in workflowID: UUID) {
        mutateWorkflow(id: workflowID) { workflow in
            workflow.connections.removeAll { $0.id == id }
        }
    }

    /// 保存画布查看位置；该状态不改变模板内容，内置工作流也允许记录。
    func updateViewport(_ viewport: WorkflowViewport, in workflowID: UUID) {
        guard let index = workflows.firstIndex(where: { $0.id == workflowID }) else { return }
        workflows[index].viewport = viewport
        scheduleSave()
    }

    // MARK: - Run history

    /// 从磁盘加载某工作流的完整运行历史。
    func loadRuns(workflowID: UUID) {
        let root = runsRootURL.appendingPathComponent(workflowID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            runsByWorkflowID[workflowID] = []
            return
        }
        do {
            let directories = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let runs = directories.compactMap { directory -> WorkflowRun? in
                let url = directory.appendingPathComponent("run.json")
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(WorkflowRun.self, from: data)
            }
            runsByWorkflowID[workflowID] = runs.sorted { $0.startedAt > $1.startedAt }
        } catch {
            lastError = error.localizedDescription
            runsByWorkflowID[workflowID] = []
        }
    }

    /// 保存当前运行快照并刷新历史列表。
    func saveRun(_ run: WorkflowRun) {
        activeRun = run
        let root = runRoot(workflowID: run.workflowID, runID: run.id)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: assetsDirectory(workflowID: run.workflowID, runID: run.id),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(run)
            try data.write(to: root.appendingPathComponent("run.json"), options: .atomic)
            var runs = runsByWorkflowID[run.workflowID] ?? []
            if let index = runs.firstIndex(where: { $0.id == run.id }) {
                runs[index] = run
            } else {
                runs.insert(run, at: 0)
            }
            runsByWorkflowID[run.workflowID] = runs.sorted { $0.startedAt > $1.startedAt }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 删除一次运行及其媒体。
    func deleteRun(workflowID: UUID, runID: UUID) {
        let root = runRoot(workflowID: workflowID, runID: runID)
        do {
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
            runsByWorkflowID[workflowID]?.removeAll { $0.id == runID }
            if activeRun?.id == runID { activeRun = nil }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 删除一个工作流的全部运行历史。
    func deleteAllRuns(workflowID: UUID) {
        let root = runsRootURL.appendingPathComponent(workflowID.uuidString, isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
            runsByWorkflowID[workflowID] = []
            if activeRun?.workflowID == workflowID { activeRun = nil }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 把相对媒体路径解析为本地文件 URL。
    func artifactURL(for value: WorkflowValue, run: WorkflowRun) -> URL? {
        switch value {
        case .text, .knowledgeCollection:
            return nil
        case .image(let relative), .video(let relative), .audio(let relative), .folder(let relative):
            let url = runRoot(workflowID: run.workflowID, runID: run.id)
                .appendingPathComponent(relative)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    /// 解析项目镜头保存的运行内相对媒体路径。
    func artifactURL(relativePath: String, workflowID: UUID, runID: UUID) -> URL? {
        let clean = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.hasPrefix("/"), !clean.contains("..") else { return nil }
        let url = runRoot(workflowID: workflowID, runID: runID).appendingPathComponent(clean)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 把用户选择的参考图片复制到指定运行的 `Assets/`，返回运行内相对路径。
    func importProjectReferenceImages(
        _ sourceURLs: [URL],
        workflowID: UUID,
        runID: UUID
    ) throws -> [String] {
        let assets = assetsDirectory(workflowID: workflowID, runID: runID)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        var relativePaths: [String] = []
        for source in sourceURLs.prefix(9) {
            let accessing = source.startAccessingSecurityScopedResource()
            defer { if accessing { source.stopAccessingSecurityScopedResource() } }
            let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
            let target = assets.appendingPathComponent(
                "project-reference-\(UUID().uuidString).\(ext)",
                isDirectory: false
            )
            try FileManager.default.copyItem(at: source, to: target)
            relativePaths.append("Assets/\(target.lastPathComponent)")
        }
        return relativePaths
    }

    // MARK: - Persistence

    /// 立即保存工作流定义。
    func saveNow() {
        debouncer.cancel()
        do {
            let file = WorkflowDefinitionsFile(workflows: workflows)
            let data = try encoder.encode(file)
            try data.write(to: definitionsURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func scheduleSave() {
        debouncer.schedule { [weak self] in self?.saveNow() }
    }

    private func loadDefinitions() {
        let url = definitionsURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            workflows = [WorkflowDefinition.knowledgeImport(), WorkflowDefinition.starter()]
            saveNow()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try decoder.decode(WorkflowDefinitionsFile.self, from: data)
            workflows = file.workflows
            var needsSave = false
            if !workflows.contains(where: { $0.id == WorkflowDefinition.knowledgeImportWorkflowID }) {
                workflows.insert(WorkflowDefinition.knowledgeImport(), at: 0)
                needsSave = true
            }
            if normalizeBuiltInFlags() {
                needsSave = true
            }
            if upgradeKnowledgeImportInputsIfNeeded() {
                needsSave = true
            }
            if needsSave { saveNow() }
        } catch {
            lastError = error.localizedDescription
            workflows = [WorkflowDefinition.knowledgeImport(), WorkflowDefinition.starter()]
        }
    }

    /// 为旧版知识入库节点补上显式提示词、知识集合输入节点与连线，并保留原节点配置。
    private func upgradeKnowledgeImportInputsIfNeeded() -> Bool {
        var changed = false
        for workflowIndex in workflows.indices {
            let importNodeIDs = workflows[workflowIndex].nodes
                .filter { $0.kind == .knowledgeImport }
                .map(\.id)
            var changedWorkflow = false
            for nodeID in importNodeIDs {
                guard let nodeIndex = workflows[workflowIndex].nodes.firstIndex(where: { $0.id == nodeID }) else {
                    continue
                }

                let importNode = workflows[workflowIndex].nodes[nodeIndex]
                let hasPromptInput = workflows[workflowIndex].connections.contains {
                    $0.targetNodeID == nodeID && $0.targetPortID == "prompt"
                }
                if !hasPromptInput {
                    var configuration = WorkflowNodeConfiguration()
                    configuration.parameterName = "知识整理提示词"
                    configuration.runtimeInputType = .prompt
                    configuration.promptCategory = .knowledgeImport
                    configuration.promptItemID = importNode.configuration.promptItemID
                    configuration.promptSnapshot = importNode.configuration.promptSnapshot.isEmpty
                        ? DefaultPrompts.knowledgeImportPromptTemplate
                        : importNode.configuration.promptSnapshot
                    let promptNode = WorkflowNode(
                        kind: .runtimeInput,
                        position: WorkflowPoint(
                            x: importNode.position.x - 350,
                            y: importNode.position.y + 260
                        ),
                        configuration: configuration
                    )
                    workflows[workflowIndex].nodes.append(promptNode)
                    workflows[workflowIndex].connections.append(
                        WorkflowConnection(
                            sourceNodeID: promptNode.id,
                            sourcePortID: "prompt",
                            targetNodeID: nodeID,
                            targetPortID: "prompt"
                        )
                    )
                    workflows[workflowIndex].nodes[nodeIndex].configuration.usesPromptLibrary = false
                    workflows[workflowIndex].nodes[nodeIndex].configuration.promptItemID = nil
                    workflows[workflowIndex].nodes[nodeIndex].configuration.promptSnapshot = ""
                    changed = true
                    changedWorkflow = true
                }

                let hasCollectionInput = workflows[workflowIndex].connections.contains {
                    $0.targetNodeID == nodeID && $0.targetPortID == "collection"
                }
                if !hasCollectionInput {
                    var configuration = WorkflowNodeConfiguration()
                    configuration.parameterName = "知识集合"
                    configuration.runtimeInputType = .knowledgeCollection
                    configuration.collectionID = importNode.configuration.collectionID
                    configuration.isRequired = false
                    let collectionNode = WorkflowNode(
                        kind: .runtimeInput,
                        position: WorkflowPoint(
                            x: importNode.position.x - 350,
                            y: importNode.position.y + 480
                        ),
                        configuration: configuration
                    )
                    workflows[workflowIndex].nodes.append(collectionNode)
                    workflows[workflowIndex].connections.append(
                        WorkflowConnection(
                            sourceNodeID: collectionNode.id,
                            sourcePortID: "knowledgeCollection",
                            targetNodeID: nodeID,
                            targetPortID: "collection"
                        )
                    )
                    workflows[workflowIndex].nodes[nodeIndex].configuration.collectionID = nil
                    changed = true
                    changedWorkflow = true
                }
            }
            if changedWorkflow { workflows[workflowIndex].updatedAt = Date() }
        }
        return changed
    }

    /// 只允许应用声明的稳定模板 ID 带有内置标记，并升级旧版安装。
    private func normalizeBuiltInFlags() -> Bool {
        var changed = false
        for index in workflows.indices {
            let shouldBeBuiltIn = workflows[index].id == WorkflowDefinition.knowledgeImportWorkflowID
            if workflows[index].isBuiltIn != shouldBeBuiltIn {
                workflows[index].isBuiltIn = shouldBeBuiltIn
                changed = true
            }
        }
        return changed
    }

    /// 返回可编辑工作流下标；内置模板在数据层拒绝一切内容修改。
    private func editableWorkflowIndex(id: UUID) -> Int? {
        guard let index = workflows.firstIndex(where: { $0.id == id }) else {
            lastError = WorkflowStoreError.missingWorkflow.localizedDescription
            return nil
        }
        guard !workflows[index].isBuiltIn else {
            lastError = WorkflowStoreError.readOnlyBuiltIn.localizedDescription
            return nil
        }
        return index
    }

    private func availableName(base: String) -> String {
        if !workflows.contains(where: { $0.name == base }) { return base }
        var suffix = 2
        while workflows.contains(where: { $0.name == "\(base) \(suffix)" }) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    /// 指定运行的隔离目录。
    func runRoot(workflowID: UUID, runID: UUID) -> URL {
        runsRootURL
            .appendingPathComponent(workflowID.uuidString, isDirectory: true)
            .appendingPathComponent(runID.uuidString, isDirectory: true)
    }

    /// 指定运行的媒体产物目录。
    func assetsDirectory(workflowID: UUID, runID: UUID) -> URL {
        runRoot(workflowID: workflowID, runID: runID)
            .appendingPathComponent("Assets", isDirectory: true)
    }
}

private struct WorkflowDefinitionsFile: Codable {
    static let currentFormatVersion = 3

    var formatVersion: Int
    var workflows: [WorkflowDefinition]

    init(workflows: [WorkflowDefinition]) {
        formatVersion = Self.currentFormatVersion
        self.workflows = workflows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = max(
            Self.currentFormatVersion,
            try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        )
        workflows = try container.decodeIfPresent([WorkflowDefinition].self, forKey: .workflows) ?? []
    }
}
