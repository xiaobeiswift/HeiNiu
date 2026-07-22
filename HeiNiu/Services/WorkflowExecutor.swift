/// 工作流串行执行器：条件分支、显式循环、模型调用与媒体产物。

import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

/// 执行器所需的知识检索与写入接口，便于使用隔离模拟实现验证调度。
@MainActor
protocol WorkflowKnowledgeAccessing {
    func search(
        query: String,
        settings: SettingsStore,
        collectionID: UUID?,
        tags: [String],
        limit: Int
    ) async throws -> [KnowledgeSearchResult]

    /// 按资料 ID 读取严格身份核验与参考图复制所需的完整只读信息。
    func documentEvidence(id: UUID) -> WorkflowKnowledgeDocumentEvidence?

    /// 保存工作流视觉模型生成的一条带原图资料。
    func addGeneratedFile(
        sourceURL: URL,
        title: String,
        content: String,
        collectionID: UUID?,
        tags: [String]
    ) throws -> KnowledgeWriteResult

    /// 为刚写入的资料建立索引并返回最终状态。
    func indexGeneratedDocument(id: UUID, settings: SettingsStore) async -> KnowledgeIndexStatus
}

extension WorkflowKnowledgeAccessing {
    func documentEvidence(id: UUID) -> WorkflowKnowledgeDocumentEvidence? { nil }

    func addGeneratedFile(
        sourceURL: URL,
        title: String,
        content: String,
        collectionID: UUID?,
        tags: [String]
    ) throws -> KnowledgeWriteResult {
        throw LLMError.underlying("当前知识库实现不支持工作流写入")
    }

    func indexGeneratedDocument(id: UUID, settings: SettingsStore) async -> KnowledgeIndexStatus {
        .pending
    }
}

extension KnowledgeStore: WorkflowKnowledgeAccessing {
    func documentEvidence(id: UUID) -> WorkflowKnowledgeDocumentEvidence? {
        guard let document = document(id: id) else { return nil }
        return WorkflowKnowledgeDocumentEvidence(
            documentID: document.id,
            title: document.title,
            tags: document.tags,
            content: document.content,
            originalFileURL: originalFileURL(for: document)
        )
    }

    func indexGeneratedDocument(id: UUID, settings: SettingsStore) async -> KnowledgeIndexStatus {
        await indexDocument(id: id, settings: settings)
        return document(id: id)?.indexStatus ?? .failed
    }
}

/// 工作流执行期错误。
enum WorkflowExecutionError: LocalizedError {
    case validationFailed
    case missingInput(String)
    case missingLoopFeedback
    case invalidValue(String)
    case unavailableAdapter(String)

    var errorDescription: String? {
        switch self {
        case .validationFailed: "工作流校验失败"
        case .missingInput(let name): "缺少运行输入：\(name)"
        case .missingLoopFeedback: "循环体没有产生反馈值"
        case .invalidValue(let message): message
        case .unavailableAdapter(let id): "媒体适配器“\(id)”未注册"
        }
    }
}

/// 知识缺口不是执行失败，而是可持久化并可恢复的暂停信号。
private struct WorkflowKnowledgeSuspension: LocalizedError {
    var gaps: [WorkflowKnowledgeGap]

    var errorDescription: String? {
        "还缺少 \(gaps.count) 项创作资料"
    }
}

/// 产品缺口联网补证的结果；失败会保留为待补资料，不会伪装成本地命中。
private enum WorkflowWebResearchOutcome {
    case unavailable(String)
    case matched(KnowledgeSearchResult, WorkflowKnowledgeDocumentEvidence)
    case insufficient(String)
}

/// 模型对网页资料做出的结构化产品结论；URL 只从 API 工具结果读取，不信任正文自报链接。
private struct WorkflowWebProductClaim {
    var status: String
    var canonicalName: String
    var identityLevel: WorkflowKnowledgeIdentityLevel
    var confirmedFacts: [String]
    var unknowns: [String]
}

/// 工作流运行控制器。
@Observable
@MainActor
final class WorkflowExecutor {
    /// 是否正在执行。
    var isRunning = false
    /// 最近一次运行前校验信息。
    var validationIssues: [WorkflowValidationIssue] = []
    /// 顶部工具栏可展示的简短状态。
    var statusMessage: String?

    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private let registry: MediaAdapterRegistry
    @ObservationIgnored private let executionHook: (@MainActor (WorkflowNode) async throws -> Void)?

    init(
        registry: MediaAdapterRegistry = .shared,
        executionHook: (@MainActor (WorkflowNode) async throws -> Void)? = nil
    ) {
        self.registry = registry
        self.executionHook = executionHook
    }

    /// 开始整图或目标节点运行并返回本次运行 ID；校验失败时返回 `nil`。
    @discardableResult
    func start(
        workflow: WorkflowDefinition,
        targetNodeID: UUID?,
        runtimeInputs: [String: WorkflowValue],
        settings: SettingsStore,
        knowledge: any WorkflowKnowledgeAccessing,
        store: WorkflowStore,
        parentRunID: UUID? = nil,
        knowledgeGapCategory: WorkflowKnowledgeCategory? = nil
    ) -> UUID? {
        guard !isRunning else { return nil }
        let validationWorkflow = WorkflowGraphAnalysis.scopedWorkflow(targetNodeID: targetNodeID, in: workflow)
        var issues = WorkflowValidator.validate(validationWorkflow, settings: settings, registry: registry)
        let relevant = relevantNodeIDs(targetNodeID: targetNodeID, workflow: workflow)
        for node in workflow.nodes where relevant.contains(node.id) && node.kind == .runtimeInput {
            let value = runtimeInputs[node.id.uuidString]
                ?? runtimeDefaultValue(for: node, settings: settings)
            if node.configuration.isRequired && (value?.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                issues.append(WorkflowValidationIssue(
                    severity: .error,
                    message: "运行输入“\(node.configuration.parameterName)”不能为空",
                    nodeIDs: [node.id]
                ))
            }
        }
        validationIssues = issues
        guard !issues.contains(where: { $0.severity == .error }) else {
            statusMessage = "请先修复 \(issues.filter { $0.severity == .error }.count) 个问题"
            return nil
        }

        let runID = UUID()
        isRunning = true
        statusMessage = targetNodeID == nil ? "正在运行工作流" : "正在运行选中节点"
        runTask = Task { [weak self] in
            guard let self else { return }
            await self.performRun(
                runID: runID,
                workflow: workflow,
                targetNodeID: targetNodeID,
                runtimeInputs: runtimeInputs,
                settings: settings,
                knowledge: knowledge,
                store: store,
                parentRunID: parentRunID,
                knowledgeGapCategory: knowledgeGapCategory,
                existingRun: nil
            )
        }
        return runID
    }

    /// 从知识准备节点恢复等待中的父运行，复用所有已完成节点输出。
    @discardableResult
    func resume(
        workflow: WorkflowDefinition,
        run: WorkflowRun,
        settings: SettingsStore,
        knowledge: any WorkflowKnowledgeAccessing,
        store: WorkflowStore
    ) -> Bool {
        guard !isRunning, run.status == .waitingForKnowledge, run.workflowID == workflow.id else { return false }
        isRunning = true
        statusMessage = "正在重新核验知识资料"
        runTask = Task { [weak self] in
            guard let self else { return }
            await self.performRun(
                runID: run.id,
                workflow: workflow,
                targetNodeID: run.targetNodeID,
                runtimeInputs: run.runtimeInputs,
                settings: settings,
                knowledge: knowledge,
                store: store,
                parentRunID: run.parentRunID,
                knowledgeGapCategory: run.knowledgeGapCategory,
                existingRun: run
            )
        }
        return true
    }

    /// 停止本地执行与媒体轮询。
    func cancel() {
        runTask?.cancel()
        statusMessage = "正在停止"
    }

    /// 返回运行输入节点配置的默认值；提示词输入会跟随提示词库中的当前正文。
    private func runtimeDefaultValue(
        for node: WorkflowNode,
        settings: SettingsStore
    ) -> WorkflowValue? {
        switch node.configuration.runtimeInputType {
        case .text:
            return .text(node.configuration.text)
        case .prompt:
            return .text(WorkflowValidator.resolvedRuntimePrompt(for: node, settings: settings).template)
        case .knowledgeCollection:
            return .knowledgeCollection(node.configuration.collectionID?.uuidString ?? "")
        case .image, .video, .audio, .folder:
            return nil
        }
    }

