/// 项目卡片、工作流运行关联与分镜审核状态。

import Foundation

/// 项目从创建到分镜审核的生命周期状态。
enum ProjectStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case running
    case awaitingKnowledge
    case awaitingReview
    case approved
    case failed
    case cancelled

    /// 中文状态标题。
    var title: String {
        switch self {
        case .running: "运行中"
        case .awaitingKnowledge: "待补资料"
        case .awaitingReview: "待审核"
        case .approved: "已通过"
        case .failed: "运行失败"
        case .cancelled: "已取消"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .failed
    }
}

/// 项目镜头中的媒体生成状态。
enum ProjectMediaStatus: String, Codable, Hashable, Sendable {
    case idle
    case generating
    case succeeded
    case failed
    case cancelled

    /// 中文状态标题。
    var title: String {
        switch self {
        case .idle: "待生成"
        case .generating: "生成中"
        case .succeeded: "已生成"
        case .failed: "生成失败"
        case .cancelled: "已取消"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .idle
    }
}

/// 参考图片进入镜头的来源。
enum ProjectReferenceImageSource: String, Codable, Hashable, Sendable {
    case workflow
    case knowledge
    case imported
    case generated

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .imported
    }
}

/// 一个镜头关联的本地参考图片。
struct ProjectReferenceImage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// 相对于关联工作流运行根目录的路径，例如 `Assets/frame.png`。
    var relativePath: String
    var source: ProjectReferenceImageSource
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        relativePath: String,
        source: ProjectReferenceImageSource,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.source = source
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "参考图片"
        relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath) ?? ""
        source = (try? container.decodeIfPresent(ProjectReferenceImageSource.self, forKey: .source)) ?? .imported
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// 一张可独立审核、配置参考图并生成视频的分镜卡片。
struct ProjectStoryboardShot: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var order: Int
    var title: String
    var durationSeconds: Int
    var prompt: String
    var referenceImages: [ProjectReferenceImage]
    var referenceGenerationStatus: ProjectMediaStatus
    var referenceGenerationProgress: Double?
    var referenceGenerationMessage: String?
    /// 相对于关联工作流运行根目录的视频路径。
    var videoRelativePath: String?
    var videoStatus: ProjectMediaStatus
    var videoProgress: Double?
    var videoMessage: String?
    var videoAspectRatio: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        order: Int,
        title: String,
        durationSeconds: Int = 4,
        prompt: String,
        referenceImages: [ProjectReferenceImage] = [],
        referenceGenerationStatus: ProjectMediaStatus = .idle,
        referenceGenerationProgress: Double? = nil,
        referenceGenerationMessage: String? = nil,
        videoRelativePath: String? = nil,
        videoStatus: ProjectMediaStatus = .idle,
        videoProgress: Double? = nil,
        videoMessage: String? = nil,
        videoAspectRatio: String = "9:16",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.durationSeconds = durationSeconds
        self.prompt = prompt
        self.referenceImages = referenceImages
        self.referenceGenerationStatus = referenceGenerationStatus
        self.referenceGenerationProgress = referenceGenerationProgress
        self.referenceGenerationMessage = referenceGenerationMessage
        self.videoRelativePath = videoRelativePath
        self.videoStatus = videoStatus
        self.videoProgress = videoProgress
        self.videoMessage = videoMessage
        self.videoAspectRatio = videoAspectRatio
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        order = max(1, try container.decodeIfPresent(Int.self, forKey: .order) ?? 1)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "分镜 \(order)"
        durationSeconds = max(1, try container.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 4)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        referenceImages = try container.decodeIfPresent([ProjectReferenceImage].self, forKey: .referenceImages) ?? []
        referenceGenerationStatus = (try? container.decodeIfPresent(ProjectMediaStatus.self, forKey: .referenceGenerationStatus)) ?? .idle
        referenceGenerationProgress = try container.decodeIfPresent(Double.self, forKey: .referenceGenerationProgress)
        referenceGenerationMessage = try container.decodeIfPresent(String.self, forKey: .referenceGenerationMessage)
        videoRelativePath = try container.decodeIfPresent(String.self, forKey: .videoRelativePath)
        videoStatus = (try? container.decodeIfPresent(ProjectMediaStatus.self, forKey: .videoStatus))
            ?? (videoRelativePath == nil ? .idle : .succeeded)
        videoProgress = try container.decodeIfPresent(Double.self, forKey: .videoProgress)
        videoMessage = try container.decodeIfPresent(String.self, forKey: .videoMessage)
        videoAspectRatio = try container.decodeIfPresent(String.self, forKey: .videoAspectRatio) ?? "9:16"
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

/// 一个项目卡片及其分镜审核内容。
struct ProjectRecord: Identifiable, Codable, Hashable, Sendable {
    var formatVersion: Int
    var id: UUID
    var name: String
    var workflowID: UUID
    var workflowName: String
    var workflowRunID: UUID?
    var status: ProjectStatus
    var storyboardDraft: String
    var storyboardShots: [ProjectStoryboardShot]
    var reviewNotes: String
    var runWarnings: [String]
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    /// 当前项目格式版本。
    static let currentFormatVersion = 2

    /// 创建一个等待工作流启动的新项目。
    init(
        id: UUID = UUID(),
        name: String,
        workflowID: UUID,
        workflowName: String,
        workflowRunID: UUID? = nil,
        status: ProjectStatus = .running,
        storyboardDraft: String = "",
        storyboardShots: [ProjectStoryboardShot] = [],
        reviewNotes: String = "",
        runWarnings: [String] = [],
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        formatVersion = Self.currentFormatVersion
        self.id = id
        self.name = name
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.workflowRunID = workflowRunID
        self.status = status
        self.storyboardDraft = storyboardDraft
        self.storyboardShots = storyboardShots
        self.reviewNotes = reviewNotes
        self.runWarnings = runWarnings
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = max(
            Self.currentFormatVersion,
            try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        )
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名项目"
        workflowID = try container.decodeIfPresent(UUID.self, forKey: .workflowID) ?? UUID()
        workflowName = try container.decodeIfPresent(String.self, forKey: .workflowName) ?? "未知工作流"
        workflowRunID = try container.decodeIfPresent(UUID.self, forKey: .workflowRunID)
        status = (try? container.decodeIfPresent(ProjectStatus.self, forKey: .status)) ?? .failed
        storyboardDraft = try container.decodeIfPresent(String.self, forKey: .storyboardDraft) ?? ""
        storyboardShots = try container.decodeIfPresent([ProjectStoryboardShot].self, forKey: .storyboardShots) ?? []
        reviewNotes = try container.decodeIfPresent(String.self, forKey: .reviewNotes) ?? ""
        runWarnings = try container.decodeIfPresent([String].self, forKey: .runWarnings) ?? []
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}
