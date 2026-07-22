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
    case knowledgePreparation
    case knowledgeImport
    case llm
    case imageGeneration
    case videoGeneration
    case condition
    case loop
    case output
    case unsupported(String)

    /// 节点目录中的稳定顺序。
    static let catalog: [WorkflowNodeKind] = [
        .runtimeInput, .promptTemplate, .knowledgeSearch, .knowledgePreparation, .knowledgeImport, .llm,
        .imageGeneration, .videoGeneration, .condition, .loop, .output,
    ]

    /// 持久化使用的稳定标识符。
    var id: String {
        switch self {
        case .runtimeInput: "runtimeInput"
        case .promptTemplate: "promptTemplate"
        case .knowledgeSearch: "knowledgeSearch"
        case .knowledgePreparation: "knowledgePreparation"
        case .knowledgeImport: "knowledgeImport"
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
        case "knowledgePreparation": self = .knowledgePreparation
        case "knowledgeImport": self = .knowledgeImport
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
    case knowledgeCollection
    case image
    case video
    case audio
    case folder
    case any

    /// 中文显示名称。
    var title: String {
        switch self {
        case .text: "文本"
        case .knowledgeCollection: "知识集合"
        case .image: "图片"
        case .video: "视频"
        case .audio: "音频"
        case .folder: "文件夹"
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
    /// 该输入端口允许的最大连线数；输出端口固定为一条值流。
    var maxConnections: Int = 1
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
            let type = node.configuration.runtimeInputType
            return [Self.output(type.rawValue, type.title, type.valueType, "本次运行选择或填写的\(type.title)参数。")]
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
        case .knowledgePreparation:
            return [
                Self.input("requirements", "创作要素", .text, true, "要素提取模型输出的严格 JSON。"),
                Self.output("context", "证据文字", .text, "按明确身份核验后的知识证据；仅文字进入规划模型。"),
                Self.output("referenceManifest", "参考图清单", .text, "复制到本次运行目录的知识原图与稳定引用 ID。"),
            ]
        case .knowledgeImport:
            return [
                Self.input("folder", "图片文件夹", .folder, true, "本次运行选择的图片文件夹；会递归处理其中支持的图片。"),
                Self.input("prompt", "知识整理提示词", .text, true, "用于逐张理解图片、生成标题、正文和标签的提示词模板。"),
                Self.input("instructions", "整理要求", .text, true, "告诉视觉模型需要识别、提炼和保存哪些知识。"),
                Self.input("collection", "知识集合", .knowledgeCollection, true, "本次生成的知识资料写入哪个集合；空引用表示未分类。"),
                Self.output("summary", "入库摘要", .text, "成功、重复、索引和失败数量，以及逐文件错误。"),
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
                Self.input("referenceImage", "参考图片", .image, false, "按连线顺序传入最多 9 张参考图片。", maxConnections: 9),
                Self.input("referenceVideo", "参考视频", .video, false, "按连线顺序传入最多 3 段参考视频。", maxConnections: 3),
                Self.input("referenceAudio", "参考音频", .audio, false, "按连线顺序传入最多 3 段参考音频。", maxConnections: 3),
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
        _ help: String,
        maxConnections: Int = 1
    ) -> WorkflowPortDescriptor {
        WorkflowPortDescriptor(
            id: id,
            title: title,
            direction: .input,
            valueType: type,
            isRequired: required,
            help: help,
            maxConnections: max(1, maxConnections)
        )
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

/// 运行前输入节点接受的值类型。
enum WorkflowRuntimeInputType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case text
    case prompt
    case knowledgeCollection
    case image
    case video
    case audio
    case folder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "文本"
        case .prompt: "提示词"
        case .knowledgeCollection: "知识集合"
        case .image: "图片"
        case .video: "视频"
        case .audio: "音频"
        case .folder: "文件夹"
        }
    }

    var valueType: WorkflowValueType {
        switch self {
        case .text, .prompt: .text
        case .knowledgeCollection: .knowledgeCollection
        case .image: .image
        case .video: .video
        case .audio: .audio
        case .folder: .folder
        }
    }

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? "text"
        self = Self(rawValue: raw) ?? .text
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
                summary: "每次运行前填写文本、选择提示词或选择文件",
                systemImage: "tray.and.arrow.down",
                tint: .blue,
                usage: NodeUsageGuide(
                    purpose: "把简报、提示词、媒体文件或文件夹等变化内容作为工作流入口。节点保存参数名称、类型和默认值，实际值在运行前提供，不会改动模板。",
                    setupSteps: ["填写清楚的参数名称。", "选择文本、提示词、知识集合、图片、视频、音频或文件夹类型。", "按需设置默认值和必填状态。", "运行工作流时填写文本、选择提示词、知识集合或本次文件。"],
                    connectionExample: "文本输入「创作简报」 → 提示词模板；提示词、知识集合与文件夹输入 → 添加知识库",
                    resultDescription: "输出本次运行提供的类型化参数；文件和文件夹会先复制到本次运行目录。",
                    commonErrors: ["必填参数为空时无法开始运行。", "文件或文件夹不可读。", "多个输入节点名称相同会难以辨认，建议使用唯一名称。"],
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
                kind: .knowledgeImport,
                title: "添加知识库",
                summary: "让视觉模型整理文件夹图片并写入知识库",
                systemImage: "books.vertical.fill",
                tint: .green,
                usage: NodeUsageGuide(
                    purpose: "递归读取文件夹内的图片，逐张调用支持视觉的 LLM，按上游提示词与整理要求生成标题、正文和标签，并把原图与生成内容一起保存到全局知识库。",
                    setupSteps: ["选择支持视觉的 LLM 服务商和模型。", "设置公共标签与单次最多处理的图片数。", "连接文件夹、知识整理提示词、整理要求与知识集合后运行。"],
                    connectionExample: "运行时输入「图片文件夹」+「知识整理提示词」+「整理要求」+「知识集合」 → 添加知识库 → 结果输出",
                    resultDescription: "每张成功图片成为一条知识资料并保留原图；若已配置嵌入服务则自动建立向量索引，最后输出批处理摘要。",
                    commonErrors: ["所选服务商未开启视觉能力。", "文件夹内没有支持的图片。", "模型、API Key 或网络不可用。", "模型返回内容为空。"],
                    warnings: ["每张图片会产生一次视觉模型请求；请用单次上限控制费用。", "同一图片和生成内容重复运行时会跳过重复资料。"]
                )
            ),
            WorkflowNodeDescriptor(
                kind: .knowledgePreparation,
                title: "创作知识准备",
                summary: "逐项核验人物、产品与车内场景资料",
                systemImage: "books.vertical.circle",
                tint: .green,
                usage: NodeUsageGuide(
                    purpose: "读取要素提取 JSON，逐个检索全局知识库并严格核验明确身份；资料不足时暂停父运行，等待补库后从这里恢复。",
                    setupSteps: ["连接要素提取模型的严格 JSON 输出。", "设置每项候选上限。", "确保知识资料已建立索引并保留原始图片。"],
                    connectionExample: "LLM 要素提取 → 创作知识准备 → 规划提示词",
                    resultDescription: "输出文字证据与稳定参考图清单；原图只复制到运行目录，不发送给规划模型。",
                    commonErrors: ["JSON 格式不符合要素协议。", "明确人物、产品或车型没有准确匹配资料。"],
                    warnings: ["检索会调用嵌入接口；资料缺失时父运行会进入待补资料状态。", "纯文字资料可以参与规划，但没有原图可挂到分镜卡片。"]
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
                    purpose: "从镜头提示词生成视频，并按适配器能力接收有序的参考图片、视频和音频。",
                    setupSteps: ["在设置中配置生视频服务商；PixMax 需先启用并登录。", "选择适配器支持的模型、画幅、分辨率与时长。", "连接提示词，并按需连接参考图片、视频或音频。"],
                    connectionExample: "LLM「回答」 → 生视频「提示词」；多个媒体输入 → 对应参考端口，连线顺序就是素材编号",
                    resultDescription: "显示排队与生成进度，完成后把主视频和额外结果下载到本次运行的 Assets 目录。",
                    commonErrors: ["模型不支持当前参考素材组合。", "PixMax 登录已失效或网络异常。", "任务失败或远端完成后媒体下载失败。"],
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
                    purpose: "作为工作流终点，接收文本、图片、视频、音频或文件夹并在运行检查器中展示。",
                    setupSteps: ["连接需要保留的最终结果。", "运行后在运行标签或历史记录中打开结果。"],
                    connectionExample: "LLM / 生图 / 生视频 / 循环完成 → 结果输出",
                    resultDescription: "文本可复制；图片可预览；视频和音频可播放；媒体与文件夹可打开或在 Finder 中定位。",
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
    var runtimeInputType: WorkflowRuntimeInputType = .text
    /// 提示词类型运行输入在运行时可选择的提示词库分类。
    var promptCategory: PromptCategory = .script
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
    /// “添加知识库”节点单次最多处理的图片数量。
    var maxFiles: Int = 50
    var comparison: WorkflowComparison = .contains
    var comparisonValue: String = ""
    var maxIterations: Int = 3
    var imageOperation: WorkflowImageOperation = .generate
    var mediaSize: String = ""
    var videoResolution: String = ""
    var durationSeconds: Int = 4
    var includeAudio: Bool = false

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
        runtimeInputType = (try? container.decodeIfPresent(WorkflowRuntimeInputType.self, forKey: .runtimeInputType)) ?? .text
        promptCategory = (try? container.decodeIfPresent(PromptCategory.self, forKey: .promptCategory)) ?? .script
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
        maxFiles = min(500, max(1, try container.decodeIfPresent(Int.self, forKey: .maxFiles) ?? 50))
        comparison = (try? container.decodeIfPresent(WorkflowComparison.self, forKey: .comparison)) ?? .contains
        comparisonValue = try container.decodeIfPresent(String.self, forKey: .comparisonValue) ?? ""
        maxIterations = min(20, max(1, try container.decodeIfPresent(Int.self, forKey: .maxIterations) ?? 3))
        imageOperation = (try? container.decodeIfPresent(WorkflowImageOperation.self, forKey: .imageOperation)) ?? .generate
        mediaSize = try container.decodeIfPresent(String.self, forKey: .mediaSize) ?? ""
        videoResolution = try container.decodeIfPresent(String.self, forKey: .videoResolution) ?? ""
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 4
        includeAudio = try container.decodeIfPresent(Bool.self, forKey: .includeAudio) ?? false
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
    /// 同一目标端口内的稳定素材顺序，从零开始。
    var targetOrder: Int

    init(
        id: UUID = UUID(),
        sourceNodeID: UUID,
        sourcePortID: String,
        targetNodeID: UUID,
        targetPortID: String,
        targetOrder: Int = 0
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.sourcePortID = sourcePortID
        self.targetNodeID = targetNodeID
        self.targetPortID = targetPortID
        self.targetOrder = max(0, targetOrder)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sourceNodeID = try container.decodeIfPresent(UUID.self, forKey: .sourceNodeID) ?? UUID()
        sourcePortID = try container.decodeIfPresent(String.self, forKey: .sourcePortID) ?? ""
        targetNodeID = try container.decodeIfPresent(UUID.self, forKey: .targetNodeID) ?? UUID()
        targetPortID = try container.decodeIfPresent(String.self, forKey: .targetPortID) ?? ""
        targetOrder = max(0, try container.decodeIfPresent(Int.self, forKey: .targetOrder) ?? 0)
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
    /// 是否为应用内置模板；内置模板只读，只能复制后编辑。
    var isBuiltIn: Bool
    var nodes: [WorkflowNode]
    var connections: [WorkflowConnection]
    var viewport: WorkflowViewport
    var createdAt: Date
    var updatedAt: Date

    static let currentFormatVersion = 3

    init(
        id: UUID = UUID(),
        name: String,
        isBuiltIn: Bool = false,
        nodes: [WorkflowNode] = [],
        connections: [WorkflowConnection] = [],
        viewport: WorkflowViewport = WorkflowViewport(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        formatVersion = Self.currentFormatVersion
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.nodes = nodes
        self.connections = connections
        self.viewport = viewport
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = max(Self.currentFormatVersion, try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名工作流"
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
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

    /// 内置“添加知识库”工作流的稳定 ID，用于为已有安装补齐模板并避免重复创建。
    static let knowledgeImportWorkflowID = UUID(uuidString: "ADD0A11B-0000-4B00-8000-000000000001")!

    /// 创建内置的图片文件夹知识入库工作流。
    static func knowledgeImport() -> WorkflowDefinition {
        var folderConfiguration = WorkflowNodeConfiguration()
        folderConfiguration.parameterName = "图片文件夹"
        folderConfiguration.runtimeInputType = .folder

        var instructionsConfiguration = WorkflowNodeConfiguration()
        instructionsConfiguration.parameterName = "整理要求"
        instructionsConfiguration.text = "请识别图片中的主体、场景、风格、关键细节和可复用知识，使用准确、便于检索的中文整理。"

        var promptConfiguration = WorkflowNodeConfiguration()
        promptConfiguration.parameterName = "知识整理提示词"
        promptConfiguration.runtimeInputType = .prompt
        promptConfiguration.promptCategory = .knowledgeImport
        promptConfiguration.promptSnapshot = DefaultPrompts.knowledgeImportPromptTemplate

        var collectionConfiguration = WorkflowNodeConfiguration()
        collectionConfiguration.parameterName = "知识集合"
        collectionConfiguration.runtimeInputType = .knowledgeCollection
        collectionConfiguration.isRequired = false

        var importConfiguration = WorkflowNodeConfiguration()
        importConfiguration.title = "LLM 图片知识入库"
        importConfiguration.temperature = 0.2
        importConfiguration.maxFiles = 50

        let folder = WorkflowNode(
            kind: .runtimeInput,
            position: WorkflowPoint(x: 60, y: 100),
            configuration: folderConfiguration
        )
        let instructions = WorkflowNode(
            kind: .runtimeInput,
            position: WorkflowPoint(x: 60, y: 320),
            configuration: instructionsConfiguration
        )
        let prompt = WorkflowNode(
            kind: .runtimeInput,
            position: WorkflowPoint(x: 60, y: 540),
            configuration: promptConfiguration
        )
        let collection = WorkflowNode(
            kind: .runtimeInput,
            position: WorkflowPoint(x: 60, y: 760),
            configuration: collectionConfiguration
        )
        let knowledgeImport = WorkflowNode(
            kind: .knowledgeImport,
            position: WorkflowPoint(x: 430, y: 390),
            configuration: importConfiguration
        )
        let output = WorkflowNode(kind: .output, position: WorkflowPoint(x: 790, y: 390))

        return WorkflowDefinition(
            id: knowledgeImportWorkflowID,
            name: "添加知识库",
            isBuiltIn: true,
            nodes: [folder, instructions, prompt, collection, knowledgeImport, output],
            connections: [
                WorkflowConnection(sourceNodeID: folder.id, sourcePortID: "folder", targetNodeID: knowledgeImport.id, targetPortID: "folder"),
                WorkflowConnection(sourceNodeID: instructions.id, sourcePortID: "text", targetNodeID: knowledgeImport.id, targetPortID: "instructions"),
                WorkflowConnection(sourceNodeID: prompt.id, sourcePortID: "prompt", targetNodeID: knowledgeImport.id, targetPortID: "prompt"),
                WorkflowConnection(sourceNodeID: collection.id, sourcePortID: "knowledgeCollection", targetNodeID: knowledgeImport.id, targetPortID: "collection"),
                WorkflowConnection(sourceNodeID: knowledgeImport.id, sourcePortID: "summary", targetNodeID: output.id, targetPortID: "value"),
            ]
        )
    }

    /// 内置“汽车内广告分镜”工作流的稳定 ID。
    static let vehicleInteriorAdWorkflowID = UUID(uuidString: "ADD0A11B-0000-4B00-8000-000000000002")!

    /// 用文章语义召回适用的全局创作规则；这不是某一人物或某一种表格的专用查询。
    static let vehicleInteriorAdRuleQueryTemplate = """
    检索与下面汽车广告文章有关的全局创作规则、强制约束、优先级、身份覆盖、固定选角、产品边界、车型场景和连续性规则。优先召回明确标注“规则”“强制”“优先级”“覆盖”“禁止”的资料。

    文章：
    {{article}}
    """

    /// 要素模型先理解知识库规则，再决定真正需要核验的视觉身份和产品场景身份。
    static let vehicleInteriorAdExtractionPromptTemplate = """
    从下面文章逐项提取制作汽车内广告分镜必须锁定的资料。只输出 JSON，不要 Markdown 或解释。
    JSON 结构必须是：
    {"requirements":[{"id":"CHAR-1","category":"character","name":"规则解析后的真实视觉身份","role":"原文称呼、剧情角色、座位身份和规则映射说明","aliases":["该视觉身份的真实别名或规则指定参考文件名"],"searchTerms":["精确检索词"],"isGenericVehicleScene":false}]}
    requirements 必须是 JSON 对象数组，每一项都必须完整写成 {"id":...}，不能省略花括号或键名开头的双引号。

    规则处理原则：
    1. “知识库候选规则”只是召回片段。只有正文明确声明自己是规则、强制约束、具有优先级或覆盖关系时，才允许覆盖文章；普通人物介绍、产品说明和相似案例不能覆盖文章。
    2. 先按规则的适用范围、优先级和角色条件完成身份解析，再输出 requirements。规则可以约束人物、产品、车型、座舱、参考文件、禁止事项和连续性，不限于固定选角。
    3. 规则若规定“文案姓名仅作称呼、视觉身份按角色固定”，name 必须填写规则指定的视觉身份；role 保留原文称呼并写明映射；aliases 只放该视觉身份的真实别名和规则指定的参考文件名，不把被覆盖的文案称呼伪装成身份别名。
    4. 多条规则冲突时只执行正文明确给出的优先级；无法判定优先级时，不擅自合并或替代，保留文章明确身份以触发人工补资料。
    5. 没有适用强制规则时，保持文章身份，不用相似对象替代。

    category 只能是 character、product、vehicleScene。每个规则解析后的明确人物、目标产品/型号、指定车型/座舱都必须单独一项。车型未指定时仍添加一项 name=通用汽车座舱、category=vehicleScene、isGenericVehicleScene=true。目标产品未指定时添加 name=文章未明确目标产品 的 product 项，使流程请求用户补充。按文章首次出现顺序输出。

    知识库候选规则：
    {{rules}}

    文章：
    {{article}}
    """

    /// 规划模型同时看到适用规则候选，确保身份锁和产品边界贯穿全片。
    static let vehicleInteriorAdPlanningPromptTemplate = """
    你是汽车内短视频广告总导演。先规划观众从开头到结尾的完整观看体验，再写可供审校的分镜草案。

    硬性规则：
    1. 先明确观看承诺、连续好奇链、情绪曲线、戏剧分组与产品证明边界，再决定镜头数量；不要从逐句拆镜开始。
    2. 第一个剧情事件必须在 0.5 秒内开始；审核 0–3 秒与 0–5 秒留存。正常戏剧组不少于 4 秒，时长由文章内容决定，不为凑模型最小时长添加空镜。
    3. 每组都要推进故事或兑现产品证据；删除任何不改变理解、情绪或证据的无效镜头。
    4. 不添加原文没有的事实、台词、效果或产品能力。清楚记录人物座位、朝向、车门方向、手持物、上下车状态与跨镜连续性。
    5. 只执行候选规则中明确声明为规则、强制约束、优先级或覆盖关系且适用于本文的内容；普通召回资料不是规则。规则指定的视觉人物身份优先于文案称呼，但台词和剧情称呼仍保留原文。
    6. 只把已核验证据文字作为知识事实。参考图清单只用于给最终镜头声明引用，不把图片当作你看过的多模态输入。

    原文：
    {{article}}

    知识库候选规则：
    {{rules}}

    已核验知识证据：
    {{context}}

    可用参考图清单：
    {{references}}
    """

    /// 审校模型再次校验规则适用范围，避免规划阶段遗漏或误用普通知识资料。
    static let vehicleInteriorAdReviewPromptTemplate = """
    你是最终分镜审校导演。对草案逐项检查并完整重写：原文事实与台词、适用的强制规则、规则优先级与覆盖范围、视觉身份锁、产品证据边界、人物座位、镜头轴线、车门方向、手持物、进出车连续性、0–3/0–5 秒留存、无效镜头、产品露出是否过早或无证据。普通召回资料不能冒充强制规则；任何不合格处直接修正，不写审校报告。

    最终只输出当前卡片解析器兼容的 Markdown 分镜。每个镜头必须以“## 镜头 N”开始，并包含：
    - 时长：N 秒
    - 戏剧任务：本镜如何推进观看体验
    - 画面描述：文案称呼、实际视觉人物身份、座位、动作、车门/朝向、产品与场景
    - 镜头与运动：景别、机位、运动、构图、光线
    - 台词/声音：严格保留原文或明确写无
    - 连续性：与前后镜头可拼接的状态
    - 参考资料：CHAR-01, PROD-01, SCENE-01（只能选清单里的有效 ID，最多 9 个）
    不要输出 JSON、总评、代码围栏或额外前言。

    原文：
    {{article}}

    知识库候选规则：
    {{rules}}

    知识证据：
    {{context}}

    有效参考图清单：
    {{references}}

    规划草案：
    {{draft}}
    """

    /// 创建受众体验优先、带严格知识核验的汽车内广告分镜工作流。
    static func vehicleInteriorAd() -> WorkflowDefinition {
        var articleConfiguration = WorkflowNodeConfiguration()
        articleConfiguration.parameterName = "广告文章"
        articleConfiguration.runtimeInputType = .text
        articleConfiguration.text = ""

        var ruleQueryConfiguration = WorkflowNodeConfiguration()
        ruleQueryConfiguration.title = "创作规则检索提示"
        ruleQueryConfiguration.text = vehicleInteriorAdRuleQueryTemplate

        var ruleSearchConfiguration = WorkflowNodeConfiguration()
        ruleSearchConfiguration.title = "创作规则检索"
        ruleSearchConfiguration.topK = 12

        var extractionPromptConfiguration = WorkflowNodeConfiguration()
        extractionPromptConfiguration.title = "要素提取提示"
        extractionPromptConfiguration.text = vehicleInteriorAdExtractionPromptTemplate

        var extractionConfiguration = WorkflowNodeConfiguration()
        extractionConfiguration.title = "LLM 要素提取"
        extractionConfiguration.temperature = 0.1
        extractionConfiguration.reasoningEffort = .low

        var knowledgeConfiguration = WorkflowNodeConfiguration()
        knowledgeConfiguration.title = "创作知识准备"
        knowledgeConfiguration.topK = 12

        var planningPromptConfiguration = WorkflowNodeConfiguration()
        planningPromptConfiguration.title = "全片规划提示"
        planningPromptConfiguration.text = vehicleInteriorAdPlanningPromptTemplate

        var planningConfiguration = WorkflowNodeConfiguration()
        planningConfiguration.title = "中等推理规划"
        planningConfiguration.temperature = 0.3
        planningConfiguration.reasoningEffort = .medium

        var reviewPromptConfiguration = WorkflowNodeConfiguration()
        reviewPromptConfiguration.title = "高推理审校提示"
        reviewPromptConfiguration.text = vehicleInteriorAdReviewPromptTemplate

        var reviewConfiguration = WorkflowNodeConfiguration()
        reviewConfiguration.title = "高推理审校重写"
        reviewConfiguration.temperature = 0.2
        reviewConfiguration.reasoningEffort = .high

        let article = WorkflowNode(kind: .runtimeInput, position: WorkflowPoint(x: 40, y: 260), configuration: articleConfiguration)
        let ruleQuery = WorkflowNode(kind: .promptTemplate, position: WorkflowPoint(x: 330, y: 40), configuration: ruleQueryConfiguration)
        let ruleSearch = WorkflowNode(kind: .knowledgeSearch, position: WorkflowPoint(x: 650, y: 40), configuration: ruleSearchConfiguration)
        let extractionPrompt = WorkflowNode(kind: .promptTemplate, position: WorkflowPoint(x: 950, y: 100), configuration: extractionPromptConfiguration)
        let extraction = WorkflowNode(kind: .llm, position: WorkflowPoint(x: 1260, y: 100), configuration: extractionConfiguration)
        let knowledge = WorkflowNode(kind: .knowledgePreparation, position: WorkflowPoint(x: 1570, y: 100), configuration: knowledgeConfiguration)
        let planningPrompt = WorkflowNode(kind: .promptTemplate, position: WorkflowPoint(x: 1880, y: 190), configuration: planningPromptConfiguration)
        let planning = WorkflowNode(kind: .llm, position: WorkflowPoint(x: 2210, y: 190), configuration: planningConfiguration)
        let reviewPrompt = WorkflowNode(kind: .promptTemplate, position: WorkflowPoint(x: 2520, y: 250), configuration: reviewPromptConfiguration)
        let review = WorkflowNode(kind: .llm, position: WorkflowPoint(x: 2850, y: 250), configuration: reviewConfiguration)
        let output = WorkflowNode(kind: .output, position: WorkflowPoint(x: 3160, y: 250))

        return WorkflowDefinition(
            id: vehicleInteriorAdWorkflowID,
            name: "汽车内广告分镜",
            isBuiltIn: true,
            nodes: [article, ruleQuery, ruleSearch, extractionPrompt, extraction, knowledge, planningPrompt, planning, reviewPrompt, review, output],
            connections: [
                WorkflowConnection(sourceNodeID: article.id, sourcePortID: "text", targetNodeID: ruleQuery.id, targetPortID: "article"),
                WorkflowConnection(sourceNodeID: ruleQuery.id, sourcePortID: "text", targetNodeID: ruleSearch.id, targetPortID: "query"),
                WorkflowConnection(sourceNodeID: article.id, sourcePortID: "text", targetNodeID: extractionPrompt.id, targetPortID: "article"),
                WorkflowConnection(sourceNodeID: ruleSearch.id, sourcePortID: "context", targetNodeID: extractionPrompt.id, targetPortID: "rules"),
                WorkflowConnection(sourceNodeID: extractionPrompt.id, sourcePortID: "text", targetNodeID: extraction.id, targetPortID: "prompt"),
                WorkflowConnection(sourceNodeID: extraction.id, sourcePortID: "text", targetNodeID: knowledge.id, targetPortID: "requirements"),
                WorkflowConnection(sourceNodeID: article.id, sourcePortID: "text", targetNodeID: planningPrompt.id, targetPortID: "article"),
                WorkflowConnection(sourceNodeID: ruleSearch.id, sourcePortID: "context", targetNodeID: planningPrompt.id, targetPortID: "rules"),
                WorkflowConnection(sourceNodeID: knowledge.id, sourcePortID: "context", targetNodeID: planningPrompt.id, targetPortID: "context"),
                WorkflowConnection(sourceNodeID: knowledge.id, sourcePortID: "referenceManifest", targetNodeID: planningPrompt.id, targetPortID: "references"),
                WorkflowConnection(sourceNodeID: planningPrompt.id, sourcePortID: "text", targetNodeID: planning.id, targetPortID: "prompt"),
                WorkflowConnection(sourceNodeID: article.id, sourcePortID: "text", targetNodeID: reviewPrompt.id, targetPortID: "article"),
                WorkflowConnection(sourceNodeID: ruleSearch.id, sourcePortID: "context", targetNodeID: reviewPrompt.id, targetPortID: "rules"),
                WorkflowConnection(sourceNodeID: knowledge.id, sourcePortID: "context", targetNodeID: reviewPrompt.id, targetPortID: "context"),
                WorkflowConnection(sourceNodeID: knowledge.id, sourcePortID: "referenceManifest", targetNodeID: reviewPrompt.id, targetPortID: "references"),
                WorkflowConnection(sourceNodeID: planning.id, sourcePortID: "text", targetNodeID: reviewPrompt.id, targetPortID: "draft"),
                WorkflowConnection(sourceNodeID: reviewPrompt.id, sourcePortID: "text", targetNodeID: review.id, targetPortID: "prompt"),
                WorkflowConnection(sourceNodeID: review.id, sourcePortID: "text", targetNodeID: output.id, targetPortID: "value"),
            ],
            viewport: WorkflowViewport(offset: WorkflowPoint(x: 20, y: 40), zoom: 0.64)
        )
    }
}

/// 节点端口在一次运行中传递的值。
enum WorkflowValue: Codable, Hashable, Sendable {
    case text(String)
    case knowledgeCollection(String)
    case image(String)
    case video(String)
    case audio(String)
    case folder(String)

    var valueType: WorkflowValueType {
        switch self {
        case .text: .text
        case .knowledgeCollection: .knowledgeCollection
        case .image: .image
        case .video: .video
        case .audio: .audio
        case .folder: .folder
        }
    }

    var payload: String {
        switch self {
        case .text(let value), .knowledgeCollection(let value), .image(let value), .video(let value), .audio(let value), .folder(let value): value
        }
    }

    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? "text"
        let value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        switch type {
        case "knowledgeCollection": self = .knowledgeCollection(value)
        case "image": self = .image(value)
        case "video": self = .video(value)
        case "audio": self = .audio(value)
        case "folder": self = .folder(value)
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
    case pending, running, waiting, succeeded, skipped, warning, failed, cancelled

    var title: String {
        switch self {
        case .pending: "等待"
        case .running: "运行中"
        case .waiting: "待补资料"
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
    case running, waitingForKnowledge, succeeded, warning, failed, cancelled

    var title: String {
        switch self {
        case .running: "运行中"
        case .waitingForKnowledge: "待补资料"
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

/// 创作知识需求的稳定类别，也决定自动补库顺序。
enum WorkflowKnowledgeCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case character
    case product
    case vehicleScene

    /// 中文类别名。
    var title: String {
        switch self {
        case .character: "人物"
        case .product: "产品"
        case .vehicleScene: "车内场景"
        }
    }

    /// 自动补库时使用的内置提示词名。
    var knowledgeImportPromptName: String {
        switch self {
        case .character: DefaultPrompts.characterKnowledgeImportPromptName
        case .product: DefaultPrompts.productKnowledgeImportPromptName
        case .vehicleScene: DefaultPrompts.vehicleKnowledgeImportPromptName
        }
    }
}

/// 要素提取模型输出的一项明确知识需求。
struct WorkflowKnowledgeRequirement: Codable, Hashable, Sendable {
    var id: String
    var category: WorkflowKnowledgeCategory
    var name: String
    var role: String
    var aliases: [String]
    var searchTerms: [String]
    var isGenericVehicleScene: Bool

    init(
        id: String,
        category: WorkflowKnowledgeCategory,
        name: String,
        role: String = "",
        aliases: [String] = [],
        searchTerms: [String] = [],
        isGenericVehicleScene: Bool = false
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.role = role
        self.aliases = aliases
        self.searchTerms = searchTerms
        self.isGenericVehicleScene = isGenericVehicleScene
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        category = (try? container.decodeIfPresent(WorkflowKnowledgeCategory.self, forKey: .category)) ?? .product
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        searchTerms = try container.decodeIfPresent([String].self, forKey: .searchTerms) ?? []
        isGenericVehicleScene = try container.decodeIfPresent(Bool.self, forKey: .isGenericVehicleScene) ?? false
    }
}

/// 要素提取节点的严格 JSON 包装。
struct WorkflowKnowledgeRequirements: Codable, Hashable, Sendable {
    var requirements: [WorkflowKnowledgeRequirement]

    init(requirements: [WorkflowKnowledgeRequirement]) {
        self.requirements = requirements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requirements = try container.decodeIfPresent([WorkflowKnowledgeRequirement].self, forKey: .requirements) ?? []
    }
}

/// 父运行持久化的一项待补资料。
struct WorkflowKnowledgeGap: Identifiable, Codable, Hashable, Sendable {
    var id: String { requirement.id }
    var requirement: WorkflowKnowledgeRequirement
    var message: String

    init(requirement: WorkflowKnowledgeRequirement, message: String) {
        self.requirement = requirement
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requirement = try container.decodeIfPresent(WorkflowKnowledgeRequirement.self, forKey: .requirement)
            ?? WorkflowKnowledgeRequirement(id: UUID().uuidString, category: .product, name: "未知产品")
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? "资料未命中"
    }
}

/// 一张复制到运行目录中的知识参考图。
struct WorkflowReferenceManifestEntry: Codable, Hashable, Sendable {
    var referenceID: String
    var requirementID: String
    var category: WorkflowKnowledgeCategory
    var documentID: UUID
    var title: String
    var relativePath: String
    var score: Double
}

/// 知识准备节点输出的稳定参考图清单。
struct WorkflowReferenceManifest: Codable, Hashable, Sendable {
    var entries: [WorkflowReferenceManifestEntry]
}

/// 知识准备节点核验标题、标签、正文与原文件所需的只读快照。
struct WorkflowKnowledgeDocumentEvidence: Hashable, Sendable {
    var documentID: UUID
    var title: String
    var tags: [String]
    var content: String
    var originalFileURL: URL?
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
    var runtimeInputs: [String: WorkflowValue]
    var nodeRuns: [WorkflowNodeRun]
    var warnings: [String]
    /// 父创作运行当前仍缺少的资料。
    var pendingKnowledgeGaps: [WorkflowKnowledgeGap]
    /// 补库子运行指向的父运行。
    var parentRunID: UUID?
    /// 父运行已启动过的补库子运行。
    var childRunIDs: [UUID]
    /// 补库子运行正在处理的资料类别。
    var knowledgeGapCategory: WorkflowKnowledgeCategory?
    var startedAt: Date
    var endedAt: Date?

    static let currentFormatVersion = 4

    init(
        id: UUID = UUID(),
        workflowID: UUID,
        targetNodeID: UUID?,
        runtimeInputs: [String: WorkflowValue],
        nodes: [WorkflowNode],
        parentRunID: UUID? = nil,
        knowledgeGapCategory: WorkflowKnowledgeCategory? = nil
    ) {
        formatVersion = Self.currentFormatVersion
        self.id = id
        self.workflowID = workflowID
        self.targetNodeID = targetNodeID
        status = .running
        self.runtimeInputs = runtimeInputs
        nodeRuns = nodes.map { WorkflowNodeRun(nodeID: $0.id) }
        warnings = []
        pendingKnowledgeGaps = []
        self.parentRunID = parentRunID
        childRunIDs = []
        self.knowledgeGapCategory = knowledgeGapCategory
        startedAt = Date()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = max(Self.currentFormatVersion, try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        workflowID = try container.decodeIfPresent(UUID.self, forKey: .workflowID) ?? UUID()
        targetNodeID = try container.decodeIfPresent(UUID.self, forKey: .targetNodeID)
        status = try container.decodeIfPresent(WorkflowRunStatus.self, forKey: .status) ?? .failed
        if let values = try? container.decode([String: WorkflowValue].self, forKey: .runtimeInputs) {
            runtimeInputs = values
        } else if let legacy = try? container.decode([String: String].self, forKey: .runtimeInputs) {
            runtimeInputs = legacy.mapValues(WorkflowValue.text)
        } else {
            runtimeInputs = [:]
        }
        nodeRuns = try container.decodeIfPresent([WorkflowNodeRun].self, forKey: .nodeRuns) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        pendingKnowledgeGaps = try container.decodeIfPresent([WorkflowKnowledgeGap].self, forKey: .pendingKnowledgeGaps) ?? []
        parentRunID = try container.decodeIfPresent(UUID.self, forKey: .parentRunID)
        childRunIDs = try container.decodeIfPresent([UUID].self, forKey: .childRunIDs) ?? []
        knowledgeGapCategory = try? container.decodeIfPresent(WorkflowKnowledgeCategory.self, forKey: .knowledgeGapCategory)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
    }

    /// 查找节点记录。
    func nodeRun(id: UUID?) -> WorkflowNodeRun? {
        guard let id else { return nil }
        return nodeRuns.first { $0.nodeID == id }
    }
}
