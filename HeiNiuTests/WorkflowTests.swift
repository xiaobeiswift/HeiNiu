import Foundation
import XCTest
@testable import HeiNiu

final class WorkflowModelTests: XCTestCase {
    @MainActor
    func testDefinitionRoundTripAndTolerantDefaults() throws {
        let original = WorkflowDefinition.starter(named: "往返测试")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(WorkflowDefinition.self, from: encoder.encode(original))
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, "往返测试")
        XCTAssertEqual(decoded.nodes.map(\.kind), original.nodes.map(\.kind))
        XCTAssertEqual(decoded.connections.count, 2)

        let legacy = Data(#"{"name":"旧工作流","nodes":[{"kind":"runtimeInput"}]}"#.utf8)
        let tolerant = try decoder.decode(WorkflowDefinition.self, from: legacy)
        XCTAssertEqual(tolerant.name, "旧工作流")
        XCTAssertEqual(tolerant.nodes.first?.position, .zero)
        XCTAssertEqual(tolerant.nodes.first?.configuration.parameterName, "输入")
        XCTAssertTrue(tolerant.connections.isEmpty)
    }

    @MainActor
    func testUnknownNodeAndRunStatusRemainDecodable() throws {
        let node = try JSONDecoder().decode(
            WorkflowNode.self,
            from: Data(#"{"kind":"futureNode","position":{"x":3,"y":4}}"#.utf8)
        )
        XCTAssertEqual(node.kind, .unsupported("futureNode"))

        let run = try JSONDecoder().decode(
            WorkflowRun.self,
            from: Data(#"{"status":"futureStatus","nodeRuns":[],"runtimeInputs":{}}"#.utf8)
        )
        XCTAssertEqual(run.status, .failed)
        XCTAssertTrue(run.warnings.isEmpty)
    }

    @MainActor
    func testLegacyProvidersMigrateToStableAdapterIDs() throws {
        let image = try JSONDecoder().decode(
            ImageProvider.self,
            from: Data(#"{"name":"旧生图","kind":"openAIImages"}"#.utf8)
        )
        XCTAssertEqual(image.adapterID, ImageProvider.openAIAdapterID)

        let video = try JSONDecoder().decode(
            VideoProvider.self,
            from: Data(#"{"name":"旧网关","kind":"generic"}"#.utf8)
        )
        XCTAssertEqual(video.adapterID, VideoProvider.unconfiguredGenericAdapterID)
        XCTAssertNil(MediaAdapterRegistry.shared.videoAdapter(id: video.adapterID))
    }

    @MainActor
    func testAllNodeAndAdapterHelpIsComplete() {
        for descriptor in WorkflowNodeCatalog.all {
            XCTAssertFalse(descriptor.title.isEmpty, descriptor.id)
            XCTAssertFalse(descriptor.summary.isEmpty, descriptor.id)
            XCTAssertFalse(descriptor.usage.purpose.isEmpty, descriptor.id)
            XCTAssertFalse(descriptor.usage.setupSteps.isEmpty, descriptor.id)
            XCTAssertFalse(descriptor.usage.connectionExample.isEmpty, descriptor.id)
            XCTAssertFalse(descriptor.usage.resultDescription.isEmpty, descriptor.id)
            XCTAssertFalse(descriptor.usage.commonErrors.isEmpty, descriptor.id)

            var configuration = WorkflowNodeConfiguration()
            if descriptor.kind == .promptTemplate { configuration.text = "{{subject}}" }
            let node = WorkflowNode(kind: descriptor.kind, position: .zero, configuration: configuration)
            for port in descriptor.ports(for: node) {
                XCTAssertFalse(port.title.isEmpty, "\(descriptor.id).\(port.id)")
                XCTAssertFalse(port.help.isEmpty, "\(descriptor.id).\(port.id)")
            }
        }

        let chargedKinds: Set<WorkflowNodeKind> = [.knowledgeSearch, .llm, .imageGeneration, .videoGeneration, .loop]
        for kind in chargedKinds {
            XCTAssertFalse(WorkflowNodeCatalog.descriptor(for: kind).usage.warnings.isEmpty, kind.id)
        }

        for adapter in MediaAdapterRegistry.shared.imageDescriptors + MediaAdapterRegistry.shared.videoDescriptors {
            XCTAssertFalse(adapter.displayName.isEmpty, adapter.id)
            XCTAssertFalse(adapter.summary.isEmpty, adapter.id)
            XCTAssertFalse(adapter.endpointHint.isEmpty, adapter.id)
            XCTAssertFalse(adapter.usageNotes.isEmpty, adapter.id)
            XCTAssertFalse(adapter.configurationFields.isEmpty, adapter.id)
            for field in adapter.configurationFields {
                XCTAssertFalse(field.title.isEmpty, "\(adapter.id).\(field.id)")
                XCTAssertFalse(field.help.isEmpty, "\(adapter.id).\(field.id)")
                XCTAssertFalse(field.example.isEmpty, "\(adapter.id).\(field.id)")
            }
        }
    }

    @MainActor
    func testPortTypesComparisonsAndPromptVariables() throws {
        XCTAssertTrue(WorkflowValueType.text.canConnect(to: .any))
        XCTAssertTrue(WorkflowValueType.any.canConnect(to: .video))
        XCTAssertFalse(WorkflowValueType.image.canConnect(to: .text))
        XCTAssertTrue(try WorkflowComparison.contains.evaluate("短剧反转", operand: "反转"))
        XCTAssertTrue(try WorkflowComparison.regex.evaluate("S12", operand: #"S\d+"#))
        XCTAssertFalse(try WorkflowComparison.isEmpty.evaluate("内容", operand: ""))

        var configuration = WorkflowNodeConfiguration()
        configuration.text = "{{brief}} + {{ context }} + {{brief}}"
        XCTAssertEqual(configuration.templateVariables, ["brief", "context"])

        var editConfiguration = WorkflowNodeConfiguration()
        editConfiguration.imageOperation = .edit
        let editNode = WorkflowNode(kind: .imageGeneration, position: .zero, configuration: editConfiguration)
        let editPorts = editNode.descriptor.ports(for: editNode)
        XCTAssertTrue(editPorts.contains { $0.id == "referenceImage" && $0.isRequired })
        XCTAssertTrue(editPorts.contains { $0.id == "maskImage" && !$0.isRequired })

        let futureConfiguration = try JSONDecoder().decode(
            WorkflowNodeConfiguration.self,
            from: Data(#"{"imageOperation":"future-operation"}"#.utf8)
        )
        XCTAssertEqual(futureConfiguration.imageOperation, .generate)
    }
}

final class WorkflowGraphAndStoreTests: XCTestCase {
    @MainActor
    func testGraphRejectsOrdinaryCycleAndRecognizesExplicitLoop() {
        var branchConfiguration = WorkflowNodeConfiguration()
        branchConfiguration.comparison = .isNotEmpty
        let first = WorkflowNode(kind: .condition, position: .zero, configuration: branchConfiguration)
        let second = WorkflowNode(kind: .condition, position: WorkflowPoint(x: 200, y: 0), configuration: branchConfiguration)
        let ordinary = WorkflowDefinition(
            name: "普通环",
            nodes: [first, second],
            connections: [
                WorkflowConnection(sourceNodeID: first.id, sourcePortID: "true", targetNodeID: second.id, targetPortID: "value"),
                WorkflowConnection(sourceNodeID: second.id, sourcePortID: "true", targetNodeID: first.id, targetPortID: "value"),
            ]
        )
        let ordinaryIssues = WorkflowValidator.validate(ordinary, settings: SettingsStore())
        XCTAssertTrue(ordinaryIssues.contains { $0.severity == .error && $0.message.contains("显式循环") })

        var loopConfiguration = WorkflowNodeConfiguration()
        loopConfiguration.comparison = .isNotEmpty
        loopConfiguration.maxIterations = 3
        let input = WorkflowNode(kind: .runtimeInput, position: .zero)
        let loop = WorkflowNode(kind: .loop, position: WorkflowPoint(x: 180, y: 0), configuration: loopConfiguration)
        let body = WorkflowNode(kind: .condition, position: WorkflowPoint(x: 360, y: 0), configuration: branchConfiguration)
        let output = WorkflowNode(kind: .output, position: WorkflowPoint(x: 540, y: 0))
        let explicit = WorkflowDefinition(
            name: "显式循环",
            nodes: [input, loop, body, output],
            connections: [
                WorkflowConnection(sourceNodeID: input.id, sourcePortID: "text", targetNodeID: loop.id, targetPortID: "seed"),
                WorkflowConnection(sourceNodeID: loop.id, sourcePortID: "iteration", targetNodeID: body.id, targetPortID: "value"),
                WorkflowConnection(sourceNodeID: body.id, sourcePortID: "true", targetNodeID: loop.id, targetPortID: "feedback"),
                WorkflowConnection(sourceNodeID: loop.id, sourcePortID: "completed", targetNodeID: output.id, targetPortID: "value"),
            ]
        )
        XCTAssertEqual(WorkflowGraphAnalysis.loopComponents(in: explicit).first?.nodeIDs, Set([loop.id, body.id]))
        let explicitIssues = WorkflowValidator.validate(explicit, settings: SettingsStore())
        XCTAssertFalse(explicitIssues.contains { $0.severity == .error && $0.message.contains("环路") })
    }

    @MainActor
    func testSelectedNodeScopeIncludesUpstreamAndWholeLoop() {
        let input = WorkflowNode(kind: .runtimeInput, position: .zero)
        let output = WorkflowNode(kind: .output, position: WorkflowPoint(x: 200, y: 0))
        let unrelated = WorkflowNode(kind: .llm, position: WorkflowPoint(x: 0, y: 300))
        let workflow = WorkflowDefinition(
            name: "范围",
            nodes: [input, output, unrelated],
            connections: [WorkflowConnection(sourceNodeID: input.id, sourcePortID: "text", targetNodeID: output.id, targetPortID: "value")]
        )
        let scoped = WorkflowGraphAnalysis.scopedWorkflow(targetNodeID: output.id, in: workflow)
        XCTAssertEqual(Set(scoped.nodes.map(\.id)), Set([input.id, output.id]))
        XCTAssertFalse(scoped.nodes.contains { $0.id == unrelated.id })
    }

    @MainActor
    func testCostEstimateUsesLoopMaximum() {
        var loopConfiguration = WorkflowNodeConfiguration()
        loopConfiguration.maxIterations = 7
        let loop = WorkflowNode(kind: .loop, position: .zero, configuration: loopConfiguration)
        let llm = WorkflowNode(kind: .llm, position: WorkflowPoint(x: 200, y: 0))
        let workflow = WorkflowDefinition(
            name: "费用",
            nodes: [loop, llm],
            connections: [
                WorkflowConnection(sourceNodeID: loop.id, sourcePortID: "iteration", targetNodeID: llm.id, targetPortID: "prompt"),
                WorkflowConnection(sourceNodeID: llm.id, sourcePortID: "text", targetNodeID: loop.id, targetPortID: "feedback"),
            ]
        )
        XCTAssertEqual(WorkflowValidator.estimateCosts(workflow).llmCalls, 7)
    }

    @MainActor
    func testAtomicDefinitionsAndRunHistoryDeletion() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkflowStore(rootURL: root)
        let workflowID = store.addWorkflow(named: "持久化测试")
        store.saveNow()

        let definitions = root.appendingPathComponent("workflows.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: definitions.path))
        let reloaded = WorkflowStore(rootURL: root)
        XCTAssertEqual(reloaded.workflow(id: workflowID)?.name, "持久化测试")
        let rootNames = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(Set(rootNames), Set(["Runs", "workflows.json"]))

        guard let workflow = reloaded.workflow(id: workflowID) else {
            return XCTFail("工作流未重新加载")
        }
        var run = WorkflowRun(
            workflowID: workflowID,
            targetNodeID: nil,
            runtimeInputs: [:],
            nodes: workflow.nodes
        )
        run.status = .succeeded
        run.endedAt = Date()
        reloaded.saveRun(run)
        let runFile = reloaded.runRoot(workflowID: workflowID, runID: run.id).appendingPathComponent("run.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: runFile.path))

        reloaded.deleteRun(workflowID: workflowID, runID: run.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: runFile.path))
        XCTAssertTrue(reloaded.runsByWorkflowID[workflowID]?.isEmpty == true)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeiNiuWorkflowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

final class WorkflowExecutorTests: XCTestCase {
    @MainActor
    func testConditionBranchRunsSeriallyAndSkipsUnselectedOutput() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkflowStore(rootURL: root)
        let recorder = NodeExecutionRecorder()
        let executor = WorkflowExecutor(executionHook: { node in recorder.nodeIDs.append(node.id) })

        var inputConfiguration = WorkflowNodeConfiguration()
        inputConfiguration.text = "通过"
        let input = WorkflowNode(kind: .runtimeInput, position: .zero, configuration: inputConfiguration, createdAt: Date(timeIntervalSince1970: 1))
        var conditionConfiguration = WorkflowNodeConfiguration()
        conditionConfiguration.comparison = .equals
        conditionConfiguration.comparisonValue = "通过"
        let condition = WorkflowNode(kind: .condition, position: WorkflowPoint(x: 200, y: 0), configuration: conditionConfiguration, createdAt: Date(timeIntervalSince1970: 2))
        let accepted = WorkflowNode(kind: .output, position: WorkflowPoint(x: 400, y: 0), createdAt: Date(timeIntervalSince1970: 3))
        let rejected = WorkflowNode(kind: .output, position: WorkflowPoint(x: 400, y: 200), createdAt: Date(timeIntervalSince1970: 4))
        let workflow = WorkflowDefinition(
            name: "条件执行",
            nodes: [rejected, condition, accepted, input],
            connections: [
                WorkflowConnection(sourceNodeID: input.id, sourcePortID: "text", targetNodeID: condition.id, targetPortID: "value"),
                WorkflowConnection(sourceNodeID: condition.id, sourcePortID: "true", targetNodeID: accepted.id, targetPortID: "value"),
                WorkflowConnection(sourceNodeID: condition.id, sourcePortID: "false", targetNodeID: rejected.id, targetPortID: "value"),
            ]
        )

        executor.start(
            workflow: workflow,
            targetNodeID: nil,
            runtimeInputs: [:],
            settings: SettingsStore(),
            knowledge: StubKnowledgeSearch(),
            store: store
        )
        try await waitUntilFinished(executor)

        XCTAssertEqual(store.activeRun?.status, .succeeded)
        XCTAssertEqual(store.activeRun?.nodeRun(id: accepted.id)?.outputs["value"], .text("通过"))
        XCTAssertEqual(store.activeRun?.nodeRun(id: rejected.id)?.status, .skipped)
        XCTAssertEqual(recorder.nodeIDs, [input.id, condition.id, accepted.id])
    }

    @MainActor
    func testLoopStopsAtMaximumAndKeepsLastResult() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkflowStore(rootURL: root)
        let executor = WorkflowExecutor()

        var inputConfiguration = WorkflowNodeConfiguration()
        inputConfiguration.text = "seed"
        let input = WorkflowNode(kind: .runtimeInput, position: .zero, configuration: inputConfiguration)
        var loopConfiguration = WorkflowNodeConfiguration()
        loopConfiguration.comparison = .equals
        loopConfiguration.comparisonValue = "不会命中"
        loopConfiguration.maxIterations = 2
        let loop = WorkflowNode(kind: .loop, position: WorkflowPoint(x: 180, y: 0), configuration: loopConfiguration)
        var templateConfiguration = WorkflowNodeConfiguration()
        templateConfiguration.text = "{{value}}!"
        let template = WorkflowNode(kind: .promptTemplate, position: WorkflowPoint(x: 360, y: 0), configuration: templateConfiguration)
        let output = WorkflowNode(kind: .output, position: WorkflowPoint(x: 540, y: 0))
        let workflow = WorkflowDefinition(
            name: "循环执行",
            nodes: [input, loop, template, output],
            connections: [
                WorkflowConnection(sourceNodeID: input.id, sourcePortID: "text", targetNodeID: loop.id, targetPortID: "seed"),
                WorkflowConnection(sourceNodeID: loop.id, sourcePortID: "iteration", targetNodeID: template.id, targetPortID: "value"),
                WorkflowConnection(sourceNodeID: template.id, sourcePortID: "text", targetNodeID: loop.id, targetPortID: "feedback"),
                WorkflowConnection(sourceNodeID: loop.id, sourcePortID: "completed", targetNodeID: output.id, targetPortID: "value"),
            ]
        )

        executor.start(
            workflow: workflow,
            targetNodeID: nil,
            runtimeInputs: [:],
            settings: SettingsStore(),
            knowledge: StubKnowledgeSearch(),
            store: store
        )
        try await waitUntilFinished(executor)

        XCTAssertEqual(store.activeRun?.status, .warning)
        XCTAssertEqual(store.activeRun?.nodeRun(id: loop.id)?.status, .warning)
        XCTAssertEqual(store.activeRun?.nodeRun(id: loop.id)?.iteration, 2)
        XCTAssertEqual(store.activeRun?.nodeRun(id: output.id)?.outputs["value"], .text("seed!!"))
        XCTAssertTrue(store.activeRun?.warnings.contains { $0.contains("2 次上限") } == true)
    }

    @MainActor
    func testCancellationAndFailurePropagationPreserveTerminalStates() async throws {
        let cancellationRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cancellationRoot) }
        let cancellationStore = WorkflowStore(rootURL: cancellationRoot)
        let slowExecutor = WorkflowExecutor(executionHook: { _ in
            try await Task.sleep(for: .seconds(10))
        })
        let cancelWorkflow = simpleWorkflow()
        slowExecutor.start(
            workflow: cancelWorkflow,
            targetNodeID: nil,
            runtimeInputs: [:],
            settings: SettingsStore(),
            knowledge: StubKnowledgeSearch(),
            store: cancellationStore
        )
        try await Task.sleep(for: .milliseconds(30))
        slowExecutor.cancel()
        try await waitUntilFinished(slowExecutor)
        XCTAssertEqual(cancellationStore.activeRun?.status, .cancelled)
        XCTAssertFalse(cancellationStore.activeRun?.nodeRuns.contains { $0.status == .pending } == true)

        let failureRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: failureRoot) }
        let failureStore = WorkflowStore(rootURL: failureRoot)
        let failureWorkflow = failurePropagationWorkflow()
        let failingNodeID = failureWorkflow.nodes.first { $0.kind == .promptTemplate }!.id
        let pendingOutputID = failureWorkflow.nodes.first { $0.kind == .output }!.id
        let failingExecutor = WorkflowExecutor(executionHook: { node in
            if node.id == failingNodeID { throw ExecutorTestError.expectedFailure }
        })
        failingExecutor.start(
            workflow: failureWorkflow,
            targetNodeID: nil,
            runtimeInputs: [:],
            settings: SettingsStore(),
            knowledge: StubKnowledgeSearch(),
            store: failureStore
        )
        try await waitUntilFinished(failingExecutor)
        XCTAssertEqual(failureStore.activeRun?.status, .failed)
        XCTAssertEqual(failureStore.activeRun?.nodeRun(id: failingNodeID)?.status, .failed)
        XCTAssertEqual(failureStore.activeRun?.nodeRun(id: pendingOutputID)?.status, .skipped)
        XCTAssertFalse(failureStore.activeRun?.nodeRuns.contains { $0.status == .pending } == true)
    }

    @MainActor
    private func simpleWorkflow() -> WorkflowDefinition {
        var configuration = WorkflowNodeConfiguration()
        configuration.text = "测试"
        let input = WorkflowNode(kind: .runtimeInput, position: .zero, configuration: configuration)
        let output = WorkflowNode(kind: .output, position: WorkflowPoint(x: 200, y: 0))
        return WorkflowDefinition(
            name: "简单执行",
            nodes: [input, output],
            connections: [WorkflowConnection(sourceNodeID: input.id, sourcePortID: "text", targetNodeID: output.id, targetPortID: "value")]
        )
    }

    @MainActor
    private func failurePropagationWorkflow() -> WorkflowDefinition {
        var inputConfiguration = WorkflowNodeConfiguration()
        inputConfiguration.text = "测试"
        let input = WorkflowNode(kind: .runtimeInput, position: .zero, configuration: inputConfiguration)
        var templateConfiguration = WorkflowNodeConfiguration()
        templateConfiguration.text = "{{value}}"
        let template = WorkflowNode(kind: .promptTemplate, position: WorkflowPoint(x: 200, y: 0), configuration: templateConfiguration)
        let output = WorkflowNode(kind: .output, position: WorkflowPoint(x: 400, y: 0))
        return WorkflowDefinition(
            name: "失败传播",
            nodes: [input, template, output],
            connections: [
                WorkflowConnection(sourceNodeID: input.id, sourcePortID: "text", targetNodeID: template.id, targetPortID: "value"),
                WorkflowConnection(sourceNodeID: template.id, sourcePortID: "text", targetNodeID: output.id, targetPortID: "value"),
            ]
        )
    }

    @MainActor
    private func waitUntilFinished(_ executor: WorkflowExecutor) async throws {
        for _ in 0..<300 {
            if !executor.isRunning { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("执行器在测试时限内没有结束")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeiNiuExecutorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

final class WorkflowMediaAdapterTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    @MainActor
    func testImageAdapterSavesBase64ArtifactWithoutPaidRequest() async throws {
        let bytes = Data("fake-png".utf8)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/images/generations")
            XCTAssertEqual(request.httpMethod, "POST")
            return (200, ["Content-Type": "application/json"], Data(#"{"data":[{"b64_json":"\#(bytes.base64EncodedString())"}]}"#.utf8))
        }
        let output = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: output) }
        let artifact = try await OpenAIImageGenerationAdapter(session: mockSession()).generate(
            request: ImageGenerationRequest(prompt: "测试", model: "mock", size: "1024x1024"),
            provider: ImageProvider(name: "Mock", baseURL: "https://mock.invalid/v1"),
            apiKey: "test-key",
            outputDirectory: output,
            progress: { _ in }
        )
        XCTAssertEqual(try Data(contentsOf: artifact.fileURL), bytes)
        XCTAssertEqual(artifact.mimeType, "image/png")
    }

    @MainActor
    func testImageAdapterUsesMultipartEditEndpointWithoutPaidRequest() async throws {
        let bytes = Data("edited-png".utf8)
        let output = try temporaryDirectory()
        let reference = output.appendingPathComponent("reference.png")
        let mask = output.appendingPathComponent("mask.png")
        try Data("reference-bytes".utf8).write(to: reference)
        try Data("mask-bytes".utf8).write(to: mask)
        defer { try? FileManager.default.removeItem(at: output) }

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/images/edits")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            let body = String(data: self.requestBody(request), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("name=\"image[]\""))
            XCTAssertTrue(body.contains("name=\"mask\""))
            XCTAssertTrue(body.contains("name=\"prompt\""))
            XCTAssertTrue(body.contains("保留人物，修改背景"))
            return (200, ["Content-Type": "application/json"], Data(#"{"data":[{"b64_json":"\#(bytes.base64EncodedString())"}]}"#.utf8))
        }

        let artifact = try await OpenAIImageGenerationAdapter(session: mockSession()).generate(
            request: ImageGenerationRequest(
                prompt: "保留人物，修改背景",
                model: "mock",
                size: "1024x1024",
                operation: .edit,
                referenceImageURL: reference,
                maskImageURL: mask
            ),
            provider: ImageProvider(name: "Mock", baseURL: "https://mock.invalid/v1"),
            apiKey: "test-key",
            outputDirectory: output,
            progress: { _ in }
        )
        XCTAssertEqual(try Data(contentsOf: artifact.fileURL), bytes)
        XCTAssertTrue(MediaAdapterRegistry.shared.imageDescriptors.first?.supportsImageEditing == true)
        XCTAssertTrue(MediaAdapterRegistry.shared.imageDescriptors.first?.supportsMaskImage == true)
    }

    @MainActor
    func testVideoAdapterDownloadsCompletedArtifactWithoutPaidRequest() async throws {
        let bytes = Data("fake-mp4".utf8)
        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/videos":
                return (200, ["Content-Type": "application/json"], Data(#"{"id":"video_mock","status":"completed","progress":100}"#.utf8))
            case "/v1/videos/video_mock/content":
                return (200, ["Content-Type": "video/mp4"], bytes)
            default:
                return (404, [:], Data())
            }
        }
        let output = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: output) }
        let artifact = try await OpenAIVideoGenerationAdapter(session: mockSession()).generate(
            request: VideoGenerationRequest(prompt: "测试", model: "mock", size: "720x1280", durationSeconds: 4, referenceImageURL: nil),
            provider: VideoProvider(name: "Mock", baseURL: "https://mock.invalid/v1"),
            apiKey: "test-key",
            outputDirectory: output,
            progress: { _ in }
        )
        XCTAssertEqual(try Data(contentsOf: artifact.fileURL), bytes)
        XCTAssertEqual(artifact.remoteJobID, "video_mock")
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeiNiuMediaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, headers, data) = try handler(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)
            else { throw URLError(.badServerResponse) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
private final class StubKnowledgeSearch: WorkflowKnowledgeSearching {
    func search(
        query: String,
        settings: SettingsStore,
        collectionID: UUID?,
        tags: [String],
        limit: Int
    ) async throws -> [KnowledgeSearchResult] {
        []
    }
}

@MainActor
private final class NodeExecutionRecorder {
    var nodeIDs: [UUID] = []
}

private enum ExecutorTestError: LocalizedError {
    case expectedFailure

    var errorDescription: String? { "预期的执行失败" }
}
