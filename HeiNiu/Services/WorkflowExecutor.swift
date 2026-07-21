/// 工作流串行执行器：条件分支、显式循环、模型调用与媒体产物。

import Foundation
import Observation

/// 执行器所需的知识检索最小接口，便于使用隔离模拟实现验证调度。
@MainActor
protocol WorkflowKnowledgeSearching {
    func search(
        query: String,
        settings: SettingsStore,
        collectionID: UUID?,
        tags: [String],
        limit: Int
    ) async throws -> [KnowledgeSearchResult]
}

extension KnowledgeStore: WorkflowKnowledgeSearching {}

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

    /// 开始整图或目标节点运行。
    func start(
        workflow: WorkflowDefinition,
        targetNodeID: UUID?,
        runtimeInputs: [String: WorkflowValue],
        settings: SettingsStore,
        knowledge: any WorkflowKnowledgeSearching,
        store: WorkflowStore
    ) {
        guard !isRunning else { return }
        let validationWorkflow = WorkflowGraphAnalysis.scopedWorkflow(targetNodeID: targetNodeID, in: workflow)
        var issues = WorkflowValidator.validate(validationWorkflow, settings: settings, registry: registry)
        let relevant = relevantNodeIDs(targetNodeID: targetNodeID, workflow: workflow)
        for node in workflow.nodes where relevant.contains(node.id) && node.kind == .runtimeInput {
            let value = runtimeInputs[node.id.uuidString]
                ?? (node.configuration.runtimeInputType == .text ? .text(node.configuration.text) : nil)
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
            return
        }

        isRunning = true
        statusMessage = targetNodeID == nil ? "正在运行工作流" : "正在运行选中节点"
        runTask = Task { [weak self] in
            guard let self else { return }
            await self.performRun(
                workflow: workflow,
                targetNodeID: targetNodeID,
                runtimeInputs: runtimeInputs,
                settings: settings,
                knowledge: knowledge,
                store: store
            )
        }
    }

    /// 停止本地执行与媒体轮询。
    func cancel() {
        runTask?.cancel()
        statusMessage = "正在停止"
    }

    private func performRun(
        workflow: WorkflowDefinition,
        targetNodeID: UUID?,
        runtimeInputs: [String: WorkflowValue],
        settings: SettingsStore,
        knowledge: any WorkflowKnowledgeSearching,
        store: WorkflowStore
    ) async {
        let relevant = relevantNodeIDs(targetNodeID: targetNodeID, workflow: workflow)
        var run = WorkflowRun(
            workflowID: workflow.id,
            targetNodeID: targetNodeID,
            runtimeInputs: runtimeInputs,
            nodes: workflow.nodes
        )
        for index in run.nodeRuns.indices where !relevant.contains(run.nodeRuns[index].nodeID) {
            run.nodeRuns[index].status = .skipped
            run.nodeRuns[index].message = "不在本次运行范围内"
        }
        do {
            try Task.checkCancellation()
            let preparedRuntimeInputs = try prepareRuntimeInputs(
                runtimeInputs,
                workflowID: workflow.id,
                runID: run.id,
                store: store
            )
            run.runtimeInputs = preparedRuntimeInputs
            store.saveRun(run)
            let loopComponents = WorkflowGraphAnalysis.loopComponents(in: workflow)
            let bodyNodeIDs = Set(loopComponents.flatMap { $0.nodeIDs.subtracting([$0.loopNodeID]) })
            var inputs: [UUID: [String: [WorkflowValue]]] = [:]
            var executed: Set<UUID> = []
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
        knowledge: any WorkflowKnowledgeSearching,
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
        knowledge: any WorkflowKnowledgeSearching,
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
                status: error is CancellationError ? .cancelled : .failed,
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
        knowledge: any WorkflowKnowledgeSearching,
        store: WorkflowStore
    ) async throws -> [String: WorkflowValue] {
        try Task.checkCancellation()
        try await executionHook?(node)
        try Task.checkCancellation()
        switch node.kind {
        case .runtimeInput:
            let expectedType = node.configuration.runtimeInputType.valueType
            let value = runtimeInputs[node.id.uuidString]
                ?? (node.configuration.runtimeInputType == .text ? .text(node.configuration.text) : nil)
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
                query: query,
                settings: settings,
                collectionID: node.configuration.collectionID,
                tags: node.configuration.tags,
                limit: node.configuration.topK
            )
            let text = results.map {
                "[\($0.documentTitle)#片段\($0.ordinal + 1) · \(String(format: "%.3f", $0.score))]\n\($0.text)"
            }.joined(separator: "\n\n")
            return ["context": .text(text)]

        case .llm:
            guard case .text(let prompt) = inputs["prompt"]?.first,
                  let provider = settings.provider(id: node.configuration.providerID)
            else { throw LLMError.missingProvider }
            let model = node.configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
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
            guard value.valueType != .text else {
                result[key] = value
                continue
            }
            let source = URL(fileURLWithPath: value.payload)
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
            case .image: result[key] = .image(relative)
            case .video: result[key] = .video(relative)
            case .audio: result[key] = .audio(relative)
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
        if [.succeeded, .warning, .failed, .cancelled, .skipped].contains(status) {
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
