/// 项目卡片、工作流运行关联与分镜审核状态。

import Foundation

/// 项目从创建到分镜审核的生命周期状态。
enum ProjectStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case running
    case awaitingReview
    case approved
    case failed
    case cancelled

    /// 中文状态标题。
    var title: String {
        switch self {
        case .running: "运行中"
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
    var reviewNotes: String
    var runWarnings: [String]
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    /// 当前项目格式版本。
    static let currentFormatVersion = 1

    /// 创建一个等待工作流启动的新项目。
    init(
        id: UUID = UUID(),
        name: String,
        workflowID: UUID,
        workflowName: String,
        workflowRunID: UUID? = nil,
        status: ProjectStatus = .running,
        storyboardDraft: String = "",
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
        reviewNotes = try container.decodeIfPresent(String.self, forKey: .reviewNotes) ?? ""
        runWarnings = try container.decodeIfPresent([String].self, forKey: .runWarnings) ?? []
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}
