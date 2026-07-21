/// 工作流端口、配置、环路结构与费用次数预估。

import Foundation

/// 工作流校验严重程度。
enum WorkflowValidationSeverity: String, Hashable {
    case warning
    case error
}

/// 一条可定位到节点的工作流校验信息。
struct WorkflowValidationIssue: Identifiable, Hashable {
    var id = UUID()
    var severity: WorkflowValidationSeverity
    var message: String
    var nodeIDs: [UUID]
}

/// 循环节点控制的强连通分量。
struct WorkflowLoopComponent: Hashable {
    var loopNodeID: UUID
    var nodeIDs: Set<UUID>
}

/// 运行前展示的最大调用次数估计。
struct WorkflowCostEstimate: Hashable {
    var llmCalls: Int = 0
    var imageCalls: Int = 0
    var videoCalls: Int = 0
}

/// 工作流静态校验器。
@MainActor
enum WorkflowValidator {
    /// 校验端口、配置和显式循环规则。
    static func validate(
        _ workflow: WorkflowDefinition,
        settings: SettingsStore,
        registry: MediaAdapterRegistry = .shared
    ) -> [WorkflowValidationIssue] {
        var issues: [WorkflowValidationIssue] = []
        let nodesByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })

        if workflow.nodes.isEmpty {
            issues.append(error("工作流还没有节点"))
            return issues
        }
        if !workflow.nodes.contains(where: { $0.kind == .output }) {
            issues.append(warning("工作流没有结果输出节点，运行结果只能在节点记录中查看"))
        }

        for node in workflow.nodes {
            let effective = effectiveNode(node, settings: settings)
            let descriptor = effective.descriptor
            if case .unsupported = node.kind {
                issues.append(error("“\(node.displayTitle)”的节点类型在当前版本不可用", node.id))
                continue
            }
            for port in descriptor.ports(for: effective) where port.direction == .input && port.isRequired {
                let connected = workflow.connections.contains {
                    $0.targetNodeID == node.id && $0.targetPortID == port.id
                }
                if !connected {
                    issues.append(error("“\(node.displayTitle)”缺少必填输入“\(port.title)”", node.id))
                }
            }

            switch node.kind {
            case .runtimeInput:
                if node.configuration.parameterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(error("运行时输入的参数名称不能为空", node.id))
                }
            case .promptTemplate:
                let template = resolvedTemplate(for: node, settings: settings).template
                if template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(error("提示词模板不能为空", node.id))
                }
                if resolvedTemplate(for: node, settings: settings).usedSnapshot {
                    issues.append(warning("“\(node.displayTitle)”绑定的提示词已删除，将使用保存快照", node.id))
                }
            case .knowledgeSearch:
                if settings.knowledgeEmbeddingProviderID == nil || settings.knowledgeEmbeddingModel.isEmpty {
                    issues.append(error("知识检索节点需要先配置嵌入服务商和模型", node.id))
                }
                if let providerID = settings.knowledgeEmbeddingProviderID,
                   settings.apiKey(for: providerID).isEmpty {
                    issues.append(error("知识检索使用的嵌入服务商还没有 API Key", node.id))
                }
            case .llm:
                validateLLM(node, settings: settings, issues: &issues)
            case .imageGeneration:
                validateImage(node, settings: settings, registry: registry, issues: &issues)
            case .videoGeneration:
                validateVideo(node, settings: settings, registry: registry, issues: &issues)
            case .condition:
                validateComparison(node, issues: &issues)
            case .loop:
                validateComparison(node, issues: &issues)
                if !(1...20).contains(node.configuration.maxIterations) {
                    issues.append(error("循环次数必须在 1 到 20 之间", node.id))
                }
            case .output, .unsupported:
                break
            }
        }

        var targetCounts: [String: Int] = [:]
        for connection in workflow.connections {
            guard let source = nodesByID[connection.sourceNodeID],
                  let target = nodesByID[connection.targetNodeID]
            else {
                issues.append(error("存在指向已删除节点的连线"))
                continue
            }
            let sourceNode = effectiveNode(source, settings: settings)
            let targetNode = effectiveNode(target, settings: settings)
            guard let sourcePort = sourceNode.descriptor.ports(for: sourceNode).first(where: {
                $0.id == connection.sourcePortID && $0.direction == .output
            }) else {
                issues.append(error("“\(source.displayTitle)”的输出端口已不存在", source.id))
                continue
            }
            guard let targetPort = targetNode.descriptor.ports(for: targetNode).first(where: {
                $0.id == connection.targetPortID && $0.direction == .input
            }) else {
                issues.append(error("“\(target.displayTitle)”的输入端口已不存在", target.id))
                continue
            }
            if !sourcePort.valueType.canConnect(to: targetPort.valueType) {
                issues.append(error(
                    "\(sourcePort.valueType.title)不能连接到\(targetPort.valueType.title)",
                    [source.id, target.id]
                ))
            }
            if target.kind == .videoGeneration,
               targetPort.id == "referenceImage",
               let provider = settings.videoProvider(id: target.configuration.providerID),
               let adapter = registry.videoAdapter(id: provider.adapterID),
               !adapter.descriptor.supportsReferenceImage {
                issues.append(error("所选生视频适配器不支持参考图片", target.id))
            }
            if target.kind == .imageGeneration,
               targetPort.id == "maskImage",
               let provider = settings.imageProvider(id: target.configuration.providerID),
               let adapter = registry.imageAdapter(id: provider.adapterID),
               !adapter.descriptor.supportsMaskImage {
                issues.append(error("所选生图适配器不支持编辑遮罩", target.id))
            }
            let key = "\(target.id.uuidString)|\(targetPort.id)"
            targetCounts[key, default: 0] += 1
            if targetCounts[key, default: 0] > 1 {
                issues.append(error("输入端口“\(targetPort.title)”连接了多条线", target.id))
            }
        }

        issues.append(contentsOf: validateCycles(workflow))
        return issues
    }

    /// 按显式循环上限估算一次整图运行的最大付费调用次数。
    static func estimateCosts(_ workflow: WorkflowDefinition) -> WorkflowCostEstimate {
        let components = WorkflowGraphAnalysis.loopComponents(in: workflow)
        var multiplier: [UUID: Int] = [:]
        for component in components {
            let count = workflow.nodes.first(where: { $0.id == component.loopNodeID })?.configuration.maxIterations ?? 1
            for id in component.nodeIDs { multiplier[id] = max(1, min(20, count)) }
        }
        var result = WorkflowCostEstimate()
        for node in workflow.nodes {
            let count = multiplier[node.id] ?? 1
            switch node.kind {
            case .llm: result.llmCalls += count
            case .imageGeneration: result.imageCalls += count
            case .videoGeneration: result.videoCalls += count
            default: break
            }
        }
        return result
    }

    /// 返回提示词库最新模板或节点保存的快照。
    static func resolvedTemplate(for node: WorkflowNode, settings: SettingsStore) -> (template: String, usedSnapshot: Bool) {
        guard node.configuration.usesPromptLibrary else { return (node.configuration.text, false) }
        if let item = settings.promptItem(id: node.configuration.promptItemID) {
            return (item.template, false)
        }
        return (node.configuration.promptSnapshot, true)
    }

    /// 用最新提示词正文构造仅供端口与校验使用的节点副本。
    static func effectiveNode(_ node: WorkflowNode, settings: SettingsStore) -> WorkflowNode {
        guard node.kind == .promptTemplate else { return node }
        var copy = node
        copy.configuration.promptSnapshot = resolvedTemplate(for: node, settings: settings).template
        return copy
    }

    private static func validateLLM(
        _ node: WorkflowNode,
        settings: SettingsStore,
        issues: inout [WorkflowValidationIssue]
    ) {
        guard let provider = settings.provider(id: node.configuration.providerID) else {
            issues.append(error("“\(node.displayTitle)”还没有选择 LLM 服务商", node.id))
            return
        }
        if settings.apiKey(for: provider.id).isEmpty {
            issues.append(error("“\(provider.name)”还没有配置 API Key", node.id))
        }
        if node.configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(error("“\(node.displayTitle)”还没有选择模型", node.id))
        }
    }

    private static func validateImage(
        _ node: WorkflowNode,
        settings: SettingsStore,
        registry: MediaAdapterRegistry,
        issues: inout [WorkflowValidationIssue]
    ) {
        guard let provider = settings.imageProvider(id: node.configuration.providerID) else {
            issues.append(error("“\(node.displayTitle)”还没有选择生图服务商", node.id))
            return
        }
        guard let adapter = registry.imageAdapter(id: provider.adapterID) else {
            issues.append(error("生图适配器“\(provider.adapterID)”未注册", node.id))
            return
        }
        if settings.imageAPIKey(for: provider.id).isEmpty {
            issues.append(error("“\(provider.name)”还没有配置 API Key", node.id))
        }
        if node.configuration.imageOperation == .edit && !adapter.descriptor.supportsImageEditing {
            issues.append(error("所选生图适配器不支持图片编辑", node.id))
        }
        if node.configuration.model.isEmpty { issues.append(error("生图节点还没有选择模型", node.id)) }
        let size = node.configuration.mediaSize.isEmpty ? provider.defaultSize : node.configuration.mediaSize
        if !adapter.descriptor.supportedSizes.isEmpty && !adapter.descriptor.supportedSizes.contains(size) {
            issues.append(error("生图适配器不支持尺寸 \(size)", node.id))
        }
    }

    private static func validateVideo(
        _ node: WorkflowNode,
        settings: SettingsStore,
        registry: MediaAdapterRegistry,
        issues: inout [WorkflowValidationIssue]
    ) {
        guard let provider = settings.videoProvider(id: node.configuration.providerID) else {
            issues.append(error("“\(node.displayTitle)”还没有选择生视频服务商", node.id))
            return
        }
        guard let adapter = registry.videoAdapter(id: provider.adapterID) else {
            issues.append(error("生视频适配器“\(provider.adapterID)”未注册", node.id))
            return
        }
        if settings.videoAPIKey(for: provider.id).isEmpty {
            issues.append(error("“\(provider.name)”还没有配置 API Key", node.id))
        }
        if node.configuration.model.isEmpty { issues.append(error("生视频节点还没有选择模型", node.id)) }
        let size = node.configuration.mediaSize.isEmpty ? "720x1280" : node.configuration.mediaSize
        if !adapter.descriptor.supportedSizes.isEmpty && !adapter.descriptor.supportedSizes.contains(size) {
            issues.append(error("生视频适配器不支持尺寸 \(size)", node.id))
        }
        if !adapter.descriptor.supportedDurations.isEmpty && !adapter.descriptor.supportedDurations.contains(node.configuration.durationSeconds) {
            issues.append(error("生视频适配器不支持 \(node.configuration.durationSeconds) 秒时长", node.id))
        }
    }

    private static func validateComparison(
        _ node: WorkflowNode,
        issues: inout [WorkflowValidationIssue]
    ) {
        if node.configuration.comparison.needsOperand &&
            node.configuration.comparisonValue.isEmpty {
            issues.append(error("“\(node.displayTitle)”的比较值不能为空", node.id))
        }
        if node.configuration.comparison == .regex {
            do { _ = try NSRegularExpression(pattern: node.configuration.comparisonValue) }
            catch let regexError {
                _ = regexError
                issues.append(error("“\(node.displayTitle)”的正则表达式无效", node.id))
            }
        }
    }

    private static func validateCycles(_ workflow: WorkflowDefinition) -> [WorkflowValidationIssue] {
        var issues: [WorkflowValidationIssue] = []
        let nodesByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        let components = WorkflowGraphAnalysis.stronglyConnectedComponents(in: workflow).filter { component in
            component.count > 1 || workflow.connections.contains {
                $0.sourceNodeID == $0.targetNodeID && component.contains($0.sourceNodeID)
            }
        }
        for component in components {
            let loopNodes = component.compactMap { id -> WorkflowNode? in
                guard let node = nodesByID[id], node.kind == .loop else { return nil }
                return node
            }
            guard loopNodes.count == 1, let loop = loopNodes.first else {
                let names = component.compactMap { nodesByID[$0]?.displayTitle }.joined(separator: "、")
                issues.append(error("环路“\(names)”必须且只能包含一个显式循环节点", Array(component)))
                continue
            }
            let internalConnections = workflow.connections.filter {
                component.contains($0.sourceNodeID) && component.contains($0.targetNodeID)
            }
            if internalConnections.contains(where: {
                $0.sourceNodeID == loop.id && $0.sourcePortID != "iteration"
            }) {
                issues.append(error("循环内部只能从“继续循环”端口进入循环体", loop.id))
            }
            if internalConnections.contains(where: {
                $0.targetNodeID == loop.id && $0.targetPortID != "feedback"
            }) {
                issues.append(error("循环体只能连接回循环节点的“反馈值”端口", loop.id))
            }
            let entering = workflow.connections.filter {
                !component.contains($0.sourceNodeID) && component.contains($0.targetNodeID)
            }
            if entering.contains(where: { $0.targetNodeID != loop.id || $0.targetPortID != "seed" }) {
                issues.append(error("循环外部只能连接循环节点的“初始值”端口", Array(component)))
            }
            let leaving = workflow.connections.filter {
                component.contains($0.sourceNodeID) && !component.contains($0.targetNodeID)
            }
            if leaving.contains(where: { $0.sourceNodeID != loop.id || $0.sourcePortID != "completed" }) {
                issues.append(error("循环内部只能通过“循环完成”端口离开", Array(component)))
            }
            let bodyIDs = component.subtracting([loop.id])
            if WorkflowGraphAnalysis.containsCycle(nodeIDs: bodyIDs, connections: internalConnections) {
                issues.append(error("循环体内部还有一个未经过显式循环节点的环路", Array(bodyIDs)))
            }
        }
        return issues
    }

    private static func error(_ message: String, _ nodeID: UUID? = nil) -> WorkflowValidationIssue {
        WorkflowValidationIssue(severity: .error, message: message, nodeIDs: nodeID.map { [$0] } ?? [])
    }

    private static func error(_ message: String, _ nodeIDs: [UUID]) -> WorkflowValidationIssue {
        WorkflowValidationIssue(severity: .error, message: message, nodeIDs: nodeIDs)
    }

    private static func warning(_ message: String, _ nodeID: UUID? = nil) -> WorkflowValidationIssue {
        WorkflowValidationIssue(severity: .warning, message: message, nodeIDs: nodeID.map { [$0] } ?? [])
    }
}

