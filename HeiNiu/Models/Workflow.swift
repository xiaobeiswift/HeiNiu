/// 节点式工作流的数据模型、端口定义与内置帮助。
///
/// 工作流定义与运行结果分开持久化；API Key 只通过 ``SettingsStore``
/// 从钥匙串读取，不会进入这些模型。

import Foundation

/// 可在画布中添加的节点类型。
enum WorkflowNodeKind: Hashable, Codable, Identifiable {
    case runtimeInput
    case promptTemplate
    case knowledgeSearch
    case llm
    case imageGeneration
    case videoGeneration
    case condition
    case loop
    case output
    case unsupported(String)

    /// 节点目录中的稳定顺序。
    static let catalog: [WorkflowNodeKind] = [
        .runtimeInput, .promptTemplate, .knowledgeSearch, .llm,
        .imageGeneration, .videoGeneration, .condition, .loop, .output,
    ]

    /// 持久化使用的稳定标识符。
    var id: String {
        switch self {
        case .runtimeInput: "runtimeInput"
        case .promptTemplate: "promptTemplate"
        case .knowledgeSearch: "knowledgeSearch"
        case .llm: "llm"
        case .imageGeneration: "imageGeneration"
        case .videoGeneration: "videoGeneration"
        case .condition: "condition"
        case .loop: "loop"
        case .output: "output"
        case .unsupported(let raw): raw
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "runtimeInput": self = .runtimeInput
        case "promptTemplate": self = .promptTemplate
        case "knowledgeSearch": self = .knowledgeSearch
        case "llm": self = .llm
        case "imageGeneration": self = .imageGeneration
        case "videoGeneration": self = .videoGeneration
        case "condition": self = .condition
        case "loop": self = .loop
        case "output": self = .output
        default: self = .unsupported(raw)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}

/// 工作流端口传递的数据类型。
enum WorkflowValueType: String, Codable, Hashable {
    case text
    case image
    case video
    case any

    /// 中文显示名称。
    var title: String {
        switch self {
        case .text: "文本"
        case .image: "图片"
        case .video: "视频"
        case .any: "任意结果"
        }
    }

    /// 判断源端口能否连接目标端口。
    func canConnect(to target: WorkflowValueType) -> Bool {
        self == target || self == .any || target == .any
    }
}

/// 节点端口方向。
enum WorkflowPortDirection: String, Codable, Hashable {
    case input
    case output
}

/// 节点输入或输出端口描述。
struct WorkflowPortDescriptor: Identifiable, Hashable {
    var id: String
    var title: String
    var direction: WorkflowPortDirection
    var valueType: WorkflowValueType
    var isRequired: Bool
    var help: String
}

/// 节点完整中文操作指南。
struct NodeUsageGuide: Hashable {
    var purpose: String
    var setupSteps: [String]
    var connectionExample: String
    var resultDescription: String
    var commonErrors: [String]
    var warnings: [String]
}

/// 单类节点的统一元数据。
struct WorkflowNodeDescriptor: Identifiable, Hashable {
    var id: String { kind.id }
    var kind: WorkflowNodeKind
    var title: String
    var summary: String
    var systemImage: String
    var tint: WorkflowNodeTint
    var usage: NodeUsageGuide

    /// 返回节点的实际端口；提示词节点会根据模板变量动态生成输入端口。
    func ports(for node: WorkflowNode) -> [WorkflowPortDescriptor] {
        switch kind {
        case .runtimeInput:
            return [Self.output("text", "文本", .text, "本次运行填写的文本参数。")]
        case .promptTemplate:
            let names = node.configuration.templateVariables
            let inputs = names.map {
                Self.input($0, "{{\($0)}}", .text, true, "替换模板中的 {{\($0)}} 变量。")
            }
            return inputs + [Self.output("text", "模板文本", .text, "全部变量替换后的完整提示词。")]
        case .knowledgeSearch:
            return [
                Self.input("query", "查询", .text, true, "用于向量检索的查询文本。"),
                Self.output("context", "检索结果", .text, "按相似度整理的资料片段与来源。"),
            ]
        case .llm:
            return [
                Self.input("prompt", "提示词", .text, true, "发给模型的用户提示词。"),
                Self.output("text", "回答", .text, "模型最终回答正文。"),
                Self.output("reasoning", "思考", .text, "服务商返回的可选推理文本。"),
            ]
        case .imageGeneration:
            var ports = [
                Self.input("prompt", "提示词", .text, true, "描述待生成图片的文本。"),
            ]
            if node.configuration.imageOperation == .edit {
                ports.append(Self.input("referenceImage", "原图", .image, true, "必须连接要编辑或作为参考的图片。"))
                ports.append(Self.input("maskImage", "遮罩", .image, false, "可选编辑遮罩；需与原图同尺寸同格式，并包含 alpha 通道。"))
            }
            ports.append(Self.output("image", "图片", .image, "已下载到本地运行目录的生成或编辑结果。"))
            return ports
        case .videoGeneration:
            return [
                Self.input("prompt", "提示词", .text, true, "描述镜头、动作、场景与光线的文本。"),
                Self.input("referenceImage", "参考图", .image, false, "可选首帧参考图；适配器不支持时会在运行前提示。"),
                Self.output("video", "视频", .video, "已下载到本地运行目录的 MP4。"),
            ]
        case .condition:
            return [
                Self.input("value", "文本", .text, true, "用于判断的文本。"),
                Self.output("true", "符合", .text, "条件成立时传递原文本。"),
                Self.output("false", "不符合", .text, "条件不成立时传递原文本。"),
            ]
        case .loop:
            return [
                Self.input("seed", "初始值", .text, true, "第一次循环使用的文本。"),
                Self.input("feedback", "反馈值", .text, true, "循环体执行后返回的文本。"),
                Self.output("iteration", "继续循环", .text, "进入循环体的当前文本。"),
                Self.output("completed", "循环完成", .text, "满足停止条件或达到上限后的最终文本。"),
            ]
        case .output:
            return [Self.input("value", "结果", .any, true, "需要展示、复制或打开的最终结果。")]
        case .unsupported:
            return []
        }
    }

    private static func input(
        _ id: String,
        _ title: String,
        _ type: WorkflowValueType,
        _ required: Bool,
        _ help: String
    ) -> WorkflowPortDescriptor {
        WorkflowPortDescriptor(id: id, title: title, direction: .input, valueType: type, isRequired: required, help: help)
    }

    private static func output(
        _ id: String,
        _ title: String,
        _ type: WorkflowValueType,
        _ help: String
    ) -> WorkflowPortDescriptor {
        WorkflowPortDescriptor(id: id, title: title, direction: .output, valueType: type, isRequired: false, help: help)
    }
}

/// 节点卡片使用的语义色。
enum WorkflowNodeTint: String, Codable, Hashable {
    case amber, blue, purple, green, pink, cyan, orange, indigo, gray
}

/// 生图节点调用生成接口还是图片编辑接口。
enum WorkflowImageOperation: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case generate
    case edit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generate: "文生图"
        case .edit: "图片编辑"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: (try? container.decode(String.self)) ?? "") ?? .generate
    }
}

