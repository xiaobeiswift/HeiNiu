/// 短剧项目（立项看板）模型。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// 项目生命周期状态。
///
/// v1 仅用于看板展示与筛选；不驱动自动流水线。
enum ProjectStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    /// 构思中：只有题材/灵感。
    case idea
    /// 筹备中：定受众、调性、参考。
    case planning
    /// 剧本中。
    case writing
    /// 分镜中。
    case storyboard
    /// 制作中。
    case production
    /// 已完成。
    case done
    /// 已归档。
    case archived

    var id: String { rawValue }

    /// 列表/徽章文案。
    var title: String {
        switch self {
        case .idea: "构思中"
        case .planning: "筹备中"
        case .writing: "剧本中"
        case .storyboard: "分镜中"
        case .production: "制作中"
        case .done: "已完成"
        case .archived: "已归档"
        }
    }

    /// 是否算「进行中」（列表筛选用）。
    var isActive: Bool {
        switch self {
        case .archived, .done: false
        default: true
        }
    }
}

/// 一条短剧项目（立项壳，不含集数实体）。
///
/// ## 设计原则
///
/// - **先立项、后拆集**：`targetEpisodeCount` 只是可选预估，不是集数列表。
/// - **项目独立**：每个项目维护自己的元数据与流水线产物。
///
/// 持久化：`projects.json`（见 ``AppPaths/projectsFileURL``）。
///
nonisolated struct ProjectItem: Identifiable, Codable, Hashable, Sendable {
    /// 唯一标识。
    var id: UUID
    /// 项目名称。
    var name: String
    /// 一句话卖点 / logline。
    var logline: String
    /// 故事概要。
    var synopsis: String
    /// 题材（自由文本，如「都市反转」「古装甜宠」）。
    var genre: String
    /// 受众。
    var audience: String
    /// 当前状态。
    var status: ProjectStatus
    /// 预估集数（可选；不是真实集数实体）。
    var targetEpisodeCount: Int?
    /// 单集目标时长（秒，可选）。
    var episodeDurationSeconds: Int?
    /// 备注。
    var notes: String
    /// 外部素材文件夹路径（可选；有值视为「外部文件夹」项目）。
    var folderPath: String?
    /// 项目引用的全局知识集合。
    var knowledgeCollectionIDs: [UUID]
    /// 项目单独引用的全局知识资料。
    var knowledgeDocumentIDs: [UUID]
    /// 列表排序，越小越靠前；同权按 `updatedAt`。
    var sortOrder: Int
    /// 创建时间。
    var createdAt: Date
    /// 最近更新时间。
    var updatedAt: Date

    /// 默认单集时长：90 秒。
    static let defaultEpisodeDurationSeconds: Int = 90

    init(
        id: UUID = UUID(),
        name: String,
        logline: String = "",
        synopsis: String = "",
        genre: String = "",
        audience: String = "",
        status: ProjectStatus = .idea,
        targetEpisodeCount: Int? = nil,
        episodeDurationSeconds: Int? = nil,
        notes: String = "",
        folderPath: String? = nil,
        knowledgeCollectionIDs: [UUID] = [],
        knowledgeDocumentIDs: [UUID] = [],
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.logline = logline
        self.synopsis = synopsis
        self.genre = genre
        self.audience = audience
        self.status = status
        self.targetEpisodeCount = targetEpisodeCount
        self.episodeDurationSeconds = episodeDurationSeconds
        self.notes = notes
        self.folderPath = folderPath
        self.knowledgeCollectionIDs = knowledgeCollectionIDs
        self.knowledgeDocumentIDs = knowledgeDocumentIDs
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 容错解码：缺字段用默认值，兼容后续加字段。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名项目"
        logline = try container.decodeIfPresent(String.self, forKey: .logline) ?? ""
        synopsis = try container.decodeIfPresent(String.self, forKey: .synopsis) ?? ""
        genre = try container.decodeIfPresent(String.self, forKey: .genre) ?? ""
        audience = try container.decodeIfPresent(String.self, forKey: .audience) ?? ""
        status = try container.decodeIfPresent(ProjectStatus.self, forKey: .status) ?? .idea
        targetEpisodeCount = try container.decodeIfPresent(Int.self, forKey: .targetEpisodeCount)
        episodeDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .episodeDurationSeconds)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath)
        knowledgeCollectionIDs = try container.decodeIfPresent([UUID].self, forKey: .knowledgeCollectionIDs) ?? []
        knowledgeDocumentIDs = try container.decodeIfPresent([UUID].self, forKey: .knowledgeDocumentIDs) ?? []
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, logline, synopsis, genre, audience, status
        case targetEpisodeCount, episodeDurationSeconds, notes, folderPath
        case knowledgeCollectionIDs, knowledgeDocumentIDs
        case sortOrder, createdAt, updatedAt
    }

    /// 是否绑定了外部素材文件夹。
    var isExternalFolder: Bool {
        !(folderPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// 单集时长的界面文案（如 `90 秒`）。
    var episodeDurationDisplay: String? {
        guard let seconds = episodeDurationSeconds, seconds > 0 else { return nil }
        if seconds % 60 == 0 {
            return "\(seconds / 60) 分钟"
        }
        return "\(seconds) 秒"
    }

    /// 相对时间（如「18 小时前」）。
    var relativeUpdatedText: String {
        Self.relativeFormatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    /// 卡片标题旁的本地时间戳。
    var cardTimestampText: String {
        Self.cardTimestampFormatter.string(from: updatedAt)
    }

    /// 复用格式化器，避免卡片网格每次 body 都 new DateFormatter。
    /// Foundation 的 Formatter 不是 Sendable，这里仅作只读缓存。
    nonisolated(unsafe) private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    nonisolated private static let cardTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM/dd HH:mm"
        return f
    }()
}
