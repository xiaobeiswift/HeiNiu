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

    @ObservationIgnored private let debouncer = DebouncedAction()
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
        case .waitingForKnowledge:
            projects[index].status = .awaitingKnowledge
            projects[index].lastError = run.pendingKnowledgeGaps
                .map { "\($0.requirement.category.title)：\($0.requirement.name)" }
                .joined(separator: "；")
        case .succeeded, .warning:
            if ![.awaitingReview, .approved].contains(previousStatus) {
                projects[index].storyboardDraft = Self.storyboardText(from: run, workflow: workflow)
                let parsed = Self.storyboardShots(
                    from: projects[index].storyboardDraft,
                    run: run
                )
                projects[index].storyboardShots = parsed.shots
                for warning in parsed.warnings where !projects[index].runWarnings.contains(warning) {
                    projects[index].runWarnings.append(warning)
                }
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
            project.storyboardShots = Self.storyboardShots(from: storyboard)
            project.reviewNotes = notes
            project.status = .awaitingReview
        }
    }

    /// 保存分镜与审核意见并标记审核通过。
    func approve(projectID: UUID, storyboard: String, notes: String) {
        mutate(projectID: projectID) { project in
            project.storyboardDraft = storyboard
            if project.storyboardShots.isEmpty || Self.storyboardText(from: project.storyboardShots) != storyboard {
                project.storyboardShots = Self.storyboardShots(from: storyboard)
            }
            project.reviewNotes = notes
            project.status = .approved
        }
    }

    /// 保存卡片式分镜的审核意见，并保持待审核状态。
    func saveStoryboardReview(projectID: UUID, notes: String) {
        mutate(projectID: projectID) { project in
            project.reviewNotes = notes
            project.storyboardDraft = Self.storyboardText(from: project.storyboardShots)
            project.status = .awaitingReview
        }
    }

    /// 保存卡片式分镜并标记审核通过。
    func approveStoryboardReview(projectID: UUID, notes: String) {
        mutate(projectID: projectID) { project in
            project.reviewNotes = notes
            project.storyboardDraft = Self.storyboardText(from: project.storyboardShots)
            project.status = .approved
        }
    }

    /// 新增一个空白分镜卡片。
    @discardableResult
    func addStoryboardShot(projectID: UUID) -> UUID? {
        var newID: UUID?
        mutate(projectID: projectID) { project in
            let order = project.storyboardShots.count + 1
            let shot = ProjectStoryboardShot(
                order: order,
                title: "新分镜",
                prompt: ""
            )
            newID = shot.id
            project.storyboardShots.append(shot)
            project.storyboardDraft = Self.storyboardText(from: project.storyboardShots)
            project.status = .awaitingReview
        }
        return newID
    }

    /// 删除一个分镜卡片并重新编号。
    func deleteStoryboardShot(projectID: UUID, shotID: UUID) {
        mutate(projectID: projectID) { project in
            project.storyboardShots.removeAll { $0.id == shotID }
            Self.renumber(&project.storyboardShots)
            project.storyboardDraft = Self.storyboardText(from: project.storyboardShots)
            project.status = .awaitingReview
        }
    }

    /// 更新一个镜头共用的生成提示词；磁盘写入使用防抖。
    func updateStoryboardPrompt(projectID: UUID, shotID: UUID, prompt: String) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
              let shotIndex = projects[projectIndex].storyboardShots.firstIndex(where: { $0.id == shotID })
        else { return }
        projects[projectIndex].storyboardShots[shotIndex].prompt = prompt
        projects[projectIndex].storyboardShots[shotIndex].updatedAt = Date()
        projects[projectIndex].storyboardDraft = Self.storyboardText(from: projects[projectIndex].storyboardShots)
        projects[projectIndex].status = .awaitingReview
        projects[projectIndex].updatedAt = Date()
        sortProjects()
        debouncer.schedule { [weak self] in self?.saveNow() }
    }

    /// 给镜头追加已复制到运行目录的参考图片。
    func addReferenceImages(
        projectID: UUID,
        shotID: UUID,
        relativePaths: [String],
        source: ProjectReferenceImageSource
    ) {
        mutateShot(projectID: projectID, shotID: shotID) { shot in
            let remaining = max(0, 9 - shot.referenceImages.count)
            for path in relativePaths.prefix(remaining) where !path.isEmpty {
                guard !shot.referenceImages.contains(where: { $0.relativePath == path }) else { continue }
                shot.referenceImages.append(ProjectReferenceImage(
                    name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                    relativePath: path,
                    source: source
                ))
            }
            shot.referenceGenerationStatus = .succeeded
            shot.referenceGenerationProgress = 1
            shot.referenceGenerationMessage = "参考图片已加入"
        }
    }

    /// 从镜头解除一张参考图片；不会删除运行目录中的原文件。
    func removeReferenceImage(projectID: UUID, shotID: UUID, referenceID: UUID) {
        mutateShot(projectID: projectID, shotID: shotID) { shot in
            shot.referenceImages.removeAll { $0.id == referenceID }
            if shot.referenceImages.isEmpty {
                shot.referenceGenerationStatus = .idle
                shot.referenceGenerationProgress = nil
                shot.referenceGenerationMessage = nil
            }
        }
    }

    /// 记录参考图生成开始。
    func beginReferenceGeneration(projectID: UUID, shotID: UUID) {
        mutateShot(projectID: projectID, shotID: shotID) { shot in
            shot.referenceGenerationStatus = .generating
            shot.referenceGenerationProgress = nil
            shot.referenceGenerationMessage = "正在生成参考图"
        }
    }

    /// 更新参考图生成进度。
    func updateReferenceGeneration(
        projectID: UUID,
        shotID: UUID,
        progress: Double?,
        message: String
    ) {
        mutateShot(projectID: projectID, shotID: shotID, saveImmediately: false) { shot in
            shot.referenceGenerationStatus = .generating
            shot.referenceGenerationProgress = progress
            shot.referenceGenerationMessage = message
        }
    }

    /// 记录参考图生成失败或取消。
    func finishReferenceGeneration(
        projectID: UUID,
        shotID: UUID,
        status: ProjectMediaStatus,
        message: String
    ) {
        mutateShot(projectID: projectID, shotID: shotID) { shot in
            shot.referenceGenerationStatus = status
            shot.referenceGenerationProgress = status == .succeeded ? 1 : nil
            shot.referenceGenerationMessage = message
        }
    }

    /// 记录视频生成开始。
    func beginVideoGeneration(projectID: UUID, shotID: UUID) {
        mutateShot(projectID: projectID, shotID: shotID) { shot in
            shot.videoStatus = .generating
            shot.videoProgress = 0
            shot.videoMessage = "正在提交视频任务"
        }
    }

    /// 更新视频生成进度。
    func updateVideoGeneration(
        projectID: UUID,
        shotID: UUID,
        progress: Double?,
        message: String
    ) {
        mutateShot(projectID: projectID, shotID: shotID, saveImmediately: false) { shot in
            shot.videoStatus = .generating
            shot.videoProgress = progress
            shot.videoMessage = message
        }
    }

    /// 保存生成完成的视频相对路径。
    func completeVideoGeneration(
        projectID: UUID,
        shotID: UUID,
        relativePath: String,
        aspectRatio: String,
        durationSeconds: Int
    ) {
        mutateShot(projectID: projectID, shotID: shotID) { shot in
            shot.videoRelativePath = relativePath
            shot.videoStatus = .succeeded
            shot.videoProgress = 1
            shot.videoMessage = "视频已保存"
            shot.videoAspectRatio = aspectRatio
            shot.durationSeconds = max(1, durationSeconds)
        }
    }

    /// 记录视频生成失败或取消。
    func finishVideoGeneration(
        projectID: UUID,
        shotID: UUID,
        status: ProjectMediaStatus,
        message: String
    ) {
        mutateShot(projectID: projectID, shotID: shotID) { shot in
            shot.videoStatus = status
            shot.videoProgress = nil
            shot.videoMessage = message
        }
    }

    /// 删除项目卡片；关联的全局工作流运行历史仍保留。
    func deleteProject(id: UUID) {
        projects.removeAll { $0.id == id }
        saveNow()
    }

    /// 立即原子保存全部项目。
    func saveNow() {
        debouncer.cancel()
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

    /// 把整段分镜文本容错拆分为可编辑卡片。
    static func storyboardShots(from storyboard: String) -> [ProjectStoryboardShot] {
        let clean = storyboard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }

        let lines = clean.components(separatedBy: .newlines)
        var blocks: [[String]] = []
        var current: [String] = []
        var foundShot = false
        for line in lines {
            if isShotStart(line) {
                if foundShot, !current.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(current)
                }
                current = []
                foundShot = true
            }
            current.append(line)
        }
        if !current.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(current)
        }
        if blocks.isEmpty { blocks = [lines] }

        return blocks.enumerated().map { offset, block in
            let prompt = block
                .filter { !isReferenceMetadataLine($0) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ProjectStoryboardShot(
                order: offset + 1,
                title: shotTitle(from: block, order: offset + 1),
                durationSeconds: shotDuration(from: prompt),
                prompt: prompt
            )
        }
    }

    /// 把卡片提示词合并回兼容旧版的分镜草稿。
    static func storyboardText(from shots: [ProjectStoryboardShot]) -> String {
        shots.sorted { $0.order < $1.order }
            .map { $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func mutate(projectID: UUID, _ mutation: (inout ProjectRecord) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        mutation(&projects[index])
        projects[index].updatedAt = Date()
        sortProjects()
        saveNow()
    }

    private func mutateShot(
        projectID: UUID,
        shotID: UUID,
        saveImmediately: Bool = true,
        _ mutation: (inout ProjectStoryboardShot) -> Void
    ) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
              let shotIndex = projects[projectIndex].storyboardShots.firstIndex(where: { $0.id == shotID })
        else { return }
        mutation(&projects[projectIndex].storyboardShots[shotIndex])
        projects[projectIndex].storyboardShots[shotIndex].updatedAt = Date()
        projects[projectIndex].storyboardDraft = Self.storyboardText(from: projects[projectIndex].storyboardShots)
        projects[projectIndex].status = .awaitingReview
        projects[projectIndex].updatedAt = Date()
        sortProjects()
        if saveImmediately {
            saveNow()
        } else {
            debouncer.schedule { [weak self] in self?.saveNow() }
        }
    }

    private func sortProjects() {
        projects.sort { $0.updatedAt > $1.updatedAt }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            projects = try decoder.decode(ProjectFile.self, from: data).projects
            var repairedData = false
            for index in projects.indices {
                if projects[index].formatVersion < ProjectRecord.currentFormatVersion {
                    projects[index].formatVersion = ProjectRecord.currentFormatVersion
                    repairedData = true
                }
                if projects[index].status == .running {
                    projects[index].status = .failed
                    projects[index].lastError = "上次运行未正常结束，请重新运行"
                    projects[index].updatedAt = Date()
                    repairedData = true
                }
                if projects[index].storyboardShots.isEmpty,
                   !projects[index].storyboardDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    projects[index].storyboardShots = Self.storyboardShots(from: projects[index].storyboardDraft)
                    repairedData = true
                }
                for shotIndex in projects[index].storyboardShots.indices {
                    if projects[index].storyboardShots[shotIndex].referenceGenerationStatus == .generating {
                        projects[index].storyboardShots[shotIndex].referenceGenerationStatus = .failed
                        projects[index].storyboardShots[shotIndex].referenceGenerationMessage = "上次参考图生成未正常结束"
                        repairedData = true
                    }
                    if projects[index].storyboardShots[shotIndex].videoStatus == .generating {
                        projects[index].storyboardShots[shotIndex].videoStatus = .failed
                        projects[index].storyboardShots[shotIndex].videoMessage = "上次视频生成未正常结束"
                        repairedData = true
                    }
                }
            }
            sortProjects()
            if repairedData { saveNow() }
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

    private static func storyboardShots(
        from storyboard: String,
        run: WorkflowRun
    ) -> (shots: [ProjectStoryboardShot], warnings: [String]) {
        var shots = storyboardShots(from: storyboard)
        guard !shots.isEmpty else { return ([], []) }
        var mappingWarnings: [String] = []

        let manifest = referenceManifest(from: run)
        if !manifest.entries.isEmpty {
            let requestedIDs = referenceIDsByShot(from: storyboard)
            var entriesByID: [String: WorkflowReferenceManifestEntry] = [:]
            for entry in manifest.entries where entriesByID[entry.referenceID.uppercased()] == nil {
                entriesByID[entry.referenceID.uppercased()] = entry
            }
            for index in shots.indices {
                let requested = index < requestedIDs.count ? requestedIDs[index] : []
                let valid = requested.compactMap { entriesByID[$0.uppercased()] }
                let selected: [WorkflowReferenceManifestEntry]
                if requested.isEmpty || valid.count != requested.count {
                    selected = Array(manifest.entries.prefix(9))
                    mappingWarnings.append("镜头 \(index + 1) 未声明完整有效参考资料，已使用本次有效参考包兜底")
                } else {
                    selected = Array(valid.prefix(9))
                }
                shots[index].referenceImages = selected.map { entry in
                    ProjectReferenceImage(
                        name: entry.title,
                        relativePath: entry.relativePath,
                        source: .knowledge
                    )
                }
                if !shots[index].referenceImages.isEmpty {
                    shots[index].referenceGenerationStatus = .succeeded
                    shots[index].referenceGenerationProgress = 1
                    shots[index].referenceGenerationMessage = "来自知识库参考包"
                }
            }
        }

        let images = mediaPaths(from: run, type: .image)
        for (index, path) in images.enumerated() {
            let shotIndex = index % shots.count
            guard shots[shotIndex].referenceImages.count < 9 else { continue }
            shots[shotIndex].referenceImages.append(ProjectReferenceImage(
                name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                relativePath: path,
                source: .workflow
            ))
        }

        let videos = mediaPaths(from: run, type: .video)
        for (index, path) in videos.enumerated() {
            let shotIndex = index % shots.count
            shots[shotIndex].videoRelativePath = path
            shots[shotIndex].videoStatus = .succeeded
            shots[shotIndex].videoProgress = 1
            shots[shotIndex].videoMessage = "来自工作流运行"
        }
        return (shots, Array(Set(mappingWarnings)).sorted())
    }

    private static func referenceManifest(from run: WorkflowRun) -> WorkflowReferenceManifest {
        for nodeRun in run.nodeRuns.reversed() {
            guard case .text(let text) = nodeRun.outputs["referenceManifest"],
                  let data = text.data(using: .utf8),
                  let manifest = try? JSONDecoder().decode(WorkflowReferenceManifest.self, from: data)
            else { continue }
            return manifest
        }
        return WorkflowReferenceManifest(entries: [])
    }

    private static func referenceIDsByShot(from storyboard: String) -> [[String]] {
        let lines = storyboard.components(separatedBy: .newlines)
        var result: [[String]] = []
        var current: [String] = []
        var foundShot = false
        for line in lines {
            if isShotStart(line) {
                if foundShot { result.append(referenceIDs(in: current)) }
                current = []
                foundShot = true
            }
            current.append(line)
        }
        if !current.isEmpty { result.append(referenceIDs(in: current)) }
        return result
    }

    private static func referenceIDs(in lines: [String]) -> [String] {
        guard let line = lines.first(where: isReferenceMetadataLine),
              let separator = line.firstIndex(where: { $0 == "：" || $0 == ":" })
        else { return [] }
        return line[line.index(after: separator)...]
            .split(whereSeparator: { ",，、;； \t".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isReferenceMetadataLine(_ line: String) -> Bool {
        let clean = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[#\-*•\s]+"#, with: "", options: .regularExpression)
        return clean.hasPrefix("参考资料：") || clean.hasPrefix("参考资料:")
    }

    private static func mediaPaths(from run: WorkflowRun, type: WorkflowValueType) -> [String] {
        var result: [String] = []
        for nodeRun in run.nodeRuns {
            for key in nodeRun.outputs.keys.sorted() {
                guard let value = nodeRun.outputs[key], value.valueType == type else { continue }
                let path = value.payload.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty, !result.contains(path) { result.append(path) }
            }
        }
        return result
    }

    private static func isShotStart(_ line: String) -> Bool {
        var value = line.trimmingCharacters(in: .whitespaces)
        while let first = value.first, "#-*•".contains(first) {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespaces)
        }
        let patterns = [
            #"^(镜头|镜号|分镜)\s*(编号)?\s*[：:#\-]?\s*[0-9一二三四五六七八九十百]+"#,
            #"^[0-9]+\s*[、.．):：]\s*"#,
        ]
        return patterns.contains { value.range(of: $0, options: .regularExpression) != nil }
    }

    private static func shotTitle(from lines: [String], order: Int) -> String {
        for line in lines {
            let clean = line
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^[#\-*•\s]+"#, with: "", options: .regularExpression)
            for key in ["画面描述", "画面", "场景"] {
                for separator in ["\(key)：", "\(key):"] {
                    if let range = clean.range(of: separator) {
                        let value = clean[range.upperBound...].trimmingCharacters(in: .whitespaces)
                        if !value.isEmpty { return String(value.prefix(24)) }
                    }
                }
            }
        }
        for line in lines {
            let clean = line
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^[#\-*•\s]+"#, with: "", options: .regularExpression)
            guard !clean.isEmpty else { continue }
            let withoutIndex = clean.replacingOccurrences(
                of: #"^(镜头|镜号|分镜)?\s*(编号)?\s*[：:#\-]?\s*[0-9一二三四五六七八九十百]+\s*[、.．):：\-]?\s*"#,
                with: "",
                options: .regularExpression
            )
            if !withoutIndex.isEmpty { return String(withoutIndex.prefix(24)) }
        }
        return "分镜 \(order)"
    }

    private static func shotDuration(from text: String) -> Int {
        guard let range = text.range(of: #"[0-9]+(?:\.[0-9]+)?\s*(秒|s)"#, options: [.regularExpression, .caseInsensitive]) else {
            return 4
        }
        let value = text[range]
            .replacingOccurrences(of: "秒", with: "")
            .replacingOccurrences(of: "s", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        return max(1, Int((Double(value) ?? 4).rounded()))
    }

    private static func renumber(_ shots: inout [ProjectStoryboardShot]) {
        for index in shots.indices { shots[index].order = index + 1 }
    }
}

/// 项目持久化文件包装，便于后续格式升级。
private struct ProjectFile: Codable {
    var formatVersion: Int
    var projects: [ProjectRecord]

    init(projects: [ProjectRecord]) {
        formatVersion = ProjectRecord.currentFormatVersion
        self.projects = projects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = max(
            ProjectRecord.currentFormatVersion,
            try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        )
        projects = try container.decodeIfPresent([ProjectRecord].self, forKey: .projects) ?? []
    }
}