    private func performRun(
        runID: UUID,
        workflow: WorkflowDefinition,
        targetNodeID: UUID?,
        runtimeInputs: [String: WorkflowValue],
        settings: SettingsStore,
        knowledge: any WorkflowKnowledgeAccessing,
        store: WorkflowStore,
        parentRunID: UUID?,
        knowledgeGapCategory: WorkflowKnowledgeCategory?,
        existingRun: WorkflowRun?
    ) async {
        let relevant = relevantNodeIDs(targetNodeID: targetNodeID, workflow: workflow)
        var run = existingRun ?? WorkflowRun(
            id: runID,
            workflowID: workflow.id,
            targetNodeID: targetNodeID,
            runtimeInputs: runtimeInputs,
            nodes: workflow.nodes,
            parentRunID: parentRunID,
            knowledgeGapCategory: knowledgeGapCategory
        )
        if existingRun == nil {
            for index in run.nodeRuns.indices where !relevant.contains(run.nodeRuns[index].nodeID) {
                run.nodeRuns[index].status = .skipped
                run.nodeRuns[index].message = "不在本次运行范围内"
            }
        } else {
            run.status = .running
            run.pendingKnowledgeGaps = []
            run.endedAt = nil
            for index in run.nodeRuns.indices where run.nodeRuns[index].status == .waiting {
                run.nodeRuns[index].status = .pending
                run.nodeRuns[index].message = "补库完成，重新核验"
                run.nodeRuns[index].endedAt = nil
            }
        }
        do {
            try Task.checkCancellation()
            let preparedRuntimeInputs = existingRun == nil
                ? try prepareRuntimeInputs(runtimeInputs, workflowID: workflow.id, runID: run.id, store: store)
                : run.runtimeInputs
            run.runtimeInputs = preparedRuntimeInputs
            store.saveRun(run)
            let loopComponents = WorkflowGraphAnalysis.loopComponents(in: workflow)
            let bodyNodeIDs = Set(loopComponents.flatMap { $0.nodeIDs.subtracting([$0.loopNodeID]) })
            var inputs: [UUID: [String: [WorkflowValue]]] = [:]
            var executed: Set<UUID> = []
            if existingRun != nil {
                for nodeRun in run.nodeRuns where [.succeeded, .warning].contains(nodeRun.status) {
                    executed.insert(nodeRun.nodeID)
                    propagate(
                        outputs: nodeRun.outputs,
                        from: nodeRun.nodeID,
                        connections: workflow.connections,
                        allowedTargets: relevant,
                        into: &inputs
                    )
                }
            }
            var madeProgress = true

            while madeProgress {
                try Task.checkCancellation()
                madeProgress = false
                let candidates = workflow.nodes
                    .filter { relevant.contains($0.id) && !executed.contains($0.id) && !bodyNodeIDs.contains($0.id) }
                    .sorted(by: stableNodeOrder)
                for node in candidates {
                    if let component = loopComponents.first(where: { $0.loopNodeID == node.id }) {
                        guard inputs[node.id]?["seed"]?.isEmpty == false else { continue }
                        let outputs = try await executeLoop(
                            component: component,
                            workflow: workflow,
                            initialInputs: inputs[node.id] ?? [:],
                            runtimeInputs: preparedRuntimeInputs,
                            runID: run.id,
                            settings: settings,
                            knowledge: knowledge,
                            store: store
                        )
                        executed.formUnion(component.nodeIDs)
                        propagate(
                            outputs: outputs,
                            from: node.id,
                            connections: workflow.connections,
                            allowedTargets: relevant,
                            into: &inputs
                        )
                        madeProgress = true
                    } else if isReady(node, inputs: inputs[node.id] ?? [:], settings: settings) {
                        let outputs = try await executeAndRecord(
                            node: node,
                            inputs: inputs[node.id] ?? [:],
                            runtimeInputs: preparedRuntimeInputs,
                            workflow: workflow,
                            runID: run.id,
                            settings: settings,
                            knowledge: knowledge,
                            store: store,
                            iteration: nil
                        )
                        executed.insert(node.id)
                        propagate(
                            outputs: outputs,
                            from: node.id,
                            connections: workflow.connections,
                            allowedTargets: relevant,
                            into: &inputs
                        )
                        madeProgress = true
                    }
                }
            }

            for node in workflow.nodes where relevant.contains(node.id) && !executed.contains(node.id) {
                updateNodeRun(
                    nodeID: node.id,
                    runID: run.id,
                    store: store,
                    status: .skipped,
                    message: "上游条件分支未命中",
                    persist: false
                )
            }
            finishRun(runID: run.id, store: store, status: currentRunHasWarnings(runID: run.id, store: store) ? .warning : .succeeded)
            statusMessage = currentRunHasWarnings(runID: run.id, store: store) ? "运行完成（有警告）" : "运行完成"
        } catch let suspension as WorkflowKnowledgeSuspension {
            suspendRun(runID: run.id, gaps: suspension.gaps, store: store)
            statusMessage = suspension.localizedDescription
        } catch is CancellationError {
            cancelRun(runID: run.id, store: store)
            statusMessage = "运行已取消"
        } catch {
            failRun(runID: run.id, store: store, message: error.localizedDescription)
            statusMessage = error.localizedDescription
        }
        isRunning = false
        runTask = nil
    }

    // MARK: - Loop execution

    private func executeLoop(
        component: WorkflowLoopComponent,
        workflow: WorkflowDefinition,
        initialInputs: [String: [WorkflowValue]],
        runtimeInputs: [String: WorkflowValue],
        runID: UUID,
        settings: SettingsStore,
        knowledge: any WorkflowKnowledgeAccessing,
        store: WorkflowStore
    ) async throws -> [String: WorkflowValue] {
        guard let loop = workflow.nodes.first(where: { $0.id == component.loopNodeID }),
              case .text(let seed) = initialInputs["seed"]?.first
        else { throw WorkflowExecutionError.invalidValue("循环初始值必须是文本") }
        let bodyIDs = component.nodeIDs.subtracting([loop.id])
        let internalConnections = workflow.connections.filter {
            component.nodeIDs.contains($0.sourceNodeID) && component.nodeIDs.contains($0.targetNodeID)
        }
        guard let feedbackConnection = internalConnections.first(where: {
            $0.targetNodeID == loop.id && $0.targetPortID == "feedback"
        }) else { throw WorkflowExecutionError.missingLoopFeedback }

        updateNodeRun(nodeID: loop.id, runID: runID, store: store, status: .running, message: "准备循环", persist: true)
        var current = seed
        let maximum = max(1, min(20, loop.configuration.maxIterations))
        for iteration in 1...maximum {
            try Task.checkCancellation()
            updateNodeRun(
                nodeID: loop.id,
                runID: runID,
                store: store,
                status: .running,
                message: "第 \(iteration) / \(maximum) 轮",
                iteration: iteration,
                persist: true
            )
            var bodyInputs: [UUID: [String: [WorkflowValue]]] = [:]
            var bodyOutputs: [UUID: [String: WorkflowValue]] = [:]
            var executed: Set<UUID> = []
            propagate(
                outputs: ["iteration": .text(current)],
                from: loop.id,
                connections: internalConnections,
                allowedTargets: bodyIDs,
                into: &bodyInputs
            )
            var madeProgress = true
            while madeProgress {
                try Task.checkCancellation()
                madeProgress = false
                let candidates = workflow.nodes
                    .filter { bodyIDs.contains($0.id) && !executed.contains($0.id) }
                    .sorted(by: stableNodeOrder)
                for node in candidates where isReady(node, inputs: bodyInputs[node.id] ?? [:], settings: settings) {
                    let outputs = try await executeAndRecord(
                        node: node,
                        inputs: bodyInputs[node.id] ?? [:],
                        runtimeInputs: runtimeInputs,
                        workflow: workflow,
                        runID: runID,
                        settings: settings,
                        knowledge: knowledge,
                        store: store,
                        iteration: iteration
                    )
                    bodyOutputs[node.id] = outputs
                    executed.insert(node.id)
                    propagate(
                        outputs: outputs,
                        from: node.id,
                        connections: internalConnections.filter { $0.targetNodeID != loop.id },
                        allowedTargets: bodyIDs,
                        into: &bodyInputs
                    )
                    madeProgress = true
                }
            }
            guard case .text(let feedback) = bodyOutputs[feedbackConnection.sourceNodeID]?[feedbackConnection.sourcePortID] else {
                throw WorkflowExecutionError.missingLoopFeedback
            }
            let shouldStop = try loop.configuration.comparison.evaluate(
                feedback,
                operand: loop.configuration.comparisonValue
            )
            if shouldStop {
                updateNodeRun(
                    nodeID: loop.id,
                    runID: runID,
                    store: store,
                    status: .succeeded,
                    outputs: ["completed": .text(feedback)],
                    message: "第 \(iteration) 轮满足停止条件",
                    iteration: iteration,
                    persist: true
                )
                return ["completed": .text(feedback)]
            }
            current = feedback
            if iteration == maximum {
                appendWarning("循环达到 \(maximum) 次上限，已输出最后结果", runID: runID, store: store)
                updateNodeRun(
                    nodeID: loop.id,
                    runID: runID,
                    store: store,
                    status: .warning,
                    outputs: ["completed": .text(feedback)],
                    message: "达到次数上限",
                    iteration: iteration,
                    persist: true
                )
                return ["completed": .text(feedback)]
            }
        }
        throw WorkflowExecutionError.missingLoopFeedback
    }