/// 图结构算法，供校验器和执行器共享。
enum WorkflowGraphAnalysis {
    /// 为单节点运行裁剪出其上游依赖；目标落在循环中时保留完整循环组件。
    static func scopedWorkflow(targetNodeID: UUID?, in workflow: WorkflowDefinition) -> WorkflowDefinition {
        guard targetNodeID != nil else { return workflow }
        let ids = upstreamClosure(targetNodeID: targetNodeID, in: workflow)
        var scoped = workflow
        scoped.nodes = workflow.nodes.filter { ids.contains($0.id) }
        scoped.connections = workflow.connections.filter {
            ids.contains($0.sourceNodeID) && ids.contains($0.targetNodeID)
        }
        return scoped
    }

    /// 返回包含一个显式循环节点的强连通分量。
    static func loopComponents(in workflow: WorkflowDefinition) -> [WorkflowLoopComponent] {
        let nodesByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        return stronglyConnectedComponents(in: workflow).compactMap { component in
            let hasCycle = component.count > 1 || workflow.connections.contains {
                $0.sourceNodeID == $0.targetNodeID && component.contains($0.sourceNodeID)
            }
            guard hasCycle else { return nil }
            let loops = component.filter { nodesByID[$0]?.kind == .loop }
            guard loops.count == 1, let loop = loops.first else { return nil }
            return WorkflowLoopComponent(loopNodeID: loop, nodeIDs: component)
        }
    }

