/// 项目卡片与分镜审核内容的本地持久化仓库。

import Foundation
import Observation

/// 全局项目仓库。
@Observable
@MainActor
final class ProjectStore {
    /// 项目卡片，最近更新的项目在前。
    var projects: [ProjectRecord] = []
    /// 最近一次持久化错误。
    var lastError: String?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    @ObservationIgnored private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// 加载项目；测试可注入隔离目录。
    init(rootURL: URL? = nil) {
        let root = rootURL ?? AppPaths.projectsRoot
        fileURL = root.appendingPathComponent("project-board.json", isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            lastError = error.localizedDescription
        }
        load()
    }

    /// 按 ID 查找项目。
    func project(id: UUID?) -> ProjectRecord? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    /// 创建项目并进入运行中状态。
    @discardableResult
    func createProject(name: String, workflow: WorkflowDefinition) -> UUID {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = ProjectRecord(
            name: cleanName.isEmpty ? "未命名项目" : cleanName,
            workflowID: workflow.id,
            workflowName: workflow.name
        )
        projects.insert(project, at: 0)
        saveNow()
        return project.id
    }

    /// 记录工作流执行器为项目分配的运行 ID。
    func bindRun(projectID: UUID, runID: UUID) {
        mutate(projectID: projectID) { project in
            project.workflowRunID = runID
            project.status = .running
            project.lastError = nil
        }
    }

    /// 把工作流运行快照同步为项目状态；返回是否首次进入分镜审核。
    @discardableResult
    func synchronize(
        projectID: UUID,
        run: WorkflowRun,
        workflow: WorkflowDefinition
    ) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return false }
        guard projects[index].workflowID == run.workflowID else { return false }
        if let linkedRunID = projects[index].workflowRunID, linkedRunID != run.id { return false }

        let previousStatus = projects[index].status
        projects[index].workflowRunID = run.id
        projects[index].runWarnings = run.warnings
        projects[index].updatedAt = Date()

        switch run.status {
        case .running:
            projects[index].status = .running
            projects[index].lastError = nil
        case .succeeded, .warning:
            if ![.awaitingReview, .approved].contains(previousStatus) {
                projects[index].storyboardDraft = Self.storyboardText(from: run, workflow: workflow)
                projects[index].status = .awaitingReview
                projects[index].lastError = nil
            }
        case .failed:
            projects[index].status = .failed
            projects[index].lastError = Self.failureMessage(from: run)
        case .cancelled:
            projects[index].status = .cancelled
            projects[index].lastError = "工作流运行已取消"
        }
        sortProjects()
        saveNow()
        return [.succeeded, .warning].contains(run.status)
            && ![.awaitingReview, .approved].contains(previousStatus)
    }

    /// 记录工作流未能启动。
    func markLaunchFailed(projectID: UUID, message: String) {
        mutate(projectID: projectID) { project in
            project.status = .failed
            project.lastError = message
        }
    }

    /// 为重新运行清空旧运行关联并刷新工作流快照名。
    func prepareForRerun(projectID: UUID, workflow: WorkflowDefinition) {
        mutate(projectID: projectID) { project in
            project.workflowID = workflow.id
            project.workflowName = workflow.name
            project.workflowRunID = nil
            project.status = .running
            project.runWarnings = []
            project.lastError = nil
        }
    }

    /// 保存用户修改后的分镜与审核意见，并回到待审核状态。
    func saveReview(projectID: UUID, storyboard: String, notes: String) {
        mutate(projectID: projectID) { project in
            project.storyboardDraft = storyboard
            project.reviewNotes = notes
            project.status = .awaitingReview
        }
    }

    /// 保存分镜与审核意见并标记审核通过。
    func approve(projectID: UUID, storyboard: String, notes: String) {
        mutate(projectID: projectID) { project in
            project.storyboardDraft = storyboard
            project.reviewNotes = notes
            project.status = .approved
        }
    }

    /// 删除项目卡片；关联的全局工作流运行历史仍保留。
    func deleteProject(id: UUID) {
        projects.removeAll { $0.id == id }
        saveNow()
    }

    /// 立即原子保存全部项目。
    func saveNow() {
        do {
            let data = try encoder.encode(ProjectFile(projects: projects))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 从最终输出节点提取分镜文本；没有文本结果时返回空白草稿。
    static func storyboardText(from run: WorkflowRun, workflow: WorkflowDefinition) -> String {
        let outputNodeIDs = workflow.nodes.filter { $0.kind == .output }.map(\.id)
        let outputTexts = outputNodeIDs.compactMap { nodeID -> String? in
            guard case .text(let text) = run.nodeRun(id: nodeID)?.outputs["value"] else { return nil }
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        }
        return outputTexts.joined(separator: "\n\n")
    }

    private func mutate(projectID: UUID, _ mutation: (inout ProjectRecord) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        mutation(&projects[index])
        projects[index].updatedAt = Date()
        sortProjects()
        saveNow()
    }

    private func sortProjects() {
        projects.sort { $0.updatedAt > $1.updatedAt }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            projects = try decoder.decode(ProjectFile.self, from: data).projects
            var repairedInterruptedRun = false
            for index in projects.indices where projects[index].status == .running {
                projects[index].status = .failed
                projects[index].lastError = "上次运行未正常结束，请重新运行"
                projects[index].updatedAt = Date()
                repairedInterruptedRun = true
            }
            sortProjects()
            if repairedInterruptedRun { saveNow() }
        } catch {
            lastError = error.localizedDescription
            projects = []
        }
    }

    private static func failureMessage(from run: WorkflowRun) -> String {
        if let warning = run.warnings.last, !warning.isEmpty { return warning }
        if let message = run.nodeRuns.reversed().compactMap(\.message).first(where: { !$0.isEmpty }) {
            return message
        }
        return "工作流运行失败"
    }
}

/// 项目持久化文件包装，便于后续格式升级。
private struct ProjectFile: Codable {
    var formatVersion: Int
    var projects: [ProjectRecord]

    init(projects: [ProjectRecord]) {
        formatVersion = 1
        self.projects = projects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = max(1, try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1)
        projects = try container.decodeIfPresent([ProjectRecord].self, forKey: .projects) ?? []
    }
}
