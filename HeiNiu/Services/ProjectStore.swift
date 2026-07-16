/// 短剧项目仓库：立项看板的增删改查与持久化。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation
import Observation

/// 项目数据源。
///
/// - 文件：`projects.json`（``AppPaths/projectsFileURL``）
/// - 流水线：`Projects/<id>/pipeline.json`
/// - 与黑妞/会话独立；删除项目会移除其工作目录。
///
@Observable
@MainActor
final class ProjectStore {
    /// 全部项目。
    var projects: [ProjectItem] = []
    /// 内存中的流水线缓存（按项目 ID）。
    private var pipelineCache: [UUID: ProjectPipeline] = [:]

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        AppPaths.ensureDirectories()
        load()
    }

    /// 排序后的项目：`sortOrder` 升序，同权按 `updatedAt` 新→旧。
    var sortedProjects: [ProjectItem] {
        projects.sorted { a, b in
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.updatedAt > b.updatedAt
        }
    }

    /// 按 ID 查找。
    func project(id: UUID?) -> ProjectItem? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    /// 新建空白项目并落盘。
    ///
    /// - Parameter name: 项目名；空则用「未命名项目」。
    @discardableResult
    func addProject(named name: String = "未命名项目") -> ProjectItem {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = trimmed.isEmpty ? "未命名项目" : trimmed
        let nextOrder = (projects.map(\.sortOrder).max() ?? -1) + 1
        let item = ProjectItem(
            name: display,
            sortOrder: nextOrder
        )
        projects.append(item)
        save()
        return item
    }

    /// 从本地文件夹导入为外部项目（同路径已存在则刷新并返回已有项）。
    @discardableResult
    func importFolder(at url: URL) -> ProjectItem {
        let path = url.standardizedFileURL.path
        if let existing = projects.first(where: { $0.folderPath == path }) {
            var refreshed = existing
            refreshed.updatedAt = Date()
            updateProject(refreshed)
            return refreshed
        }
        let nextOrder = (projects.map(\.sortOrder).max() ?? -1) + 1
        let item = ProjectItem(
            name: url.lastPathComponent,
            logline: "外部文件夹项目",
            notes: "素材目录：\(path)",
            folderPath: path,
            sortOrder: nextOrder
        )
        projects.append(item)
        save()
        return item
    }

    /// 用完整快照覆盖同 ID 项目并刷新 `updatedAt`。
    func updateProject(_ project: ProjectItem) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        var updated = project
        updated.updatedAt = Date()
        projects[index] = updated
        save()
    }

    /// 删除项目及其工作目录。
    func deleteProject(id: UUID) {
        projects.removeAll { $0.id == id }
        pipelineCache[id] = nil
        let dir = AppPaths.projectDirectory(for: id)
        try? FileManager.default.removeItem(at: dir)
        save()
    }

    // MARK: - Pipeline

    /// 读取（或初始化）项目流水线。
    func pipeline(for projectID: UUID) -> ProjectPipeline {
        if let cached = pipelineCache[projectID] {
            return cached
        }
        let loaded = loadPipeline(projectID: projectID)
        pipelineCache[projectID] = loaded
        return loaded
    }

    /// 保存流水线快照。
    func savePipeline(_ pipeline: ProjectPipeline) {
        var pipe = pipeline
        pipe.updatedAt = Date()
        pipelineCache[pipe.projectID] = pipe
        AppPaths.ensureProjectDirectory(for: pipe.projectID)
        do {
            let data = try encoder.encode(pipe)
            try data.write(
                to: AppPaths.projectPipelineFileURL(for: pipe.projectID),
                options: .atomic
            )
        } catch {
            // ignore
        }
    }

    /// 执行一步并落盘（失败也会写入 failed 状态）。
    @discardableResult
    func runPipelineStep(
        _ kind: PipelineStepKind,
        projectID: UUID,
        settings: SettingsStore
    ) async throws -> ProjectPipeline {
        guard let project = project(id: projectID) else {
            throw LLMError.underlying("项目不存在")
        }
        let current = pipeline(for: projectID)
        do {
            let next = try await ProjectPipelineRunner.run(
                step: kind,
                project: project,
                pipeline: current,
                settings: settings
            )
            savePipeline(next)
            // 粗粒度推进项目状态
            advanceProjectStatus(for: projectID, completed: kind)
            return next
        } catch let err as PipelineRunError {
            savePipeline(err.pipeline)
            throw err
        }
    }

    private func advanceProjectStatus(for projectID: UUID, completed kind: PipelineStepKind) {
        guard var project = project(id: projectID) else { return }
        let mapped: ProjectStatus? = {
            switch kind {
            case .script: .writing
            case .segment, .characters, .scenes, .items: .writing
            case .images, .shotPrompts: .storyboard
            case .video: .production
            }
        }()
        guard let mapped else { return }
        // 不自动从归档/完成往回跳
        if project.status == .archived || project.status == .done { return }
        project.status = mapped
        updateProject(project)
    }

    // MARK: - Persistence

    private func load() {
        let url = AppPaths.projectsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            projects = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            projects = try decoder.decode([ProjectItem].self, from: data)
        } catch {
            // 解码失败不覆盖磁盘，避免误删用户数据
            projects = []
        }
    }

    private func save() {
        AppPaths.ensureDirectories()
        do {
            let data = try encoder.encode(projects)
            try data.write(to: AppPaths.projectsFileURL, options: .atomic)
        } catch {
            // ignore disk errors for now
        }
    }

    private func loadPipeline(projectID: UUID) -> ProjectPipeline {
        let url = AppPaths.projectPipelineFileURL(for: projectID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ProjectPipeline(projectID: projectID)
        }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(ProjectPipeline.self, from: data)
        } catch {
            return ProjectPipeline(projectID: projectID)
        }
    }
}