/// 所有内置节点描述与帮助的注册表。
enum WorkflowNodeCatalog {
    /// 按节点类型读取描述。
    static func descriptor(for kind: WorkflowNodeKind) -> WorkflowNodeDescriptor {
        descriptors[kind.id] ?? unsupportedDescriptor(for: kind)
    }

    /// 节点面板中的全部描述。
    static var all: [WorkflowNodeDescriptor] {
        WorkflowNodeKind.catalog.map(descriptor(for:))
    }

    private static let descriptors: [String: WorkflowNodeDescriptor] = {
        let items: [WorkflowNodeDescriptor] = [
            WorkflowNodeDescriptor(
                kind: .runtimeInput,
                title: "运行时输入",
                summary: "每次运行前填写一个可复用文本参数",
                systemImage: "text.cursor",
                tint: .blue,
                usage: NodeUsageGuide(
                    purpose: "把简报、主题、剧本文本等变化内容作为工作流入口。节点保存参数名称和默认值，实际值在运行前填写，不会改动模板。",
                    setupSteps: ["填写清楚的参数名称。", "按需设置默认值和必填状态。", "运行工作流时在参数表中填写本次内容。"],
                    connectionExample: "运行时输入「创作简报」 → 提示词模板 {{brief}}",
                    resultDescription: "输出本次运行填写的纯文本。",
                    commonErrors: ["必填参数为空时无法开始运行。", "多个输入节点名称相同会难以辨认，建议使用唯一名称。"],
                    warnings: []
                )
            ),
            WorkflowNodeDescriptor(
                kind: .promptTemplate,
                title: "提示词模板",
                summary: "把多个文本变量组装成完整提示词",
                systemImage: "curlybraces",
                tint: .purple,
                usage: NodeUsageGuide(
                    purpose: "复用提示词库或编写内联模板，并将 {{variable}} 变量变成可连接端口。",
                    setupSteps: ["选择提示词库条目，或切换为内联模板。", "在正文中用 {{name}} 声明变量。", "为出现的每个变量连接一个文本输出。"],
                    connectionExample: "运行时输入 → {{brief}}；知识检索 → {{context}}；模板文本 → LLM",
                    resultDescription: "输出替换全部变量后的完整文本。绑定提示词库时，每次运行读取最新内容。",
                    commonErrors: ["变量端口未连接时校验失败。", "提示词条目被删除后会使用节点保存的快照，并显示警告。"],
                    warnings: ["模板变量名称区分大小写。"]
                )
            ),
            WorkflowNodeDescriptor(
                kind: .knowledgeSearch,
                title: "知识检索",
                summary: "从全局知识库召回相关资料片段",
                systemImage: "books.vertical",
                tint: .green,
                usage: NodeUsageGuide(
                    purpose: "将上游文本作为语义查询，从已建立向量索引的资料中选出最相关片段。",
                    setupSteps: ["先在设置中配置知识库嵌入服务。", "为需要使用的资料建立索引。", "选择可选集合、标签与 Top-K 数量。"],
                    connectionExample: "运行时输入「主题」 → 知识检索 → 提示词模板 {{context}}",
                    resultDescription: "按相似度输出 [资料标题#片段序号]、正文和分数。",
                    commonErrors: ["未配置嵌入模型或 API Key。", "筛选范围内没有已完成索引的资料。", "查询向量与现有索引指纹不一致。"],
                    warnings: ["检索会调用嵌入接口，可能产生少量费用。"]
                )
            ),
            WorkflowNodeDescriptor(
                kind: .llm,
                title: "LLM",
                summary: "调用已配置的大模型生成文本",
                systemImage: "sparkles",
                tint: .indigo,
                usage: NodeUsageGuide(
                    purpose: "执行剧本、分镜、改写、提取等文本生成任务，并实时展示流式结果。",
                    setupSteps: ["选择 LLM 服务商和模型。", "按需填写系统提示、温度和推理强度。", "把完整提示词连接到输入端口。"],
                    connectionExample: "提示词模板 → LLM「提示词」 → 结果输出",
                    resultDescription: "回答端口输出最终正文；思考端口输出服务商可选的推理文本。",
                    commonErrors: ["服务商、模型或 API Key 未配置。", "兼容网关不支持所选参数。", "请求超时或返回空内容。"],
                    warnings: ["每次执行都会产生一次模型请求，循环内可能重复计费。"]
                )
            ),
            WorkflowNodeDescriptor(
                kind: .imageGeneration,
                title: "生图",
                summary: "根据提示词生成新图或编辑上游图片",
                systemImage: "photo.artframe",
                tint: .pink,
                usage: NodeUsageGuide(
                    purpose: "生成角色图、场景图、商品图或分镜参考图，也可以把上游图片作为原图进行整体编辑或局部遮罩编辑。实际请求由所选源码适配器执行。",
                    setupSteps: ["在设置中配置生图服务商和 Key。", "选择“文生图”或“图片编辑”。", "选择服务商、模型与尺寸。", "连接提示词；图片编辑还必须连接原图，可选连接遮罩。"],
                    connectionExample: "文生图：LLM → 生图「提示词」；图片编辑：上游图片 → 生图「原图」，修改说明 →「提示词」",
                    resultDescription: "生成或编辑后的图片下载到本次运行的 Assets 目录，并从图片端口继续传递。",
                    commonErrors: ["图片编辑模式没有连接原图。", "所选适配器或模型不支持编辑。", "遮罩与原图尺寸或格式不一致。", "提示词触发内容限制。", "响应不含图片或下载失败。"],
                    warnings: ["图片编辑会同时计算文本、输入图片和输出图片用量；循环内使用时请先核对最大次数。"]
                )
            ),
            WorkflowNodeDescriptor(
                kind: .videoGeneration,
                title: "生视频",
                summary: "提交异步视频任务并下载成片",
                systemImage: "video.badge.waveform",
                tint: .cyan,
                usage: NodeUsageGuide(
                    purpose: "从镜头提示词生成视频，可在适配器支持时把上游图片作为首帧参考。",
                    setupSteps: ["在设置中配置生视频服务商和 Key。", "选择适配器支持的模型、尺寸与时长。", "连接提示词，并可选连接参考图片。"],
                    connectionExample: "LLM「回答」 → 生视频「提示词」；生图「图片」 → 生视频「参考图」",
                    resultDescription: "显示排队与生成进度，完成后把 MP4 下载到 Assets 目录。",
                    commonErrors: ["所选适配器不支持参考图。", "任务失败、过期或轮询超时。", "远端完成后媒体下载失败。"],
                    warnings: ["视频生成耗时较长且费用较高。停止本地轮询不一定取消远端任务。"]
                )
            ),
            WorkflowNodeDescriptor(
                kind: .condition,
                title: "条件分支",
                summary: "根据文本规则选择一条执行分支",
                systemImage: "arrow.triangle.branch",
                tint: .orange,
                usage: NodeUsageGuide(
                    purpose: "按等于、包含、正则或空值判断，将原文本送入符合或不符合分支。",
                    setupSteps: ["选择比较操作。", "需要时填写比较值。", "分别连接符合与不符合输出。"],
                    connectionExample: "LLM 回答 → 条件「包含：通过」 → 符合：输出 / 不符合：重写",
                    resultDescription: "只有命中的输出端口产生文本，另一分支在运行记录中标记跳过。",
                    commonErrors: ["正则表达式无效。", "分支没有连接到任何下游节点。"],
                    warnings: []
                )
            ),
            WorkflowNodeDescriptor(
                kind: .loop,
                title: "显式循环",
                summary: "用停止条件和次数上限安全地重复一段流程",
                systemImage: "repeat",
                tint: .amber,
                usage: NodeUsageGuide(
                    purpose: "让一段文本处理链反复优化。所有有向环都必须经过一个显式循环节点。",
                    setupSteps: ["把初始文本连接到 seed。", "把 iteration 接到循环体入口。", "把循环体结果接回 feedback。", "配置停止条件和 1–20 次上限。", "把 completed 接到循环外下游。"],
                    connectionExample: "输入 → seed；iteration → LLM → feedback；completed → 结果输出",
                    resultDescription: "停止条件成立时输出当前反馈；达到上限时输出最后反馈并附警告。",
                    commonErrors: ["feedback 没有形成回路。", "环路包含多个循环节点。", "普通节点直接形成环路。"],
                    warnings: ["循环体内的 LLM、生图和视频节点每轮都会产生新请求和费用。"]
                )
            ),
            WorkflowNodeDescriptor(
                kind: .output,
                title: "结果输出",
                summary: "集中查看、复制或打开最终结果",
                systemImage: "square.and.arrow.down",
                tint: .gray,
                usage: NodeUsageGuide(
                    purpose: "作为工作流终点，接收文本、图片或视频并在运行检查器中展示。",
                    setupSteps: ["连接需要保留的最终结果。", "运行后在运行标签或历史记录中打开结果。"],
                    connectionExample: "LLM / 生图 / 生视频 / 循环完成 → 结果输出",
                    resultDescription: "文本可复制；图片可预览；视频可播放；媒体可在 Finder 中定位。",
                    commonErrors: ["没有连接任何上游结果。", "上游分支未命中时本节点会被跳过。"],
                    warnings: []
                )
            ),
        ]
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }()