    // MARK: - Individual nodes

    private func executeAndRecord(
        node: WorkflowNode,
        inputs: [String: [WorkflowValue]],
        runtimeInputs: [String: WorkflowValue],
        workflow: WorkflowDefinition,
        runID: UUID,
        settings: SettingsStore,
        knowledge: any WorkflowKnowledgeAccessing,
        store: WorkflowStore,
        iteration: Int?
    ) async throws -> [String: WorkflowValue] {
        updateNodeRun(
            nodeID: node.id,
            runID: runID,
            store: store,
            status: .running,
            message: iteration.map { "第 \($0) 轮" },
            iteration: iteration,
            persist: true
        )
        do {
            let outputs = try await executeNode(
                node,
                inputs: inputs,
                runtimeInputs: runtimeInputs,
                workflow: workflow,
                runID: runID,
                settings: settings,
                knowledge: knowledge,
                store: store
            )
            updateNodeRun(
                nodeID: node.id,
                runID: runID,
                store: store,
                status: .succeeded,
                outputs: outputs,
                message: "完成",
                iteration: iteration,
                persist: true
            )
            return outputs
        } catch {
            updateNodeRun(
                nodeID: node.id,
                runID: runID,
                store: store,
                status: error is WorkflowKnowledgeSuspension
                    ? .waiting
                    : (error is CancellationError ? .cancelled : .failed),
                message: error.localizedDescription,
                iteration: iteration,
                persist: true
            )
            throw error
        }
    }

    private func executeNode(
        _ node: WorkflowNode,
        inputs: [String: [WorkflowValue]],
        runtimeInputs: [String: WorkflowValue],
        workflow: WorkflowDefinition,
        runID: UUID,
        settings: SettingsStore,
        knowledge: any WorkflowKnowledgeAccessing,
        store: WorkflowStore
    ) async throws -> [String: WorkflowValue] {
        try Task.checkCancellation()
        try await executionHook?(node)
        try Task.checkCancellation()
        switch node.kind {
        case .runtimeInput:
            let expectedType = node.configuration.runtimeInputType.valueType
            let value = runtimeInputs[node.id.uuidString]
                ?? runtimeDefaultValue(for: node, settings: settings)
            guard let value else {
                throw WorkflowExecutionError.missingInput(node.configuration.parameterName)
            }
            if node.configuration.isRequired && value.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw WorkflowExecutionError.missingInput(node.configuration.parameterName)
            }
            guard value.valueType == expectedType else {
                throw WorkflowExecutionError.invalidValue("运行输入“\(node.configuration.parameterName)”应为\(expectedType.title)")
            }
            return [node.configuration.runtimeInputType.rawValue: value]

        case .promptTemplate:
            let resolved = WorkflowValidator.resolvedTemplate(for: node, settings: settings)
            if resolved.usedSnapshot {
                appendWarning("“\(node.displayTitle)”使用了已删除提示词的快照", runID: runID, store: store)
            }
            var output = resolved.template
            let effective = WorkflowValidator.effectiveNode(node, settings: settings)
            for variable in effective.configuration.templateVariables {
                guard case .text(let value) = inputs[variable]?.first else {
                    throw WorkflowExecutionError.missingInput("{{\(variable)}}")
                }
                let pattern = #"\{\{\s*"# + NSRegularExpression.escapedPattern(for: variable) + #"\s*\}\}"#
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(
                    in: output,
                    range: range,
                    withTemplate: NSRegularExpression.escapedTemplate(for: value)
                )
            }
            return ["text": .text(output)]

        case .knowledgeSearch:
            guard case .text(let query) = inputs["query"]?.first else {
                throw WorkflowExecutionError.invalidValue("知识检索输入必须是文本")
            }
            let results = try await knowledge.search(
                query: Self.compactKnowledgeQuery(query),
                settings: settings,
                collectionID: node.configuration.collectionID,
                tags: node.configuration.tags,
                limit: node.configuration.topK
            )
            let text = results.map {
                "[\($0.documentTitle)#片段\($0.ordinal + 1) · \(String(format: "%.3f", $0.score))]\n\($0.text)"
            }.joined(separator: "\n\n")
            return ["context": .text(text)]

        case .knowledgePreparation:
            guard case .text(let requirementsJSON) = inputs["requirements"]?.first else {
                throw WorkflowExecutionError.invalidValue("创作知识准备输入必须是要素 JSON")
            }
            return try await prepareCreationKnowledge(
                requirementsJSON: requirementsJSON,
                node: node,
                workflow: workflow,
                runID: runID,
                settings: settings,
                knowledge: knowledge,
                store: store
            )

        case .knowledgeImport:
            guard case .folder(let relativeFolder) = inputs["folder"]?.first,
                  case .text(let knowledgePromptTemplate) = inputs["prompt"]?.first,
                  case .text(let instructions) = inputs["instructions"]?.first,
                  case .knowledgeCollection(let collectionReference) = inputs["collection"]?.first,
                  let provider = settings.effectiveLLMProvider(for: node.configuration.providerID)
            else { throw WorkflowExecutionError.invalidValue("添加知识库节点需要图片文件夹、知识整理提示词、整理要求、知识集合和有效 LLM 服务商") }
            let targetCollectionID = UUID(uuidString: collectionReference)
            guard provider.supportsVision else {
                throw WorkflowExecutionError.invalidValue("“\(provider.name)”未开启视觉能力，不能理解图片")
            }
            let model = settings.effectiveLLMModel(
                providerID: node.configuration.providerID,
                model: node.configuration.model
            )
            guard !model.isEmpty else { throw LLMError.missingModel }
            let apiKey = settings.apiKey(for: provider.id)
            guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

            let runRoot = store.runRoot(workflowID: workflow.id, runID: runID)
            let folderURL = runRoot.appendingPathComponent(relativeFolder, isDirectory: true).standardizedFileURL
            guard folderURL.path.hasPrefix(runRoot.standardizedFileURL.path + "/") else {
                throw WorkflowExecutionError.invalidValue("图片文件夹路径超出本次运行目录")
            }
            let allImages = try imageFiles(in: folderURL)
            guard !allImages.isEmpty else {
                throw WorkflowExecutionError.invalidValue("所选文件夹内没有可处理的图片")
            }
            let limit = max(1, min(500, node.configuration.maxFiles))
            let images = Array(allImages.prefix(limit))
            if allImages.count > limit {
                appendWarning(
                    "图片文件夹共有 \(allImages.count) 张支持的图片，本次按上限只处理前 \(limit) 张",
                    runID: runID,
                    store: store
                )
            }

            let cleanInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanInstructions.isEmpty else { throw WorkflowExecutionError.missingInput("整理要求") }
            let cleanKnowledgePrompt = knowledgePromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanKnowledgePrompt.isEmpty else { throw WorkflowExecutionError.missingInput("知识整理提示词") }
            let client = LLMClientFactory.make(for: provider)
            let shouldIndex = canAutomaticallyIndex(settings: settings)
            var created = 0
            var duplicates = 0
            var indexed = 0
            var indexFailures = 0
            var failures: [String] = []

            for (offset, imageURL) in images.enumerated() {
                try Task.checkCancellation()
                let progress = Double(offset) / Double(images.count)
                updateNodeRun(
                    nodeID: node.id,
                    runID: runID,
                    store: store,
                    status: .running,
                    message: "正在理解第 \(offset + 1)/\(images.count) 张：\(imageURL.lastPathComponent)",
                    progress: progress,
                    persist: true
                )
                do {
                    let attachment = try visionAttachment(from: imageURL)
                    let completion = try await client.complete(
                        messages: knowledgeImportMessages(
                            image: attachment,
                            filename: imageURL.lastPathComponent,
                            instructions: cleanInstructions,
                            knowledgePromptTemplate: cleanKnowledgePrompt,
                            additionalSystemPrompt: node.configuration.systemPrompt
                        ),
                        model: model,
                        temperature: node.configuration.temperature,
                        reasoningEffort: node.configuration.reasoningEffort,
                        apiKey: apiKey
                    )
                    let generated = parseGeneratedKnowledge(
                        completion.content,
                        fallbackTitle: imageURL.deletingPathExtension().lastPathComponent
                    )
                    let write = try knowledge.addGeneratedFile(
                        sourceURL: imageURL,
                        title: generated.title,
                        content: generated.content,
                        collectionID: targetCollectionID,
                        tags: node.configuration.tags + generated.tags
                    )
                    if write.wasCreated {
                        created += 1
                        if shouldIndex {
                            let status = await knowledge.indexGeneratedDocument(id: write.documentID, settings: settings)
                            if status == .ready { indexed += 1 } else { indexFailures += 1 }
                        }
                    } else {
                        duplicates += 1
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures.append("\(imageURL.lastPathComponent)：\(error.localizedDescription)")
                }
            }

            guard created + duplicates > 0 else {
                throw WorkflowExecutionError.invalidValue(
                    "图片均未能写入知识库：\(failures.prefix(3).joined(separator: "；"))"
                )
            }
            if !failures.isEmpty {
                appendWarning("有 \(failures.count) 张图片处理失败", runID: runID, store: store)
            }
            if indexFailures > 0 {
                appendWarning("有 \(indexFailures) 条新资料未能完成向量索引，可在知识库中重试", runID: runID, store: store)
            }
            let indexLine = shouldIndex
                ? "自动索引：成功 \(indexed) 条，失败 \(indexFailures) 条"
                : "自动索引：未配置可用的嵌入服务，资料保持等待索引"
            var summary = [
                "图片知识入库完成",
                "扫描 \(allImages.count) 张，本次处理 \(images.count) 张",
                "新增 \(created) 条，跳过重复 \(duplicates) 条，失败 \(failures.count) 条",
                indexLine,
            ]
            if !failures.isEmpty {
                summary.append("失败明细：\n" + failures.map { "- \($0)" }.joined(separator: "\n"))
            }
            return ["summary": .text(summary.joined(separator: "\n"))]

        case .llm:
            guard case .text(let prompt) = inputs["prompt"]?.first,
                  let provider = settings.effectiveLLMProvider(for: node.configuration.providerID)
            else { throw LLMError.missingProvider }
            let model = settings.effectiveLLMModel(
                providerID: node.configuration.providerID,
                model: node.configuration.model
            )
            guard !model.isEmpty else { throw LLMError.missingModel }
            let apiKey = settings.apiKey(for: provider.id)
            guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }
            var messages: [LLMChatMessage] = []
            let systemPrompt = node.configuration.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !systemPrompt.isEmpty { messages.append(LLMChatMessage(role: .system, content: systemPrompt)) }
            messages.append(LLMChatMessage(role: .user, content: prompt))
            let client = LLMClientFactory.make(for: provider)
            var content = LLMStreamTextBuffer()
            var reasoning = LLMStreamTextBuffer()
            for try await event in client.stream(
                messages: messages,
                model: model,
                temperature: node.configuration.temperature,
                reasoningEffort: node.configuration.reasoningEffort,
                apiKey: apiKey
            ) {
                try Task.checkCancellation()
                switch event {
                case .contentDelta(let delta): _ = content.absorb(delta)
                case .reasoningDelta(let delta): _ = reasoning.absorb(delta)
                }
                var live: [String: WorkflowValue] = ["text": .text(content.text)]
                if !reasoning.text.isEmpty { live["reasoning"] = .text(reasoning.text) }
                updateLiveOutputs(nodeID: node.id, runID: runID, store: store, outputs: live)
            }
            guard !content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMError.emptyResponse
            }
            var outputs: [String: WorkflowValue] = ["text": .text(content.text)]
            if !reasoning.text.isEmpty { outputs["reasoning"] = .text(reasoning.text) }
            return outputs

