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
        XCTAssertFalse(tolerant.isBuiltIn)
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
    func testVersionThreeFolderAudioAndLegacyRuntimeInputsRoundTrip() throws {
        let legacy = try JSONDecoder().decode(
            WorkflowRun.self,
            from: Data(#"{"formatVersion":1,"status":"succeeded","runtimeInputs":{"brief":"旧文本"},"nodeRuns":[]}"#.utf8)
        )
        XCTAssertEqual(legacy.formatVersion, WorkflowRun.currentFormatVersion)
        XCTAssertEqual(legacy.runtimeInputs["brief"], .text("旧文本"))

        let value = WorkflowValue.audio("Assets/voice.wav")
        XCTAssertEqual(try JSONDecoder().decode(WorkflowValue.self, from: JSONEncoder().encode(value)), value)
        let folder = WorkflowValue.folder("Assets/images")
        XCTAssertEqual(try JSONDecoder().decode(WorkflowValue.self, from: JSONEncoder().encode(folder)), folder)
        let collection = WorkflowValue.knowledgeCollection(UUID().uuidString)
        XCTAssertEqual(try JSONDecoder().decode(WorkflowValue.self, from: JSONEncoder().encode(collection)), collection)

        let connection = WorkflowConnection(
            sourceNodeID: UUID(),
            sourcePortID: "audio",
            targetNodeID: UUID(),
            targetPortID: "referenceAudio",
            targetOrder: 2
        )
        let decoded = try JSONDecoder().decode(WorkflowConnection.self, from: JSONEncoder().encode(connection))
        XCTAssertEqual(decoded.targetOrder, 2)
    }

    @MainActor
    func testBuiltInKnowledgeImportWorkflowHasFolderPromptAndOutput() throws {
        let workflow = WorkflowDefinition.knowledgeImport()
        XCTAssertEqual(workflow.id, WorkflowDefinition.knowledgeImportWorkflowID)
        XCTAssertEqual(workflow.name, "添加知识库")
        XCTAssertTrue(workflow.isBuiltIn)
        XCTAssertFalse(WorkflowDefinition.starter().isBuiltIn)
        XCTAssertEqual(workflow.nodes.filter { $0.kind == .runtimeInput }.count, 4)
        XCTAssertTrue(workflow.nodes.contains {
            $0.kind == .runtimeInput && $0.configuration.runtimeInputType == .folder
        })
        let promptNode = try XCTUnwrap(workflow.nodes.first {
            $0.kind == .runtimeInput && $0.configuration.runtimeInputType == .prompt
        })
        XCTAssertEqual(promptNode.configuration.promptCategory, .knowledgeImport)
        XCTAssertEqual(promptNode.configuration.promptSnapshot, DefaultPrompts.knowledgeImportPromptTemplate)
        let collectionNode = try XCTUnwrap(workflow.nodes.first {
            $0.kind == .runtimeInput && $0.configuration.runtimeInputType == .knowledgeCollection
        })
        XCTAssertFalse(collectionNode.configuration.isRequired)
        let importNode = try XCTUnwrap(workflow.nodes.first { $0.kind == .knowledgeImport })
        XCTAssertFalse(importNode.configuration.usesPromptLibrary)
        let ports = importNode.descriptor.ports(for: importNode)
        XCTAssertTrue(ports.contains { $0.id == "folder" && $0.valueType == .folder && $0.isRequired })
        XCTAssertTrue(ports.contains { $0.id == "prompt" && $0.valueType == .text && $0.isRequired })
        XCTAssertTrue(ports.contains { $0.id == "instructions" && $0.valueType == .text && $0.isRequired })
        XCTAssertTrue(ports.contains { $0.id == "collection" && $0.valueType == .knowledgeCollection && $0.isRequired })
        XCTAssertTrue(workflow.connections.contains {
            $0.sourceNodeID == promptNode.id && $0.sourcePortID == "prompt" &&
            $0.targetNodeID == importNode.id && $0.targetPortID == "prompt"
        })
        XCTAssertTrue(workflow.connections.contains {
            $0.sourceNodeID == collectionNode.id && $0.sourcePortID == "knowledgeCollection" &&
            $0.targetNodeID == importNode.id && $0.targetPortID == "collection"
        })
        XCTAssertEqual(workflow.connections.count, 5)
        XCTAssertEqual(WorkflowValidator.estimateCosts(workflow).llmCalls, 50)
    }

    @MainActor
    func testBuiltInWorkflowRejectsEditsAndCreatesEditableCopy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeiNiuBuiltInWorkflow-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkflowStore(rootURL: root)
        let builtInID = WorkflowDefinition.knowledgeImportWorkflowID
        let original = try XCTUnwrap(store.workflow(id: builtInID))

        store.renameWorkflow(id: builtInID, name: "被修改")
        store.mutateWorkflow(id: builtInID) { $0.nodes.removeAll() }
        XCTAssertNil(store.addNode(kind: .llm, to: builtInID, at: .zero))
        store.deleteWorkflow(id: builtInID)

        let unchanged = try XCTUnwrap(store.workflow(id: builtInID))
        XCTAssertEqual(unchanged.name, original.name)
        XCTAssertEqual(unchanged.nodes, original.nodes)
        XCTAssertEqual(store.lastError, "内置工作流不可编辑，请先复制")

        let connectionResult = store.addConnection(
            sourceNodeID: UUID(),
            sourcePortID: "text",
            targetNodeID: UUID(),
            targetPortID: "prompt",
            in: builtInID
        )
        guard case .failure(.readOnlyBuiltIn) = connectionResult else {
            return XCTFail("内置工作流连线应被数据层拒绝")
        }

        let copyID = try XCTUnwrap(store.duplicateWorkflow(id: builtInID))
        let copy = try XCTUnwrap(store.workflow(id: copyID))
        XCTAssertFalse(copy.isBuiltIn)
        XCTAssertNotEqual(copy.id, builtInID)
        XCTAssertEqual(copy.nodes.count, original.nodes.count)

        store.renameWorkflow(id: copyID, name: "我的知识入库")
        XCTAssertEqual(store.workflow(id: copyID)?.name, "我的知识入库")
    }

    @MainActor
    func testGlobalDefaultLLMResolvesForBuiltInWorkflowAndBackup() throws {
        let provider = LLMProvider(
            name: "默认视觉服务",
            protocolType: .openAICompatible,
            models: ["vision-model"],
            supportsVision: true
        )
        let settings = SettingsStore()
        settings.providers = [provider]
        settings.defaultLLMProviderID = provider.id
        settings.defaultLLMModel = "vision-model"

        XCTAssertEqual(settings.effectiveLLMProvider(for: nil)?.id, provider.id)
        XCTAssertEqual(settings.effectiveLLMModel(providerID: nil, model: ""), "vision-model")
        XCTAssertNil(settings.effectiveLLMProvider(for: UUID()))
        XCTAssertEqual(settings.effectiveLLMModel(providerID: provider.id, model: ""), "")

        let workflow = WorkflowDefinition.knowledgeImport()
        let issues = WorkflowValidator.validate(workflow, settings: settings)
        XCTAssertFalse(issues.contains { $0.message.contains("默认大模型") })
        XCTAssertFalse(issues.contains { $0.message.contains("未开启视觉能力") })

        let backup = SettingsBackup(
            includeAPIKeys: false,
            providers: [provider],
            defaultLLMProviderID: provider.id,
            defaultLLMModel: "vision-model",
            promptItems: [],
            imageProviders: [],
            videoProviders: []
        )
        let decoded = try JSONDecoder().decode(
            SettingsBackup.self,
            from: JSONEncoder().encode(backup)
        )
        XCTAssertEqual(decoded.defaultLLMProviderID, provider.id)
        XCTAssertEqual(decoded.defaultLLMModel, "vision-model")
        XCTAssertEqual(decoded.formatVersion, SettingsBackup.currentFormatVersion)
    }

    @MainActor
    func testKnowledgeImportPromptCategoryAndDefaultTemplate() throws {
        XCTAssertEqual(PromptCategory.knowledgeImport.displayName, "知识库添加")
        XCTAssertEqual(PromptCategory.knowledgeImport.suggestedVariables, ["filename", "requirements"])

        let productPrompt = try XCTUnwrap(
            DefaultPrompts.seedItems().first {
                $0.category == .knowledgeImport && $0.name == DefaultPrompts.productKnowledgeImportPromptName
            }
        )
        let vehiclePrompt = try XCTUnwrap(
            DefaultPrompts.seedItems().first {
                $0.category == .knowledgeImport && $0.name == DefaultPrompts.vehicleKnowledgeImportPromptName
            }
        )
        XCTAssertEqual(
            DefaultPrompts.seedItems().filter { $0.category == .knowledgeImport }.count,
            2
        )
        XCTAssertTrue(productPrompt.isBuiltIn)
        XCTAssertTrue(productPrompt.template.contains("{{filename}}"))
        XCTAssertTrue(productPrompt.template.contains("{{requirements}}"))
        XCTAssertTrue(productPrompt.template.contains("普通产品知识库资料整理员"))
        XCTAssertTrue(vehiclePrompt.isBuiltIn)
        XCTAssertTrue(vehiclePrompt.template.contains("{{filename}}"))
        XCTAssertTrue(vehiclePrompt.template.contains("{{requirements}}"))
        XCTAssertTrue(vehiclePrompt.template.contains("汽车知识库资料整理员"))
        XCTAssertTrue(DefaultPrompts.blankTemplate(for: .knowledgeImport).contains("{{filename}}"))

        let settings = SettingsStore()
        settings.promptItems = [
            PromptItem(
                category: .knowledgeImport,
                name: DefaultPrompts.knowledgeImportPromptName,
                template: "最新版：{{filename}} / {{requirements}}"
            ),
        ]
        var promptNode = try XCTUnwrap(
            WorkflowDefinition.knowledgeImport().nodes.first {
                $0.kind == .runtimeInput && $0.configuration.runtimeInputType == .prompt
            }
        )
        let resolved = WorkflowValidator.resolvedRuntimePrompt(for: promptNode, settings: settings)
        XCTAssertEqual(resolved.template, "最新版：{{filename}} / {{requirements}}")
        XCTAssertFalse(resolved.usedSnapshot)

        let runtimePrompt = PromptItem(
            category: .knowledgeImport,
            name: "本次人物服装提取",
            template: "只整理人物服装：{{filename}} / {{requirements}}"
        )
        settings.promptItems.append(runtimePrompt)
        promptNode.configuration.promptItemID = runtimePrompt.id
        promptNode.configuration.promptSnapshot = runtimePrompt.template
        let runtimeResolved = WorkflowValidator.resolvedRuntimePrompt(for: promptNode, settings: settings)
        XCTAssertEqual(runtimeResolved.template, runtimePrompt.template)
        XCTAssertFalse(runtimeResolved.usedSnapshot)

        settings.promptItems.removeAll { $0.id == runtimePrompt.id }
        let snapshotResolved = WorkflowValidator.resolvedRuntimePrompt(for: promptNode, settings: settings)
        XCTAssertEqual(snapshotResolved.template, runtimePrompt.template)
        XCTAssertTrue(snapshotResolved.usedSnapshot)
    }

    @MainActor
    func testVisionMessagesUseProviderSpecificImagePayloads() throws {
        let bytes = Data([0x01, 0x02, 0x03])
        let image = LLMImageAttachment(data: bytes, mediaType: "image/jpeg")
        let message = LLMChatMessage(role: .user, content: "整理图片", images: [image])

        let chat = OpenAICompatibleClient.chatMessagePayload(message)
        let chatBlocks = try XCTUnwrap(chat["content"] as? [[String: Any]])
        XCTAssertEqual(chatBlocks.first?["type"] as? String, "text")
        let chatImage = try XCTUnwrap(chatBlocks.last?["image_url"] as? [String: Any])
        XCTAssertEqual(chatImage["url"] as? String, "data:image/jpeg;base64,AQID")

        let responses = OpenAICompatibleClient.responsesMessagePayload(message)
        let responseBlocks = try XCTUnwrap(responses["content"] as? [[String: Any]])
        XCTAssertEqual(responseBlocks.last?["type"] as? String, "input_image")
        XCTAssertEqual(responseBlocks.last?["image_url"] as? String, "data:image/jpeg;base64,AQID")

        let anthropic = AnthropicClient.messagePayload(message)
        let anthropicBlocks = try XCTUnwrap(anthropic["content"] as? [[String: Any]])
        let source = try XCTUnwrap(anthropicBlocks.first?["source"] as? [String: Any])
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, "AQID")
    }

    @MainActor
    func testPixmaxMultimediaPortsExposeOrderedConnectionLimits() throws {
        let video = WorkflowNode(kind: .videoGeneration, position: .zero)
        let ports = video.descriptor.ports(for: video)
        XCTAssertEqual(ports.first { $0.id == "referenceImage" }?.maxConnections, 9)
        XCTAssertEqual(ports.first { $0.id == "referenceVideo" }?.maxConnections, 3)
        XCTAssertEqual(ports.first { $0.id == "referenceAudio" }?.maxConnections, 3)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeiNiuConnectionLimits-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkflowStore(rootURL: root)
        let workflowID = store.addWorkflow(named: "多参考")
        let videoID = try XCTUnwrap(store.addNode(kind: .videoGeneration, to: workflowID, at: .zero))
        var sourceIDs: [UUID] = []
        for index in 0..<10 {
            let id = try XCTUnwrap(store.addNode(
                kind: .runtimeInput,
                to: workflowID,
                at: WorkflowPoint(x: Double(index), y: 0)
            ))
            var node = try XCTUnwrap(store.workflow(id: workflowID)?.nodes.first { $0.id == id })
            node.configuration.runtimeInputType = .image
            store.updateNode(node, in: workflowID)
            sourceIDs.append(id)
        }
        for (index, sourceID) in sourceIDs.enumerated() {
            let result = store.addConnection(
                sourceNodeID: sourceID,
                sourcePortID: "image",
                targetNodeID: videoID,
                targetPortID: "referenceImage",
                in: workflowID
            )
            if index < 9 {
                guard case .success = result else { return XCTFail("第 \(index + 1) 条参考图连接应成功") }
            } else {
                guard case .failure = result else { return XCTFail("第 10 条参考图连接应被拒绝") }
            }
        }
        let orders = store.workflow(id: workflowID)?.connections
            .filter { $0.targetNodeID == videoID && $0.targetPortID == "referenceImage" }
            .map(\.targetOrder)
        XCTAssertEqual(orders, Array(0..<9))
        store.saveNow()
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

        let legacyPixmax = VideoProvider(
            name: "旧 PixMax",
            kind: .pixmax,
            baseURL: "https://app.pixmax.ai"
        )
        XCTAssertEqual(legacyPixmax.effectiveBaseURL, "https://console.pixmax.ai")
        XCTAssertEqual(PixmaxSite.international.baseURL, "https://console.pixmax.ai")
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

        let chargedKinds: Set<WorkflowNodeKind> = [.knowledgeSearch, .knowledgeImport, .llm, .imageGeneration, .videoGeneration, .loop]
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
        let definitionsObject = try JSONSerialization.jsonObject(with: Data(contentsOf: definitions)) as? [String: Any]
        XCTAssertEqual(definitionsObject?["formatVersion"] as? Int, 3)
        let reloaded = WorkflowStore(rootURL: root)
        XCTAssertEqual(reloaded.workflow(id: workflowID)?.name, "持久化测试")
        XCTAssertNotNil(reloaded.workflow(id: WorkflowDefinition.knowledgeImportWorkflowID))
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
        let runObject = try JSONSerialization.jsonObject(with: Data(contentsOf: runFile)) as? [String: Any]
        XCTAssertEqual(runObject?["formatVersion"] as? Int, WorkflowRun.currentFormatVersion)

        reloaded.deleteRun(workflowID: workflowID, runID: run.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: runFile.path))
        XCTAssertTrue(reloaded.runsByWorkflowID[workflowID]?.isEmpty == true)
    }

    @MainActor
    func testLegacyKnowledgeImportAddsExplicitPromptInputAndKeepsConfiguration() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkflowStore(rootURL: root)
        let workflow = try XCTUnwrap(store.workflow(id: WorkflowDefinition.knowledgeImportWorkflowID))
        var importNode = try XCTUnwrap(
            store.workflow(id: WorkflowDefinition.knowledgeImportWorkflowID)?.nodes.first {
                $0.kind == .knowledgeImport
            }
        )
        let oldPromptID = UUID()
        let oldCollectionID = UUID()
        importNode.configuration.usesPromptLibrary = true
        importNode.configuration.promptItemID = oldPromptID
        importNode.configuration.promptSnapshot = "保留旧版提示词"
        importNode.configuration.collectionID = oldCollectionID
        importNode.configuration.systemPrompt = "保留我的补充要求"
        importNode.configuration.model = "vision-model"
        var legacyWorkflow = workflow
        legacyWorkflow.isBuiltIn = false
        legacyWorkflow.nodes.removeAll {
            $0.kind == .runtimeInput &&
            ($0.configuration.runtimeInputType == .prompt ||
             $0.configuration.runtimeInputType == .knowledgeCollection)
        }
        legacyWorkflow.connections.removeAll {
            $0.targetNodeID == importNode.id &&
            ($0.targetPortID == "prompt" || $0.targetPortID == "collection")
        }
        if let index = legacyWorkflow.nodes.firstIndex(where: { $0.id == importNode.id }) {
            legacyWorkflow.nodes[index] = importNode
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedWorkflow = try encoder.encode(legacyWorkflow)
        let workflowObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedWorkflow) as? [String: Any]
        )
        let legacyFile = try JSONSerialization.data(
            withJSONObject: ["formatVersion": 3, "workflows": [workflowObject]],
            options: [.prettyPrinted, .sortedKeys]
        )
        try legacyFile.write(
            to: root.appendingPathComponent("workflows.json"),
            options: .atomic
        )

        let reloaded = WorkflowStore(rootURL: root)
        let upgradedWorkflow = try XCTUnwrap(reloaded.workflow(id: WorkflowDefinition.knowledgeImportWorkflowID))
        XCTAssertTrue(upgradedWorkflow.isBuiltIn)
        let upgraded = try XCTUnwrap(
            upgradedWorkflow.nodes.first {
                $0.kind == .knowledgeImport
            }
        )
        let promptInput = try XCTUnwrap(upgradedWorkflow.nodes.first {
            $0.kind == .runtimeInput && $0.configuration.runtimeInputType == .prompt
        })
        XCTAssertEqual(promptInput.configuration.promptCategory, .knowledgeImport)
        XCTAssertEqual(promptInput.configuration.promptItemID, oldPromptID)
        XCTAssertEqual(promptInput.configuration.promptSnapshot, "保留旧版提示词")
        XCTAssertTrue(upgradedWorkflow.connections.contains {
            $0.sourceNodeID == promptInput.id && $0.sourcePortID == "prompt" &&
            $0.targetNodeID == upgraded.id && $0.targetPortID == "prompt"
        })
        let collectionInput = try XCTUnwrap(upgradedWorkflow.nodes.first {
            $0.kind == .runtimeInput && $0.configuration.runtimeInputType == .knowledgeCollection
        })
        XCTAssertEqual(collectionInput.configuration.collectionID, oldCollectionID)
        XCTAssertTrue(upgradedWorkflow.connections.contains {
            $0.sourceNodeID == collectionInput.id && $0.sourcePortID == "knowledgeCollection" &&
            $0.targetNodeID == upgraded.id && $0.targetPortID == "collection"
        })
        XCTAssertFalse(upgraded.configuration.usesPromptLibrary)
        XCTAssertNil(upgraded.configuration.promptItemID)
        XCTAssertTrue(upgraded.configuration.promptSnapshot.isEmpty)
        XCTAssertNil(upgraded.configuration.collectionID)
        XCTAssertEqual(upgraded.configuration.systemPrompt, "保留我的补充要求")
        XCTAssertEqual(upgraded.configuration.model, "vision-model")
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
    func testFolderRuntimeInputCopiesDirectoryIntoRunAssets() async throws {
        let root = try temporaryDirectory()
        let source = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        try Data("image-bytes".utf8).write(to: source.appendingPathComponent("frame.jpg"))
        let store = WorkflowStore(rootURL: root)
        let executor = WorkflowExecutor()

        var configuration = WorkflowNodeConfiguration()
        configuration.parameterName = "图片文件夹"
        configuration.runtimeInputType = .folder
        let input = WorkflowNode(kind: .runtimeInput, position: .zero, configuration: configuration)
        let output = WorkflowNode(kind: .output, position: WorkflowPoint(x: 200, y: 0))
        let workflow = WorkflowDefinition(
            name: "文件夹输入",
            nodes: [input, output],
            connections: [
                WorkflowConnection(sourceNodeID: input.id, sourcePortID: "folder", targetNodeID: output.id, targetPortID: "value"),
            ]
        )

        executor.start(
            workflow: workflow,
            targetNodeID: nil,
            runtimeInputs: [input.id.uuidString: .folder(source.path)],
            settings: SettingsStore(),
            knowledge: StubKnowledgeSearch(),
            store: store
        )
        try await waitUntilFinished(executor)

        XCTAssertEqual(store.activeRun?.status, .succeeded)
        let value = try XCTUnwrap(store.activeRun?.nodeRun(id: output.id)?.outputs["value"])
        guard case .folder = value else { return XCTFail("结果应保留文件夹类型") }
        let run = try XCTUnwrap(store.activeRun)
        let copied = try XCTUnwrap(store.artifactURL(for: value, run: run))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.appendingPathComponent("frame.jpg").path))
    }

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