    private static func unsupportedDescriptor(for kind: WorkflowNodeKind) -> WorkflowNodeDescriptor {
        WorkflowNodeDescriptor(
            kind: kind,
            title: "不支持的节点",
            summary: "当前版本无法识别此节点类型",
            systemImage: "questionmark.square.dashed",
            tint: .gray,
            usage: NodeUsageGuide(
                purpose: "该节点来自更新版本或缺失的实现。为避免破坏数据，定义会原样保留但不能运行。",
                setupSteps: ["升级应用或安装包含该节点实现的版本。"],
                connectionExample: "不适用",
                resultDescription: "不会产生结果。",
                commonErrors: ["节点类型未注册。"],
                warnings: ["删除该节点会同时删除与它相连的连线。"]
            )
        )
    }
}

/// 工作流画布坐标。
struct WorkflowPoint: Codable, Hashable {
    var x: Double
    var y: Double

    static let zero = WorkflowPoint(x: 0, y: 0)

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0
    }
}

/// 文本条件操作符。
enum WorkflowComparison: String, Codable, CaseIterable, Identifiable, Hashable {
    case equals
    case contains
    case notContains
    case regex
    case isEmpty
    case isNotEmpty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equals: "等于"
        case .contains: "包含"
        case .notContains: "不包含"
        case .regex: "正则匹配"
        case .isEmpty: "为空"
        case .isNotEmpty: "非空"
        }
    }

    var needsOperand: Bool { self != .isEmpty && self != .isNotEmpty }

    /// 对文本执行条件判断。
    func evaluate(_ text: String, operand: String) throws -> Bool {
        switch self {
        case .equals: return text == operand
        case .contains: return text.localizedCaseInsensitiveContains(operand)
        case .notContains: return !text.localizedCaseInsensitiveContains(operand)
        case .regex:
            let expression = try NSRegularExpression(pattern: operand)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return expression.firstMatch(in: text, range: range) != nil
        case .isEmpty: return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .isNotEmpty: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// 一个节点的可持久化配置。
struct WorkflowNodeConfiguration: Codable, Hashable {
    var title: String = ""
    var text: String = ""
    var parameterName: String = "输入"
    var isRequired: Bool = true
    var usesPromptLibrary: Bool = false
    var promptItemID: UUID?
    var promptSnapshot: String = ""
    var providerID: UUID?
    var model: String = ""
    var systemPrompt: String = ""
    var temperature: Double = 0.7
    var reasoningEffort: ReasoningEffort = .none
    var collectionID: UUID?
    var tags: [String] = []
    var topK: Int = 5
    var comparison: WorkflowComparison = .contains
    var comparisonValue: String = ""
    var maxIterations: Int = 3
    var imageOperation: WorkflowImageOperation = .generate
    var mediaSize: String = ""
    var durationSeconds: Int = 4

    /// 从当前模板提取去重后的 `{{variable}}`。
    var templateVariables: [String] {
        let source = usesPromptLibrary ? promptSnapshot : text
        guard let regex = try? NSRegularExpression(pattern: #"\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}"#) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var result: [String] = []
        for match in regex.matches(in: source, range: range) {
            guard let swiftRange = Range(match.range(at: 1), in: source) else { continue }
            let name = String(source[swiftRange])
            if !result.contains(name) { result.append(name) }
        }
        return result
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        parameterName = try container.decodeIfPresent(String.self, forKey: .parameterName) ?? "输入"
        isRequired = try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? true
        usesPromptLibrary = try container.decodeIfPresent(Bool.self, forKey: .usesPromptLibrary) ?? false
        promptItemID = try container.decodeIfPresent(UUID.self, forKey: .promptItemID)
        promptSnapshot = try container.decodeIfPresent(String.self, forKey: .promptSnapshot) ?? ""
        providerID = try container.decodeIfPresent(UUID.self, forKey: .providerID)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
        reasoningEffort = (try? container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)) ?? .none
        collectionID = try container.decodeIfPresent(UUID.self, forKey: .collectionID)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        topK = min(20, max(1, try container.decodeIfPresent(Int.self, forKey: .topK) ?? 5))
        comparison = (try? container.decodeIfPresent(WorkflowComparison.self, forKey: .comparison)) ?? .contains
        comparisonValue = try container.decodeIfPresent(String.self, forKey: .comparisonValue) ?? ""
        maxIterations = min(20, max(1, try container.decodeIfPresent(Int.self, forKey: .maxIterations) ?? 3))
        imageOperation = (try? container.decodeIfPresent(WorkflowImageOperation.self, forKey: .imageOperation)) ?? .generate
        mediaSize = try container.decodeIfPresent(String.self, forKey: .mediaSize) ?? ""
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 4
    }
}

/// 画布上的一个节点实例。
struct WorkflowNode: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: WorkflowNodeKind
    var position: WorkflowPoint
    var configuration: WorkflowNodeConfiguration
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: WorkflowNodeKind,
        position: WorkflowPoint,
        configuration: WorkflowNodeConfiguration = WorkflowNodeConfiguration(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.position = position
        self.configuration = configuration
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = (try? container.decodeIfPresent(WorkflowNodeKind.self, forKey: .kind)) ?? .unsupported("missing")
        position = try container.decodeIfPresent(WorkflowPoint.self, forKey: .position) ?? .zero
        configuration = try container.decodeIfPresent(WorkflowNodeConfiguration.self, forKey: .configuration) ?? WorkflowNodeConfiguration()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    /// 当前节点的统一描述。
    var descriptor: WorkflowNodeDescriptor { WorkflowNodeCatalog.descriptor(for: kind) }

    /// 节点在画布上的显示标题。
    var displayTitle: String {
        let custom = configuration.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? descriptor.title : custom
    }
}

/// 两个端口之间的一条有向连接。
struct WorkflowConnection: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceNodeID: UUID
    var sourcePortID: String
    var targetNodeID: UUID
    var targetPortID: String

    init(
        id: UUID = UUID(),
        sourceNodeID: UUID,
        sourcePortID: String,
        targetNodeID: UUID,
        targetPortID: String
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.sourcePortID = sourcePortID
        self.targetNodeID = targetNodeID
        self.targetPortID = targetPortID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sourceNodeID = try container.decodeIfPresent(UUID.self, forKey: .sourceNodeID) ?? UUID()
        sourcePortID = try container.decodeIfPresent(String.self, forKey: .sourcePortID) ?? ""
        targetNodeID = try container.decodeIfPresent(UUID.self, forKey: .targetNodeID) ?? UUID()
        targetPortID = try container.decodeIfPresent(String.self, forKey: .targetPortID) ?? ""
    }
}

/// 保存的画布视口。
struct WorkflowViewport: Codable, Hashable {
    var offset: WorkflowPoint = .zero
    var zoom: Double = 1

    init(offset: WorkflowPoint = .zero, zoom: Double = 1) {
        self.offset = offset
        self.zoom = zoom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        offset = try container.decodeIfPresent(WorkflowPoint.self, forKey: .offset) ?? .zero
        zoom = min(2, max(0.4, try container.decodeIfPresent(Double.self, forKey: .zoom) ?? 1))
    }
}

/// 一个可复用工作流定义。
struct WorkflowDefinition: Identifiable, Codable, Hashable {
    var formatVersion: Int
    var id: UUID
    var name: String
    var nodes: [WorkflowNode]
    var connections: [WorkflowConnection]
    var viewport: WorkflowViewport
    var createdAt: Date
    var updatedAt: Date

    static let currentFormatVersion = 1

    init(
        id: UUID = UUID(),
        name: String,
        nodes: [WorkflowNode] = [],
        connections: [WorkflowConnection] = [],
        viewport: WorkflowViewport = WorkflowViewport(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        formatVersion = Self.currentFormatVersion
        self.id = id
        self.name = name
        self.nodes = nodes
        self.connections = connections
        self.viewport = viewport
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名工作流"
        nodes = try container.decodeIfPresent([WorkflowNode].self, forKey: .nodes) ?? []
        connections = try container.decodeIfPresent([WorkflowConnection].self, forKey: .connections) ?? []
        viewport = try container.decodeIfPresent(WorkflowViewport.self, forKey: .viewport) ?? WorkflowViewport()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// 创建一个可立即试用的入门工作流。
    static func starter(named name: String = "短剧创作入门") -> WorkflowDefinition {
        var inputConfig = WorkflowNodeConfiguration()
        inputConfig.parameterName = "创作简报"
        inputConfig.text = "一段具有反转的短剧简报"

        var templateConfig = WorkflowNodeConfiguration()
        templateConfig.text = "请根据以下简报写出一段节奏紧凑的短剧内容：\n\n{{brief}}"

        let input = WorkflowNode(kind: .runtimeInput, position: WorkflowPoint(x: 80, y: 180), configuration: inputConfig)
        let template = WorkflowNode(kind: .promptTemplate, position: WorkflowPoint(x: 390, y: 180), configuration: templateConfig)
        let output = WorkflowNode(kind: .output, position: WorkflowPoint(x: 700, y: 180))
        return WorkflowDefinition(
            name: name,
            nodes: [input, template, output],
            connections: [
                WorkflowConnection(sourceNodeID: input.id, sourcePortID: "text", targetNodeID: template.id, targetPortID: "brief"),
                WorkflowConnection(sourceNodeID: template.id, sourcePortID: "text", targetNodeID: output.id, targetPortID: "value"),
            ]
        )
    }
}

/// 节点端口在一次运行中传递的值。
enum WorkflowValue: Codable, Hashable, Sendable {
    case text(String)
    case image(String)
    case video(String)

    var valueType: WorkflowValueType {
        switch self {
        case .text: .text
        case .image: .image
        case .video: .video
        }
    }

    var payload: String {
        switch self {
        case .text(let value), .image(let value), .video(let value): value
        }
    }

    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? "text"
        let value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        switch type {
        case "image": self = .image(value)
        case "video": self = .video(value)
        default: self = .text(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(valueType.rawValue, forKey: .type)
        try container.encode(payload, forKey: .value)
    }
}

/// 单节点运行状态。
enum WorkflowNodeRunStatus: String, Codable, Hashable, Sendable {
    case pending, running, succeeded, skipped, warning, failed, cancelled

    var title: String {
        switch self {
        case .pending: "等待"
        case .running: "运行中"
        case .succeeded: "完成"
        case .skipped: "跳过"
        case .warning: "完成（有警告）"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .pending
    }
}

/// 整次工作流运行状态。
enum WorkflowRunStatus: String, Codable, Hashable, Sendable {
    case running, succeeded, warning, failed, cancelled

    var title: String {
        switch self {
        case .running: "运行中"
        case .succeeded: "已完成"
        case .warning: "已完成（有警告）"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .failed
    }
}

/// 一次运行中的单节点记录。
struct WorkflowNodeRun: Identifiable, Codable, Hashable, Sendable {
    var id: UUID { nodeID }
    var nodeID: UUID
    var status: WorkflowNodeRunStatus
    var outputs: [String: WorkflowValue]
    var message: String?
    var progress: Double?
    var iteration: Int?
    var startedAt: Date?
    var endedAt: Date?

    init(nodeID: UUID, status: WorkflowNodeRunStatus = .pending) {
        self.nodeID = nodeID
        self.status = status
        outputs = [:]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decodeIfPresent(UUID.self, forKey: .nodeID) ?? UUID()
        status = try container.decodeIfPresent(WorkflowNodeRunStatus.self, forKey: .status) ?? .pending
        outputs = try container.decodeIfPresent([String: WorkflowValue].self, forKey: .outputs) ?? [:]
        message = try container.decodeIfPresent(String.self, forKey: .message)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        iteration = try container.decodeIfPresent(Int.self, forKey: .iteration)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
    }
}

/// 一次完整或单节点目标运行的历史记录。
struct WorkflowRun: Identifiable, Codable, Hashable, Sendable {
    var formatVersion: Int
    var id: UUID
    var workflowID: UUID
    var targetNodeID: UUID?
    var status: WorkflowRunStatus
    var runtimeInputs: [String: String]
    var nodeRuns: [WorkflowNodeRun]
    var warnings: [String]
    var startedAt: Date
    var endedAt: Date?

    static let currentFormatVersion = 1

    init(
        id: UUID = UUID(),
        workflowID: UUID,
        targetNodeID: UUID?,
        runtimeInputs: [String: String],
        nodes: [WorkflowNode]
    ) {
        formatVersion = Self.currentFormatVersion
        self.id = id
        self.workflowID = workflowID
        self.targetNodeID = targetNodeID
        status = .running
        self.runtimeInputs = runtimeInputs
        nodeRuns = nodes.map { WorkflowNodeRun(nodeID: $0.id) }
        warnings = []
        startedAt = Date()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        workflowID = try container.decodeIfPresent(UUID.self, forKey: .workflowID) ?? UUID()
        targetNodeID = try container.decodeIfPresent(UUID.self, forKey: .targetNodeID)
        status = try container.decodeIfPresent(WorkflowRunStatus.self, forKey: .status) ?? .failed
        runtimeInputs = try container.decodeIfPresent([String: String].self, forKey: .runtimeInputs) ?? [:]
        nodeRuns = try container.decodeIfPresent([WorkflowNodeRun].self, forKey: .nodeRuns) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
    }

    /// 查找节点记录。
    func nodeRun(id: UUID?) -> WorkflowNodeRun? {
        guard let id else { return nil }
        return nodeRuns.first { $0.nodeID == id }
    }
}