        case .imageGeneration:
            guard case .text(let prompt) = inputs["prompt"]?.first,
                  let provider = settings.imageProvider(id: node.configuration.providerID)
            else { throw WorkflowExecutionError.invalidValue("生图节点需要文本提示词和有效服务商") }
            guard let adapter = registry.imageAdapter(id: provider.adapterID) else {
                throw WorkflowExecutionError.unavailableAdapter(provider.adapterID)
            }
            let key = settings.imageAPIKey(for: provider.id)
            guard !key.isEmpty else { throw LLMError.missingAPIKey }
            var referenceURL: URL?
            if case .image(let relative) = inputs["referenceImage"]?.first {
                referenceURL = store.runRoot(workflowID: workflow.id, runID: runID)
                    .appendingPathComponent(relative)
            }
            var maskURL: URL?
            if case .image(let relative) = inputs["maskImage"]?.first {
                maskURL = store.runRoot(workflowID: workflow.id, runID: runID)
                    .appendingPathComponent(relative)
            }
            if node.configuration.imageOperation == .edit && referenceURL == nil {
                throw WorkflowExecutionError.invalidValue("图片编辑节点需要连接原图")
            }
            let assets = store.assetsDirectory(workflowID: workflow.id, runID: runID)
            let artifact = try await adapter.generate(
                request: ImageGenerationRequest(
                    prompt: prompt,
                    model: node.configuration.model,
                    size: node.configuration.mediaSize.isEmpty ? provider.defaultSize : node.configuration.mediaSize,
                    operation: node.configuration.imageOperation,
                    referenceImageURL: referenceURL,
                    maskImageURL: maskURL
                ),
                provider: provider,
                apiKey: key,
                outputDirectory: assets
            ) { [weak self] event in
                await self?.updateProgress(nodeID: node.id, runID: runID, store: store, event: event)
            }
            return ["image": .image("Assets/\(artifact.fileURL.lastPathComponent)")]

        case .videoGeneration:
            guard case .text(let prompt) = inputs["prompt"]?.first,
                  let provider = settings.videoProvider(id: node.configuration.providerID)
            else { throw WorkflowExecutionError.invalidValue("生视频节点需要文本提示词和有效服务商") }
            guard let adapter = registry.videoAdapter(id: provider.adapterID) else {
                throw WorkflowExecutionError.unavailableAdapter(provider.adapterID)
            }
            let key = settings.videoAPIKey(for: provider.id)
            if provider.kind != .pixmax && key.isEmpty { throw LLMError.missingAPIKey }
            let root = store.runRoot(workflowID: workflow.id, runID: runID)
            let imageURLs = mediaURLs(inputs["referenceImage"] ?? [], expected: .image, root: root)
            let videoURLs = mediaURLs(inputs["referenceVideo"] ?? [], expected: .video, root: root)
            let audioURLs = mediaURLs(inputs["referenceAudio"] ?? [], expected: .audio, root: root)
            let assets = store.assetsDirectory(workflowID: workflow.id, runID: runID)
            let artifact = try await adapter.generate(
                request: VideoGenerationRequest(
                    prompt: prompt,
                    model: node.configuration.model,
                    aspectRatio: provider.kind == .pixmax
                        ? (node.configuration.mediaSize.isEmpty ? provider.defaultAspectRatio : node.configuration.mediaSize)
                        : "auto",
                    resolution: provider.kind == .pixmax
                        ? (node.configuration.videoResolution.isEmpty ? "720P" : node.configuration.videoResolution)
                        : (node.configuration.mediaSize.isEmpty ? "720x1280" : node.configuration.mediaSize),
                    durationSeconds: node.configuration.durationSeconds,
                    includeAudio: node.configuration.includeAudio,
                    referenceImageURLs: imageURLs,
                    referenceVideoURLs: videoURLs,
                    referenceAudioURLs: audioURLs
                ),
                provider: provider,
                apiKey: key,
                outputDirectory: assets
            ) { [weak self] event in
                await self?.updateProgress(nodeID: node.id, runID: runID, store: store, event: event)
            }
            for warning in artifact.warnings {
                appendWarning(warning, runID: runID, store: store)
            }
            return ["video": .video("Assets/\(artifact.fileURL.lastPathComponent)")]

        case .condition:
            guard case .text(let value) = inputs["value"]?.first else {
                throw WorkflowExecutionError.invalidValue("条件节点输入必须是文本")
            }
            let matched = try node.configuration.comparison.evaluate(value, operand: node.configuration.comparisonValue)
            return [matched ? "true" : "false": .text(value)]

        case .output:
            guard let value = inputs["value"]?.first else { throw WorkflowExecutionError.missingInput("结果") }
            return ["value": value]