final class PixmaxNativeTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    @MainActor
    func testDomainAllowlistRSAAndLoginPaths() async throws {
        XCTAssertNoThrow(try PixmaxAPIClient.validatedBaseURL("https://console.pixmax.ai"))
        XCTAssertNoThrow(try PixmaxAPIClient.validatedBaseURL("https://team.console.pixmax.cn/ignored"))
        XCTAssertThrowsError(try PixmaxAPIClient.validatedBaseURL("http://console.pixmax.ai"))
        XCTAssertThrowsError(try PixmaxAPIClient.validatedBaseURL("https://pixmax.ai.evil.example"))

        let encrypted = try PixmaxAuthenticator.encryptPassword("secret-password")
        XCTAssertNotEqual(encrypted, "secret-password")
        XCTAssertEqual(Data(base64Encoded: encrypted)?.count, 128)

        var paths: [String] = []
        var encryptedPasswords: [String] = []
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            paths.append(path)
            if let body = try? JSONSerialization.jsonObject(with: requestPayload(request)) as? [String: Any],
               let password = body["password"] as? String {
                encryptedPasswords.append(password)
                XCTAssertFalse(password.contains("secret-password"))
            }
            switch path {
            case "/user/api/user/password/login", "/user/api/sub-user/login":
                return (200, ["Content-Type": "application/json", "Set-Cookie": "pixmax_session=verified; Path=/; HttpOnly"], Data(#"{"success":true}"#.utf8))
            case "/user/api/sub-user/mainUserInfo":
                return (200, ["Content-Type": "application/json"], Data(#"{"success":true,"data":{"enterpriseFlag":true}}"#.utf8))
            case "/user/api/user/info":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "pixmax_session=verified")
                return (200, ["Content-Type": "application/json"], Data(#"{"success":true,"data":{"userUuid":"user-1","email":"tester@example.com"}}"#.utf8))
            default:
                return (404, [:], Data())
            }
        }

        let authenticator = PixmaxAuthenticator(session: mockPixmaxSession())
        let personal = try await authenticator.personalLogin(
            site: .international,
            account: "tester@example.com",
            password: "secret-password"
        )
        XCTAssertEqual(personal.cookie, "pixmax_session=verified")
        XCTAssertEqual(personal.identity.stableID, "user-1")

        let teamUUID = "12345678-1234-1234-1234-123456789abc"
        _ = try await authenticator.teamLogin(
            baseURL: PixmaxSite.international.baseURL,
            teamLinkOrUUID: "https://console.pixmax.ai/team/\(teamUUID)",
            account: "sub-account",
            password: "secret-password"
        )
        XCTAssertTrue(paths.contains("/user/api/sub-user/mainUserInfo"))
        XCTAssertTrue(paths.contains("/user/api/sub-user/login"))
        XCTAssertEqual(encryptedPasswords.count, 2)
    }

    @MainActor
    func testTeamLoginExplainsUnknownMainUser() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/user/api/sub-user/mainUserInfo")
            return (
                200,
                ["Content-Type": "application/json"],
                Data(#"{"success":false,"errCode":"User.NotFound","errMessage":"User not found"}"#.utf8)
            )
        }

        do {
            _ = try await PixmaxAuthenticator(session: mockPixmaxSession()).teamLogin(
                baseURL: PixmaxSite.china.baseURL,
                teamLinkOrUUID: "12345678-1234-1234-1234-123456789abc",
                account: "sub-account",
                password: "secret-password"
            )
            XCTFail("无效 mainUserUuid 应被拒绝")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("团队链接或 mainUserUuid 不正确"))
        }
    }

    @MainActor
    func testTeamIdentityPrefersSubUserAndMasksAccount() throws {
        let response: [String: Any] = [
            "data": [
                "userUuid": "main-user",
                "phone": "15000008888",
                "subUser": [
                    "subUserUuid": "sub-user",
                    "subUserAccount": "18000006666",
                ],
            ],
        ]
        let identity = try PixmaxAPIClient.identity(from: response)
        XCTAssertEqual(identity.stableID, "sub-user")
        XCTAssertEqual(identity.summary, "180****6666")
    }

    @MainActor
    func testTeamOverviewUsesSubAccountQuotaAndRecentConsumptions() async throws {
        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/user/api/credit/balance":
                XCTAssertEqual(request.httpMethod, "GET")
                return (200, ["Content-Type": "application/json"], Data(#"{"success":true,"data":{"totalBalance":99999,"availableQuota":4321.5,"quotaMode":"FIXED","userTier":"TEAM"}}"#.utf8))
            case "/user/api/credit/consumptions":
                XCTAssertEqual(request.httpMethod, "POST")
                let payload = try? JSONSerialization.jsonObject(with: requestPayload(request)) as? [String: Any]
                XCTAssertEqual(payload?["pageIndex"] as? Int, 1)
                XCTAssertEqual(payload?["pageSize"] as? Int, 8)
                return (200, ["Content-Type": "application/json"], Data(#"{"success":true,"data":[{"taskUuid":"task-1","modelName":"Seedance 2.0","createTime":"1784678400000","status":"COMPLETED","totalCost":88}]}"#.utf8))
            default:
                return (404, [:], Data())
            }
        }

        let client = try PixmaxAPIClient(
            baseURL: PixmaxSite.china.baseURL,
            cookie: "session=team",
            session: mockPixmaxSession()
        )
        let overview = try await client.accountOverview()
        XCTAssertEqual(overview.credit.displayValue(isTeamAccount: true), "4,321.5")
        XCTAssertEqual(overview.credit.displayValue(isTeamAccount: false), "99,999")
        XCTAssertEqual(overview.recentGenerations.first?.taskUUID, "task-1")
        XCTAssertEqual(overview.recentGenerations.first?.statusTitle, "已完成")
        XCTAssertEqual(overview.recentGenerations.first?.creditCostTitle, "88")
    }

    @MainActor
    func testCookieImportRequiresUserInfoAndInvalidationPromptsOnce() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/user/api/user/info")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=manual")
            return (200, ["Content-Type": "application/json"], Data(#"{"success":true,"data":{"uuid":"cookie-user","nickname":"Cookie User"}}"#.utf8))
        }
        let result = try await PixmaxAuthenticator(session: mockPixmaxSession()).importCookie(
            baseURL: PixmaxSite.international.baseURL,
            cookie: "session=manual"
        )
        XCTAssertEqual(result.identity.summary, "Cookie User")

        let manager = PixmaxSessionManager(session: mockPixmaxSession(), heartbeatInterval: .milliseconds(5))
        let providerID = UUID()
        manager.reportAuthenticationFailure(providerID: providerID)
        XCTAssertEqual(manager.loginPresentation?.providerID, providerID)
        manager.dismissLogin(providerID: providerID)
        manager.reportAuthenticationFailure(providerID: providerID)
        XCTAssertNil(manager.loginPresentation, "同一失效周期不应重复自动弹框")
        manager.requestLogin(providerID: providerID)
        XCTAssertEqual(manager.loginPresentation?.providerID, providerID, "手动登录仍可重新打开")
        manager.dismissLogin(providerID: providerID)
    }

    @MainActor
    func testPixmaxAdapterReusesRemoteAssetBuildsMentionAndDownloads() async throws {
        let output = try pixmaxTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: output) }
        let audio = output.appendingPathComponent("voice.mp3")
        try Data("fake-audio".utf8).write(to: audio)
        let videoBytes = Data("pixmax-video".utf8)
        var capturedPrompt = ""
        var authorizeCalls = 0
        var revision = 1

        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            switch path {
            case "/user/api/user/info":
                return (200, ["Content-Type": "application/json"], Data(#"{"success":true,"data":{"uuid":"u1","email":"u@example.com"}}"#.utf8))
            case "/user/api/canvas/get":
                return (200, ["Content-Type": "application/json"], Data(#"{"success":true,"data":{"revision":"r0"}}"#.utf8))
            case "/user/api/assets/check":
                return (200, ["Content-Type": "application/json"], Data(#"{"success":true,"data":{"assetsUuid":"asset-audio","webUrl":"/voice.mp3","ossDomain":"https://cdn.invalid","complianceStatus":"ACTIVE"}}"#.utf8))
            case "/user/api/assets/oss/authorize":
                authorizeCalls += 1
                return (500, [:], Data())
            case "/user/api/assetLibrary/compliance/check":
                return (200, ["Content-Type": "application/json"], Data(#"{"success":true,"data":{"assetsUuid":"asset-audio","complianceStatus":"ACTIVE","webUrl":"/voice.mp3","ossDomain":"https://cdn.invalid"}}"#.utf8))
            case "/user/api/canvas/node/batch":
                if let payload = try? JSONSerialization.jsonObject(with: requestPayload(request)) as? [String: Any],
                   let creates = payload["create"] as? [[String: Any]],
                   let generation = creates.first,
                   generation["type"] as? String == "GENERATE_VIDEO",
                   let params = generation["params"] as? [String: Any] {
                    capturedPrompt = params["prompt"] as? String ?? ""
                    XCTAssertEqual(params["count"] as? String, "1")
                    XCTAssertEqual(params["referModel"] as? String, "referToVideo")
                }
                revision += 1
                return (200, ["Content-Type": "application/json"], Data("{\"success\":true,\"data\":{\"revision\":\"r\(revision)\"}}".utf8))
            case "/user/api/generate/batch":
                return (200, ["Content-Type": "application/json"], Data(#"{"success":true}"#.utf8))
            case "/user/api/generate/progress":
                let body = try? JSONSerialization.jsonObject(with: requestPayload(request)) as? [String: Any]
                let uuid = (body?["nodeUuids"] as? [String])?.first ?? ""
                return (200, ["Content-Type": "application/json"], Data("{\"success\":true,\"data\":[{\"nodeUuid\":\"\(uuid)\",\"status\":\"COMPLETE\",\"resultAssets\":[{\"assetsUuid\":\"result-1\",\"webUrl\":\"https://cdn.invalid/result.mp4\"}]}]}".utf8))
            case "/result.mp4":
                return (200, ["Content-Type": "video/mp4"], videoBytes)
            default:
                return (404, [:], Data())
            }
        }

        let provider = pixmaxProvider()
        let artifact = try await PixmaxVideoGenerationAdapter(session: mockPixmaxSession()).generate(
            request: VideoGenerationRequest(
                prompt: "让音频1驱动画面",
                model: "PIXDANCE_2_FAST",
                aspectRatio: "16:9",
                resolution: "720P",
                durationSeconds: 5,
                includeAudio: true,
                referenceAudioURLs: [audio]
            ),
            provider: provider,
            apiKey: "session=valid",
            outputDirectory: output,
            progress: { _ in }
        )
        XCTAssertEqual(try Data(contentsOf: artifact.fileURL), videoBytes)
        XCTAssertEqual(authorizeCalls, 0, "远端哈希命中后不应再次申请 OSS 上传")
        XCTAssertTrue(capturedPrompt.contains("%%@[voice.mp3][audio][0]("))
        XCTAssertFalse(capturedPrompt.contains("音频1"))
    }

    @MainActor
    func testPixmaxAdapterUsesNativeOSSSignatureWithoutBrowserFallback() async throws {
        let output = try pixmaxTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: output) }
        let audio = output.appendingPathComponent("upload.mp3")
        try Data("upload-audio".utf8).write(to: audio)
        let videoBytes = Data("uploaded-result".utf8)
        var sawSignedPut = false
        var revision = 0

        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "HEAD" {
                return (200, ["Date": "Wed, 22 Jul 2026 00:00:00 GMT"], Data())
            }
            if request.httpMethod == "PUT" {
                sawSignedPut = request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("OSS AKID:") == true &&
                    request.value(forHTTPHeaderField: "x-oss-security-token") == "TOKEN" &&
                    request.value(forHTTPHeaderField: "x-oss-callback") != nil
                return (200, [:], Data())
            }
            switch path {
            case "/user/api/user/info":
                return (200, ["Content-Type": "application/json"], Data(#"{"success":true,"data":{"uuid":"u1","email":"u@example.com"}}"#.utf8))
            case "/user/api/canvas/get":
                return (200, ["Content-Type": "application/json"], Data(#"{"success":true,"data":{"revision":"r0"}}"#.utf8))
            case "/user/api/assets/check":
                return (200, ["Content-Type": "application/json"], Data(#"{"success":false,"errCode":"Common.NotFound"}"#.utf8))
            case "/user/api/assets/oss/authorize":
                let json = #"{"success":true,"data":{"sessionId":"oss-session","objectKey":"folder/upload.mp3","bucketName":"bucket","endpoint":"oss.invalid","contentType":"audio/mpeg","accessKeyId":"AKID","accessKeySecret":"SECRET","securityToken":"TOKEN","callbackUrl":"https://callback.invalid","callbackBody":"asset=${object}","callbackBodyType":"application/x-www-form-urlencoded"}}"#
                return (200, ["Content-Type": "application/json"], Data(json.utf8))
            case "/user/api/assets/oss/check":
                let json = #"{"success":true,"data":{"status":"COMPLETED","asset":{"assetsUuid":"uploaded-audio","webUrl":"/upload.mp3","ossDomain":"https://cdn.invalid","complianceStatus":"ACTIVE"}}}"#
                return (200, ["Content-Type": "application/json"], Data(json.utf8))
            case "/user/api/assetLibrary/compliance/check":
                return (200, ["Content-Type": "application/json"], Data(#"{"success":true,"data":{"assetsUuid":"uploaded-audio","complianceStatus":"ACTIVE","webUrl":"/upload.mp3","ossDomain":"https://cdn.invalid"}}"#.utf8))
            case "/user/api/canvas/node/batch":
                revision += 1
                return (200, ["Content-Type": "application/json"], Data("{\"success\":true,\"data\":{\"revision\":\"r\(revision)\"}}".utf8))
            case "/user/api/generate/batch":
                return (200, ["Content-Type": "application/json"], Data(#"{"success":true}"#.utf8))
            case "/user/api/generate/progress":
                let body = try? JSONSerialization.jsonObject(with: requestPayload(request)) as? [String: Any]
                let uuid = (body?["nodeUuids"] as? [String])?.first ?? ""
                return (200, ["Content-Type": "application/json"], Data("{\"success\":true,\"data\":[{\"nodeUuid\":\"\(uuid)\",\"status\":\"COMPLETE\",\"resultAssets\":[{\"assetsUuid\":\"result-1\",\"webUrl\":\"https://cdn.invalid/uploaded.mp4\"}]}]}".utf8))
            case "/uploaded.mp4":
                return (200, ["Content-Type": "video/mp4"], videoBytes)
            default:
                return (404, [:], Data())
            }
        }

        let artifact = try await PixmaxVideoGenerationAdapter(session: mockPixmaxSession()).generate(
            request: VideoGenerationRequest(
                prompt: "使用音频1",
                model: "PIXDANCE_2_FAST",
                aspectRatio: "16:9",
                resolution: "720P",
                durationSeconds: 5,
                includeAudio: false,
                referenceAudioURLs: [audio]
            ),
            provider: pixmaxProvider(),
            apiKey: "session=valid",
            outputDirectory: output,
            progress: { _ in }
        )
        XCTAssertTrue(sawSignedPut)
        XCTAssertEqual(try Data(contentsOf: artifact.fileURL), videoBytes)
    }

    @MainActor
    func testPixmaxRejectsUnsupportedMediaCombinationBeforeNetwork() async throws {
        let output = try pixmaxTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: output) }
        let audio = output.appendingPathComponent("voice.wav")
        try Data("audio".utf8).write(to: audio)
        MockURLProtocol.handler = { _ in
            XCTFail("不支持的组合不应发起网络请求")
            return (500, [:], Data())
        }
        do {
            _ = try await PixmaxVideoGenerationAdapter(session: mockPixmaxSession()).generate(
                request: VideoGenerationRequest(
                    prompt: "测试",
                    model: "SEEDANCE_1_5",
                    aspectRatio: "16:9",
                    resolution: "720P",
                    durationSeconds: 5,
                    includeAudio: false,
                    referenceAudioURLs: [audio]
                ),
                provider: pixmaxProvider(),
                apiKey: "session=valid",
                outputDirectory: output,
                progress: { _ in }
            )
            XCTFail("应拒绝不支持的音频参考")
        } catch let error as PixmaxError {
            XCTAssertTrue(error.localizedDescription.contains("不支持当前视频或音频参考组合"))
        }
    }

    @MainActor
    private func pixmaxProvider() -> VideoProvider {
        VideoProvider(
            name: "PixMax Mock",
            kind: .pixmax,
            adapterSettings: [
                "enabled": "true",
                "workspaceUUID": "workspace-1",
                "fileUUID": "file-1",
                "submissionInterval": "0",
            ]
        )
    }

    private func pixmaxTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeiNiuPixmaxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private func mockPixmaxSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func requestPayload(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
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
private final class StubKnowledgeSearch: WorkflowKnowledgeAccessing {
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