    /// Tarjan 强连通分量。
    static func stronglyConnectedComponents(in workflow: WorkflowDefinition) -> [Set<UUID>] {
        let nodeIDs = workflow.nodes.map(\.id)
        let adjacency = Dictionary(grouping: workflow.connections, by: \.sourceNodeID)
            .mapValues { $0.map(\.targetNodeID) }
        var index = 0
        var indices: [UUID: Int] = [:]
        var lowLinks: [UUID: Int] = [:]
        var stack: [UUID] = []
        var onStack: Set<UUID> = []
        var result: [Set<UUID>] = []

        func visit(_ node: UUID) {
            indices[node] = index
            lowLinks[node] = index
            index += 1
            stack.append(node)
            onStack.insert(node)

            for next in adjacency[node] ?? [] {
                if indices[next] == nil {
                    visit(next)
                    lowLinks[node] = min(lowLinks[node]!, lowLinks[next]!)
                } else if onStack.contains(next) {
                    lowLinks[node] = min(lowLinks[node]!, indices[next]!)
                }
            }
            if lowLinks[node] == indices[node] {
                var component: Set<UUID> = []
                while let last = stack.popLast() {
                    onStack.remove(last)
                    component.insert(last)
                    if last == node { break }
                }
                result.append(component)
            }
        }
        for node in nodeIDs where indices[node] == nil { visit(node) }
        return result
    }