        case .loop:
            throw WorkflowExecutionError.invalidValue("循环节点必须由显式循环调度器执行")
        case .unsupported(let id):
            throw WorkflowExecutionError.invalidValue("不支持的节点类型：\(id)")
        }
    }

    /// 递归列出文件夹中的支持图片，使用相对路径稳定排序。
    private func imageFiles(in folder: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkflowExecutionError.invalidValue("图片文件夹不存在或不可读")
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentTypeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw WorkflowExecutionError.invalidValue("无法读取图片文件夹") }
        let fallbackExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "bmp", "gif"]
        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let isImage = values?.contentType?.conforms(to: .image) == true
                || fallbackExtensions.contains(url.pathExtension.lowercased())
            if isImage { result.append(url) }
        }
        return result.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    /// 将任意可解码图片缩放并转为兼容面更广的 JPEG 视觉附件。
    private func visionAttachment(from url: URL) throws -> LLMImageAttachment {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw WorkflowExecutionError.invalidValue("无法解码图片：\(url.lastPathComponent)")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_560,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw WorkflowExecutionError.invalidValue("无法读取图片画面：\(url.lastPathComponent)")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { throw WorkflowExecutionError.invalidValue("无法创建视觉图片数据") }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw WorkflowExecutionError.invalidValue("无法编码图片：\(url.lastPathComponent)")
        }
        return LLMImageAttachment(data: output as Data, mediaType: "image/jpeg")
    }

    /// 为单张图片构建约束清晰、同时允许用户自定义提炼目标的视觉消息。
    private func knowledgeImportMessages(
        image: LLMImageAttachment,
        filename: String,
        instructions: String,
        knowledgePromptTemplate: String,
        additionalSystemPrompt: String
    ) -> [LLMChatMessage] {
        var system = """
        你是黑妞短剧的知识整理助手。请理解用户提供的图片，并把可复用、可检索的事实整理为知识资料。
        只返回一个 JSON 对象，不要使用 Markdown 代码块。JSON 必须包含：
        {"title":"简洁准确的中文标题","content":"完整知识正文","tags":["标签"]}
        content 必须能够脱离图片单独理解；不要编造图片无法确认的事实。tags 使用简短中文词语。
        """
        let managedPrompt = renderKnowledgeImportPrompt(
            knowledgePromptTemplate,
            filename: filename,
            requirements: instructions
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if !managedPrompt.isEmpty { system += "\n\n知识整理提示词：\n\(managedPrompt)" }
        let extra = additionalSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { system += "\n\n补充系统要求：\n\(extra)" }
        let user = """
        文件名：\(filename)

        用户整理要求：
        \(instructions)
        """
        return [
            LLMChatMessage(role: .system, content: system),
            LLMChatMessage(role: .user, content: user, images: [image]),
        ]
    }

    /// 替换知识整理模板中的逐图文件名和本次运行要求。
    private func renderKnowledgeImportPrompt(
        _ template: String,
        filename: String,
        requirements: String
    ) -> String {
        var output = template
        for (name, value) in [("filename", filename), ("requirements", requirements)] {
            let pattern = #"\{\{\s*"# + NSRegularExpression.escapedPattern(for: name) + #"\s*\}\}"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(
                in: output,
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: value)
            )
        }
        return output
    }

    /// 容错解析视觉模型 JSON；非 JSON 回答仍作为正文入库，避免丢失已生成内容。
    private func parseGeneratedKnowledge(_ response: String, fallbackTitle: String) -> GeneratedKnowledge {
        var clean = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            clean = clean.replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            clean = clean.replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
        }
        guard let first = clean.firstIndex(of: "{"), let last = clean.lastIndex(of: "}"), first <= last else {
            return GeneratedKnowledge(title: fallbackTitle, content: clean, tags: [])
        }
        let json = String(clean[first...last])
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return GeneratedKnowledge(title: fallbackTitle, content: clean, tags: []) }

        let titleKeys = ["title", "标题", "name"]
        let contentKeys = ["content", "正文", "knowledge", "description", "summary"]
        let title = titleKeys.compactMap { object[$0] as? String }.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let content = contentKeys.compactMap { object[$0] as? String }.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var tags: [String] = []
        if let values = object["tags"] as? [String] {
            tags = values
        } else if let value = object["tags"] as? String ?? object["标签"] as? String {
            tags = value.components(separatedBy: CharacterSet(charactersIn: ",，、"))
        } else if let values = object["标签"] as? [String] {
            tags = values
        }
        let normalizedTags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return GeneratedKnowledge(
            title: title?.isEmpty == false ? title! : fallbackTitle,
            content: content?.isEmpty == false ? content! : clean,
            tags: normalizedTags
        )
    }

    /// 只有嵌入配置、模型和钥匙串密钥都齐全时才自动索引，写入本身不受影响。
    private func canAutomaticallyIndex(settings: SettingsStore) -> Bool {
        guard let providerID = settings.knowledgeEmbeddingProviderID,
              !settings.knowledgeEmbeddingModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        return !settings.apiKey(for: providerID).isEmpty
    }

    // MARK: - Creation knowledge preparation

    private func prepareCreationKnowledge(
        requirementsJSON: String,
        node: WorkflowNode,
        workflow: WorkflowDefinition,
        runID: UUID,
        settings: SettingsStore,
        knowledge: any WorkflowKnowledgeAccessing,
        store: WorkflowStore
    ) async throws -> [String: WorkflowValue] {
        guard let envelope = Self.parseKnowledgeRequirements(from: requirementsJSON) else {
            throw WorkflowExecutionError.invalidValue("要素提取结果不是有效 JSON，或没有列出任何创作要素")
        }

        var gaps: [WorkflowKnowledgeGap] = []
        var matched: [(WorkflowKnowledgeRequirement, KnowledgeSearchResult, WorkflowKnowledgeDocumentEvidence)] = []
        let candidateLimit = max(1, min(12, node.configuration.topK))
        for requirement in envelope.requirements {
            try Task.checkCancellation()
            let name = requirement.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                gaps.append(WorkflowKnowledgeGap(requirement: requirement, message: "要素名称为空，无法精确检索"))
                continue
            }
            let query = ([name] + requirement.aliases + requirement.searchTerms)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " ")
            let results: [KnowledgeSearchResult]
            do {
                results = try await knowledge.search(
                    query: query,
                    settings: settings,
                    collectionID: nil,
                    tags: [],
                    limit: candidateLimit
                )
            } catch {
                if error.localizedDescription.contains("没有使用当前嵌入配置完成索引") {
                    results = []
                } else {
                    throw error
                }
            }
            var candidate = results.compactMap { result -> (KnowledgeSearchResult, WorkflowKnowledgeDocumentEvidence)? in
                guard let evidence = knowledge.documentEvidence(id: result.documentID),
                      Self.matches(requirement: requirement, evidence: evidence)
                else { return nil }
                return (result, evidence)
            }.max { lhs, rhs in
                let lhsHasImage = Self.isImageReference(lhs.1.originalFileURL)
                let rhsHasImage = Self.isImageReference(rhs.1.originalFileURL)
                if lhsHasImage != rhsHasImage { return !lhsHasImage && rhsHasImage }
                return lhs.0.score < rhs.0.score
            }
            var gapDetail: String?
            if candidate == nil, requirement.category == .product {
                switch await researchProductKnowledge(
                    requirement: requirement,
                    node: node,
                    runID: runID,
                    settings: settings,
                    store: store
                ) {
                case .matched(let result, let evidence):
                    candidate = (result, evidence)
                case .unavailable(let message), .insufficient(let message):
                    gapDetail = message
                }
            }
            if let candidate {
                var resolvedRequirement = requirement
                if Self.isProvisionalProductRequirement(requirement) {
                    resolvedRequirement.name = candidate.1.title
                    resolvedRequirement.identityLevel = .series
                    resolvedRequirement.aliases = requirement.aliases.filter {
                        !Self.isProvisionalProductName($0)
                    }
                    let boundary = "匹配边界：当前仅确认同一产品系列或用途类别；香型、品牌、SKU、具体型号和车型兼容性必须以资料明确证据为准，未证实字段不得写成确定事实。"
                    if !resolvedRequirement.role.contains(boundary) {
                        resolvedRequirement.role = [resolvedRequirement.role, boundary]
                            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            .joined(separator: "\n")
                    }
                    appendWarning(
                        "“\(requirement.name)”仅按产品系列资料“\(candidate.1.title)”继续；品牌、SKU、香型和适配版本仍按证据边界处理",
                        runID: runID,
                        store: store
                    )
                }
                matched.append((resolvedRequirement, candidate.0, candidate.1))
            } else {
                let baseMessage = Self.isProvisionalProductRequirement(requirement)
                    ? "知识库中没有与产品系列、用途和检索锚点匹配的已索引资料"
                    : "知识库中没有标题、标签或正文准确匹配“\(name)”的已索引资料"
                gaps.append(WorkflowKnowledgeGap(
                    requirement: requirement,
                    message: [baseMessage, gapDetail]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: "；")
                ))
            }
        }
        if !gaps.isEmpty { throw WorkflowKnowledgeSuspension(gaps: gaps) }

        let referenceRoot = store.assetsDirectory(workflowID: workflow.id, runID: runID)
            .appendingPathComponent("KnowledgeReferences", isDirectory: true)
        try FileManager.default.createDirectory(at: referenceRoot, withIntermediateDirectories: true)
        var categoryCounts: [WorkflowKnowledgeCategory: Int] = [:]
        var contextParts: [String] = []
        var entries: [WorkflowReferenceManifestEntry] = []
        for (requirement, result, evidence) in matched {
            contextParts.append("""
            [\(requirement.category.title)｜\(requirement.name)｜资料：\(evidence.title)｜相似度：\(String(format: "%.3f", result.score))]
            身份/用途：\(requirement.role.isEmpty ? "原文明确要素" : requirement.role)
            标签：\(evidence.tags.joined(separator: "、"))
            \(String(evidence.content.prefix(12_000)))
            """)
            guard let sourceURL = evidence.originalFileURL,
                  Self.isImageReference(sourceURL)
            else {
                appendWarning("“\(requirement.name)”已命中文字资料，但没有可挂到分镜卡片的原始图片", runID: runID, store: store)
                continue
            }
            categoryCounts[requirement.category, default: 0] += 1
            let prefix: String
            switch requirement.category {
            case .character: prefix = "CHAR"
            case .product: prefix = "PROD"
            case .vehicleScene: prefix = "SCENE"
            }
            let referenceID = String(format: "%@-%02d", prefix, categoryCounts[requirement.category] ?? 1)
            let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension.lowercased()
            let destination = referenceRoot.appendingPathComponent(
                "\(referenceID)-\(evidence.documentID.uuidString.prefix(8)).\(ext)",
                isDirectory: false
            )
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: sourceURL, to: destination)
            }
            entries.append(WorkflowReferenceManifestEntry(
                referenceID: referenceID,
                requirementID: requirement.id,
                category: requirement.category,
                documentID: evidence.documentID,
                title: evidence.title,
                relativePath: "Assets/KnowledgeReferences/\(destination.lastPathComponent)",
                score: result.score
            ))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(WorkflowReferenceManifest(entries: entries))
        let manifestText = String(decoding: manifestData, as: UTF8.self)
        return [
            "context": .text(contextParts.joined(separator: "\n\n")),
            "referenceManifest": .text(manifestText),
        ]
    }

    /// 本地知识库未命中产品时，使用已明确开启的 Responses Web Search 服务商补证。
    /// 普通聊天回答、无来源回答或无法确认身份级别的回答都会保留为知识缺口。
    private func researchProductKnowledge(
        requirement: WorkflowKnowledgeRequirement,
        node: WorkflowNode,
        runID: UUID,
        settings: SettingsStore,
        store: WorkflowStore
    ) async -> WorkflowWebResearchOutcome {
        let preferredProvider = settings.effectiveLLMProvider(for: node.configuration.providerID)
        var providers: [LLMProvider] = []
        if let preferredProvider { providers.append(preferredProvider) }
        let additionalProviders = settings.providers.filter { provider in
            !providers.contains(where: { $0.id == provider.id })
        }
        providers.append(contentsOf: additionalProviders)
        let capableProviders = providers.filter {
            $0.supportsWebSearch
                && $0.protocolType == .openAICompatible
                && $0.openAIAPIMode == .responses
        }
        guard !capableProviders.isEmpty else {
            return .unavailable("尚未配置可用的 Responses 联网补资料服务商")
        }

        var failures: [String] = []
        for provider in capableProviders {
            let model: String
            if provider.id == preferredProvider?.id {
                model = settings.effectiveLLMModel(
                    providerID: node.configuration.providerID,
                    model: node.configuration.model
                )
            } else if provider.id == settings.defaultLLMProviderID {
                model = settings.defaultLLMModel.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                model = provider.models.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            let apiKey = settings.apiKey(for: provider.id)
            guard !model.isEmpty, !apiKey.isEmpty else {
                failures.append("“\(provider.name)”缺少模型或 API Key")
                continue
            }
            let client = LLMClientFactory.make(for: provider)
            guard let researcher = client as? any LLMWebResearching else {
                failures.append("“\(provider.name)”不支持原生网页检索")
                continue
            }

            updateNodeRun(
                nodeID: node.id,
                runID: runID,
                store: store,
                status: .running,
                message: "本地知识库未命中，正在联网核验“\(requirement.name)”",
                persist: true
            )
            do {
                let result = try await researcher.researchWeb(
                    messages: Self.webResearchMessages(for: requirement),
                    model: model,
                    temperature: 0,
                    reasoningEffort: .low,
                    apiKey: apiKey
                )
                guard let claim = Self.parseWebProductClaim(result.content) else {
                    failures.append("“\(provider.name)”联网回答不是可核验的结构化产品结论")
                    continue
                }
                guard ["verified", "partial"].contains(claim.status.lowercased()),
                      claim.identityLevel != .unknown,
                      !claim.canonicalName.isEmpty,
                      !claim.confirmedFacts.isEmpty
                else {
                    failures.append("网页来源不足以确认“\(requirement.name)”")
                    continue
                }
                if !Self.isProvisionalProductRequirement(requirement) {
                    let exactIdentities = ([requirement.name] + requirement.aliases)
                        .map(Self.normalizedIdentityText)
                        .filter { !$0.isEmpty }
                    guard claim.identityLevel == .exact,
                          exactIdentities.contains(Self.normalizedIdentityText(claim.canonicalName))
                    else {
                        failures.append("网页只确认到相近系列，未确认精确商品“\(requirement.name)”")
                        continue
                    }
                }

                let sourceLines = result.sources.map { source in
                    "- \(source.title)：\(source.url.absoluteString)"
                }.joined(separator: "\n")
                let unknownLine = claim.unknowns.isEmpty
                    ? "无额外未知项"
                    : claim.unknowns.joined(separator: "；")
                let content = """
                联网补证级别：\(claim.identityLevel.rawValue)
                已确认事实：
                \(claim.confirmedFacts.map { "- \($0)" }.joined(separator: "\n"))
                尚未确认：\(unknownLine)
                网页来源：
                \(sourceLines)
                """
                let documentID = UUID()
                let evidence = WorkflowKnowledgeDocumentEvidence(
                    documentID: documentID,
                    title: claim.canonicalName,
                    tags: ["产品", "联网补证", "证据级别-\(claim.identityLevel.rawValue)"],
                    content: content,
                    originalFileURL: nil
                )
                guard Self.matches(requirement: requirement, evidence: evidence) else {
                    failures.append("联网来源与产品系列、用途或检索锚点仍不一致")
                    continue
                }
                appendWarning(
                    "“\(requirement.name)”本地资料未命中，已采用带 \(result.sources.count) 个来源的联网补证",
                    runID: runID,
                    store: store
                )
                let searchResult = KnowledgeSearchResult(
                    chunkID: UUID(),
                    documentID: documentID,
                    documentTitle: claim.canonicalName,
                    ordinal: 0,
                    text: content,
                    score: claim.identityLevel == .exact ? 0.700 : 0.550
                )
                return .matched(searchResult, evidence)
            } catch is CancellationError {
                return .insufficient("联网补证已取消")
            } catch {
                failures.append("“\(provider.name)”联网失败：\(error.localizedDescription)")
            }
        }
        return .insufficient(failures.prefix(2).joined(separator: "；"))
    }

    private static func webResearchMessages(for requirement: WorkflowKnowledgeRequirement) -> [LLMChatMessage] {
        let system = """
        你是产品资料事实核验员。必须使用网页搜索工具核验，不得依赖记忆补全。
        只输出一个 JSON 对象，不要 Markdown：
        {"status":"verified|partial|insufficient","canonicalName":"网页可证实的正式商品名或稳定系列名","identityLevel":"exact|series|unknown","confirmedFacts":["逐条可由网页来源支持的事实"],"unknowns":["仍未证实的品牌、SKU、规格、香型或适配信息"]}
        exact 仅用于品牌、正式商品名或唯一型号已由网页明确确认；只能确认类别、用途或产品系列时必须填 series；无法确认目标产品时填 insufficient 和 unknown。
        不要把用户检索词、价格、卖点、香型对标和“型号未明确”等说明拼成商品名。兼容车型、规格、价格和性能没有网页证据时必须放入 unknowns。
        """
        let user = """
        待核验产品描述：\(requirement.name)
        身份级别：\(requirement.identityLevel.rawValue)
        剧情用途：\(requirement.role)
        别名：\(requirement.aliases.joined(separator: "、"))
        建议检索词：\(requirement.searchTerms.joined(separator: "；"))
        """
        return [
            LLMChatMessage(role: .system, content: system),
            LLMChatMessage(role: .user, content: user),
        ]
    }

    private static func parseWebProductClaim(_ text: String) -> WorkflowWebProductClaim? {
        let json = jsonObjectText(from: text)
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let rawLevel = (object["identityLevel"] as? String) ?? "unknown"
        let level = WorkflowKnowledgeIdentityLevel(rawValue: rawLevel) ?? .unknown
        let facts = object["confirmedFacts"] as? [String] ?? []
        let unknowns = object["unknowns"] as? [String] ?? []
        return WorkflowWebProductClaim(
            status: (object["status"] as? String) ?? "insufficient",
            canonicalName: ((object["canonicalName"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            identityLevel: level,
            confirmedFacts: facts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            unknowns: unknowns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        )
    }

    private static func jsonObjectText(from text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = clean.firstIndex(of: "{"), let end = clean.lastIndex(of: "}"), start <= end else {
            return clean
        }
        return String(clean[start...end])
    }

    /// 解码模型提取的创作要素，并容忍第一个数组对象起始符被模型漏写的单一常见笔误。
    ///
    /// 修复只发生在 `requirements` 数组紧接 `id` 键时；其余无效内容仍会被拒绝，
    /// 后续人物、产品和车型也仍逐项执行严格身份匹配。
    static func parseKnowledgeRequirements(from text: String) -> WorkflowKnowledgeRequirements? {
        let cleanJSON = jsonObjectText(from: text)
        if let envelope = decodeKnowledgeRequirements(cleanJSON) {
            return envelope
        }
        guard let repairedJSON = repairingFirstKnowledgeRequirement(in: cleanJSON) else {
            return nil
        }
        return decodeKnowledgeRequirements(repairedJSON)
    }

    private static func decodeKnowledgeRequirements(_ text: String) -> WorkflowKnowledgeRequirements? {
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(WorkflowKnowledgeRequirements.self, from: data),
              !envelope.requirements.isEmpty
        else { return nil }
        return envelope
    }

    private static func repairingFirstKnowledgeRequirement(in text: String) -> String? {
        let prefixPattern = #""requirements"\s*:\s*\[\s*"#
        guard let prefixRange = text.range(of: prefixPattern, options: .regularExpression) else {
            return nil
        }
        let remainder = text[prefixRange.upperBound...]
        var repaired = text
        if remainder.hasPrefix(#"id":"#) {
            repaired.insert(contentsOf: "{\"", at: prefixRange.upperBound)
            return repaired
        }
        if remainder.hasPrefix(#""id":"#) {
            repaired.insert("{", at: prefixRange.upperBound)
            return repaired
        }
        return nil
    }

    /// 严格身份核验；系列级或未命名产品按稳定用途锚点核验，避免把临时概括当成正式 SKU。
    static func matches(
        requirement: WorkflowKnowledgeRequirement,
        evidence: WorkflowKnowledgeDocumentEvidence
    ) -> Bool {
        let haystack = normalizedIdentityText(([evidence.title] + evidence.tags + [evidence.content]).joined(separator: " "))
        if requirement.isGenericVehicleScene {
            return ["车内", "座舱", "汽车内饰", "驾驶舱"].contains { haystack.contains(normalizedIdentityText($0)) }
        }
        if isProvisionalProductRequirement(requirement) {
            let hasProductEvidence = [
                "产品", "商品", "品类", "型号", "包装", "product", "配件", "替换芯", "香氛芯", "陶瓷芯",
            ].contains {
                haystack.contains(normalizedIdentityText($0))
            }
            guard hasProductEvidence else { return false }
            let anchors = productSeriesAnchors(requirement)
            let matchedAnchors = anchors.filter(haystack.contains)
            let productSpecificMatches = matchedAnchors.filter(isProductSpecificSeriesAnchor)
            return productSpecificMatches.contains { $0.count >= 6 }
                || (matchedAnchors.count >= 2 && !productSpecificMatches.isEmpty)
        }
        let identities = ([requirement.name] + requirement.aliases)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return identities.contains { identity in
            let normalized = normalizedIdentityText(identity)
            if evidence.tags.contains(where: { normalizedIdentityText($0) == normalized }) { return true }
            let escaped = NSRegularExpression.escapedPattern(for: identity)
            let pattern = "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
            let text = evidence.title + "\n" + evidence.content
            return regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil
        }
    }

    /// 新版身份级别和旧运行中的“不明确”合成名都按系列证据处理。
    private static func isProvisionalProductRequirement(_ requirement: WorkflowKnowledgeRequirement) -> Bool {
        requirement.category == .product
            && (requirement.identityLevel != .exact || isProvisionalProductName(requirement.name))
    }

    private static func isProvisionalProductName(_ name: String) -> Bool {
        let normalized = normalizedIdentityText(name)
        if normalized == normalizedIdentityText("文章未明确目标产品")
            || normalized == normalizedIdentityText("未明确目标产品")
            || normalized == normalizedIdentityText("未知产品") {
            return true
        }
        return ["未明确", "未确认", "待确认", "未知", "不详", "不明"]
            .map(normalizedIdentityText)
            .contains(where: normalized.contains)
    }

    /// 从系列名称、用途和检索词中提取可由补库或联网资料命中的稳定语义锚点。
    private static func productSeriesAnchors(_ requirement: WorkflowKnowledgeRequirement) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        let ignored = Set([
            "产品", "商品", "资料", "目标产品", "产品外观", "平替", "文章核心目标产品",
        ].map(normalizedIdentityText))
        let uncertaintyFragments = ["未明确", "未确认", "待确认", "未知", "不详", "不明"]
            .map(normalizedIdentityText)
        let source = [requirement.name] + requirement.aliases + requirement.searchTerms + [requirement.role]
        var seen: Set<String> = []
        return source
            .flatMap { $0.components(separatedBy: separators) }
            .map(normalizedIdentityText)
            .filter { anchor in
                guard anchor.count >= 2,
                      !ignored.contains(anchor),
                      !uncertaintyFragments.contains(where: anchor.contains),
                      !seen.contains(anchor)
                else { return false }
                seen.insert(anchor)
                return true
            }
    }

    /// 排除只描述车型、座舱位置或价格的锚点，避免“同车型的任意产品”被当作目标系列。
    private static func isProductSpecificSeriesAnchor(_ anchor: String) -> Bool {
        let productIndicators = ["芯", "香氛", "替换", "陶瓷", "配件", "包装", "商品", "产品", "型号", "sku"]
            .map(normalizedIdentityText)
        if productIndicators.contains(where: anchor.contains) { return true }
        let contextOnly = ["第三代es8", "中控台区域", "车内场景", "驾驶位", "副驾驶", "三十元", "九十元"]
            .map(normalizedIdentityText)
        return !contextOnly.contains(where: anchor.contains)
    }

    private static func normalizedIdentityText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }

    /// 限制语义检索输入长度，防止长文章直接超出嵌入模型上下文。
    ///
    /// 同时保留首尾，让开场角色与结尾产品信息都能参与检索。
    static func compactKnowledgeQuery(_ query: String, maxCharacters: Int = 6_000) -> String {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(200, maxCharacters)
        guard clean.count > limit else { return clean }
        let separator = "\n\n……中间内容已为知识检索压缩……\n\n"
        let available = max(2, limit - separator.count)
        let prefixCount = available / 2
        let suffixCount = available - prefixCount
        return String(clean.prefix(prefixCount)) + separator + String(clean.suffix(suffixCount))
    }

    /// 只把真实图片文件作为分镜参考图，避免将 Markdown/PDF 资料误复制进图片清单。
    private static func isImageReference(_ url: URL?) -> Bool {
        guard let url,
              let type = UTType(filenameExtension: url.pathExtension)
        else { return false }
        return type.conforms(to: .image)
    }

    // MARK: - Scheduling helpers

    private func relevantNodeIDs(targetNodeID: UUID?, workflow: WorkflowDefinition) -> Set<UUID> {
        if let targetNodeID {
            return WorkflowGraphAnalysis.upstreamClosure(targetNodeID: targetNodeID, in: workflow)
        }
        let outputs = workflow.nodes.filter { $0.kind == .output }
        guard !outputs.isEmpty else { return Set(workflow.nodes.map(\.id)) }
        return outputs.reduce(into: Set<UUID>()) { result, output in
            result.formUnion(WorkflowGraphAnalysis.upstreamClosure(targetNodeID: output.id, in: workflow))
        }
    }

    private func isReady(_ node: WorkflowNode, inputs: [String: [WorkflowValue]], settings: SettingsStore) -> Bool {
        if node.kind == .runtimeInput { return true }
        if node.kind == .loop { return inputs["seed"]?.isEmpty == false }
        let effective = WorkflowValidator.effectiveNode(node, settings: settings)
        let required = effective.descriptor.ports(for: effective).filter {
            $0.direction == .input && $0.isRequired
        }
        return required.allSatisfy { inputs[$0.id]?.isEmpty == false }
    }

    private func propagate(
        outputs: [String: WorkflowValue],
        from nodeID: UUID,
        connections: [WorkflowConnection],
        allowedTargets: Set<UUID>,
        into inputs: inout [UUID: [String: [WorkflowValue]]]
    ) {
        for connection in connections where connection.sourceNodeID == nodeID && allowedTargets.contains(connection.targetNodeID) {
            guard let value = outputs[connection.sourcePortID] else { continue }
            let siblings = connections
                .filter { $0.targetNodeID == connection.targetNodeID && $0.targetPortID == connection.targetPortID }
                .sorted {
                    if $0.targetOrder != $1.targetOrder { return $0.targetOrder < $1.targetOrder }
                    return $0.id.uuidString < $1.id.uuidString
                }
            let desiredIndex = siblings.firstIndex(where: { $0.id == connection.id }) ?? siblings.count
            var values = inputs[connection.targetNodeID, default: [:]][connection.targetPortID, default: []]
            values.insert(value, at: min(desiredIndex, values.count))
            inputs[connection.targetNodeID, default: [:]][connection.targetPortID] = values
        }
    }

    private func mediaURLs(_ values: [WorkflowValue], expected: WorkflowValueType, root: URL) -> [URL] {
        values.compactMap { value in
            guard value.valueType == expected else { return nil }
            return root.appendingPathComponent(value.payload)
        }
    }

    private func prepareRuntimeInputs(
        _ values: [String: WorkflowValue],
        workflowID: UUID,
        runID: UUID,
        store: WorkflowStore
    ) throws -> [String: WorkflowValue] {
        let allowed: [WorkflowValueType: Set<String>] = [
            .image: ["jpg", "jpeg", "png", "webp", "bmp", "gif"],
            .video: ["mp4", "mov", "webm", "mkv", "avi"],
            .audio: ["mp3", "wav", "m4a", "aac", "ogg", "flac"],
        ]
        let assets = store.assetsDirectory(workflowID: workflowID, runID: runID)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        var result: [String: WorkflowValue] = [:]
        for (key, value) in values {
            guard value.valueType != .text, value.valueType != .knowledgeCollection else {
                result[key] = value
                continue
            }
            let source = URL(fileURLWithPath: value.payload)
            if value.valueType == .folder {
                var isDirectory: ObjCBool = false
                guard source.isFileURL,
                      FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory),
                      isDirectory.boolValue,
                      FileManager.default.isReadableFile(atPath: source.path)
                else {
                    throw WorkflowExecutionError.invalidValue("运行输入文件夹不可读：\(source.lastPathComponent)")
                }
                let target = assets.appendingPathComponent(
                    "input-\(UUID().uuidString)-\(source.lastPathComponent)",
                    isDirectory: true
                )
                try FileManager.default.copyItem(at: source, to: target)
                result[key] = .folder("Assets/\(target.lastPathComponent)")
                continue
            }
            guard source.isFileURL,
                  FileManager.default.isReadableFile(atPath: source.path),
                  allowed[value.valueType]?.contains(source.pathExtension.lowercased()) == true
            else {
                throw WorkflowExecutionError.invalidValue("运行输入媒体不可读或文件类型不受支持：\(source.lastPathComponent)")
            }
            let target = assets.appendingPathComponent("input-\(UUID().uuidString)-\(source.lastPathComponent)")
            try FileManager.default.copyItem(at: source, to: target)
            let relative = "Assets/\(target.lastPathComponent)"
            switch value {
            case .knowledgeCollection: result[key] = value
            case .image: result[key] = .image(relative)
            case .video: result[key] = .video(relative)
            case .audio: result[key] = .audio(relative)
            case .folder: result[key] = .folder(relative)
            case .text: result[key] = value
            }
        }
        return result
    }

    /// 创建时间相同也使用 UUID 收尾，保证多个就绪分支每次都以相同顺序串行执行。
    private func stableNodeOrder(_ lhs: WorkflowNode, _ rhs: WorkflowNode) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    // MARK: - Run mutation helpers

    private func updateNodeRun(
        nodeID: UUID,
        runID: UUID,
        store: WorkflowStore,
        status: WorkflowNodeRunStatus,
        outputs: [String: WorkflowValue]? = nil,
        message: String? = nil,
        progress: Double? = nil,
        iteration: Int? = nil,
        persist: Bool
    ) {
        guard var run = store.activeRun, run.id == runID,
              let index = run.nodeRuns.firstIndex(where: { $0.nodeID == nodeID })
        else { return }
        let previous = run.nodeRuns[index].status
        run.nodeRuns[index].status = status
        if let outputs { run.nodeRuns[index].outputs = outputs }
        run.nodeRuns[index].message = message
        run.nodeRuns[index].progress = progress
        if let iteration { run.nodeRuns[index].iteration = iteration }
        if status == .running && previous != .running { run.nodeRuns[index].startedAt = Date() }
        if [.waiting, .succeeded, .warning, .failed, .cancelled, .skipped].contains(status) {
            run.nodeRuns[index].endedAt = Date()
        }
        if persist { store.saveRun(run) } else { store.activeRun = run }
    }

    private func updateLiveOutputs(
        nodeID: UUID,
        runID: UUID,
        store: WorkflowStore,
        outputs: [String: WorkflowValue]
    ) {
        guard var run = store.activeRun, run.id == runID,
              let index = run.nodeRuns.firstIndex(where: { $0.nodeID == nodeID })
        else { return }
        run.nodeRuns[index].outputs = outputs
        run.nodeRuns[index].message = "正在接收流式结果"
        store.activeRun = run
    }

    private func updateProgress(
        nodeID: UUID,
        runID: UUID,
        store: WorkflowStore,
        event: MediaGenerationProgress
    ) {
        updateNodeRun(
            nodeID: nodeID,
            runID: runID,
            store: store,
            status: .running,
            message: event.message,
            progress: event.fraction,
            persist: false
        )
    }

    private func appendWarning(_ message: String, runID: UUID, store: WorkflowStore) {
        guard var run = store.activeRun, run.id == runID else { return }
        if !run.warnings.contains(message) { run.warnings.append(message) }
        store.saveRun(run)
    }

    private func finishRun(runID: UUID, store: WorkflowStore, status: WorkflowRunStatus) {
        guard var run = store.activeRun, run.id == runID else { return }
        run.status = status
        run.endedAt = Date()
        store.saveRun(run)
    }

    private func suspendRun(runID: UUID, gaps: [WorkflowKnowledgeGap], store: WorkflowStore) {
        guard var run = store.activeRun, run.id == runID else { return }
        run.status = .waitingForKnowledge
        run.pendingKnowledgeGaps = gaps
        run.endedAt = nil
        store.saveRun(run)
    }

    private func failRun(runID: UUID, store: WorkflowStore, message: String) {
        guard var run = store.activeRun, run.id == runID else { return }
        run.status = .failed
        run.endedAt = Date()
        if !run.warnings.contains(message) { run.warnings.append(message) }
        for index in run.nodeRuns.indices where run.nodeRuns[index].status == .pending {
            run.nodeRuns[index].status = .skipped
            run.nodeRuns[index].endedAt = Date()
            run.nodeRuns[index].message = "上游失败，未执行"
        }
        store.saveRun(run)
    }

    private func cancelRun(runID: UUID, store: WorkflowStore) {
        guard var run = store.activeRun, run.id == runID else { return }
        run.status = .cancelled
        run.endedAt = Date()
        for index in run.nodeRuns.indices where [.pending, .running].contains(run.nodeRuns[index].status) {
            run.nodeRuns[index].status = .cancelled
            run.nodeRuns[index].endedAt = Date()
            run.nodeRuns[index].message = run.nodeRuns[index].startedAt == nil ? "运行已停止，未执行" : "用户停止运行"
        }
        store.saveRun(run)
    }

    private func currentRunHasWarnings(runID: UUID, store: WorkflowStore) -> Bool {
        guard let run = store.activeRun, run.id == runID else { return false }
        return !run.warnings.isEmpty || run.nodeRuns.contains { $0.status == .warning }
    }
}

/// 视觉模型为一张图片整理出的知识资料。
private struct GeneratedKnowledge {
    var title: String
    var content: String
    var tags: [String]
}