    /// 判断指定子图是否仍包含环路。
    static func containsCycle(nodeIDs: Set<UUID>, connections: [WorkflowConnection]) -> Bool {
        let adjacency = Dictionary(grouping: connections.filter {
            nodeIDs.contains($0.sourceNodeID) && nodeIDs.contains($0.targetNodeID)
        }, by: \.sourceNodeID).mapValues { $0.map(\.targetNodeID) }
        var visiting: Set<UUID> = []
        var visited: Set<UUID> = []
        func visit(_ id: UUID) -> Bool {
            if visiting.contains(id) { return true }
            if visited.contains(id) { return false }
            visiting.insert(id)
            for next in adjacency[id] ?? [] where visit(next) { return true }
            visiting.remove(id)
            visited.insert(id)
            return false
        }
        return nodeIDs.contains(where: visit)
    }

    /// 计算目标节点需要的上游闭包；命中循环组件时包含完整循环体。
    static func upstreamClosure(targetNodeID: UUID?, in workflow: WorkflowDefinition) -> Set<UUID> {
        guard let targetNodeID else { return Set(workflow.nodes.map(\.id)) }
        let components = loopComponents(in: workflow)
        let reverse = Dictionary(grouping: workflow.connections, by: \.targetNodeID)
            .mapValues { $0.map(\.sourceNodeID) }
        var result: Set<UUID> = []
        var queue: [UUID] = [targetNodeID]
        while let id = queue.popLast() {
            guard result.insert(id).inserted else { continue }
            if let component = components.first(where: { $0.nodeIDs.contains(id) }) {
                for member in component.nodeIDs where result.insert(member).inserted {
                    queue.append(member)
                }
            }
            queue.append(contentsOf: reverse[id] ?? [])
        }
        return result
    }
}
