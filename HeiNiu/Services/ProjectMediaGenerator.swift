/// 项目分镜卡片的参考图与视频生成协调器。

import Foundation
import Observation

/// 一次项目参考图生成的已确认配置。
struct ProjectImageGenerationConfiguration: Hashable, Sendable {
    var providerID: UUID
    var model: String
    var size: String
    var prompt: String
}

/// 一次项目视频生成的已确认配置。
struct ProjectVideoGenerationConfiguration: Hashable, Sendable {
    var providerID: UUID
    var model: String
    var aspectRatio: String
    var resolution: String
    var durationSeconds: Int
    var includeAudio: Bool
}

/// 复用全局媒体适配器，为单个项目镜头执行可取消的生成任务。
@Observable
@MainActor
final class ProjectMediaGenerator {
    @ObservationIgnored private let registry: MediaAdapterRegistry
    @ObservationIgnored private var imageTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var videoTasks: [UUID: Task<Void, Never>] = [:]

    /// 创建生成协调器；测试可注入适配器注册表。
    init(registry: MediaAdapterRegistry = .shared) {
        self.registry = registry
    }

    /// 生成一张参考图并追加到镜头，文件写入关联工作流运行的 `Assets/`。
    func generateReferenceImage(
        projectID: UUID,
        shotID: UUID,
        configuration: ProjectImageGenerationConfiguration,
        settings: SettingsStore,
        workflowStore: WorkflowStore,
        projectStore: ProjectStore
    ) {
        cancelReferenceImage(shotID: shotID, projectID: projectID, projectStore: projectStore, markCancelled: false)
        guard let project = projectStore.project(id: projectID),
              let runID = project.workflowRunID,
              let shot = project.storyboardShots.first(where: { $0.id == shotID }),
              shot.referenceImages.count < 9,
              let provider = settings.imageProvider(id: configuration.providerID),
              let adapter = registry.imageAdapter(id: provider.adapterID)
        else {
            projectStore.finishReferenceGeneration(
                projectID: projectID,
                shotID: shotID,
                status: .failed,
                message: "缺少关联运行、参考图已满或生图服务商无效"
            )
            return
        }

        let prompt = configuration.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !model.isEmpty else {
            projectStore.finishReferenceGeneration(
                projectID: projectID,
                shotID: shotID,
                status: .failed,
                message: "提示词和生图模型不能为空"
            )
            return
        }

        let apiKey = settings.imageAPIKey(for: provider.id)
        guard !apiKey.isEmpty else {
            projectStore.finishReferenceGeneration(
                projectID: projectID,
                shotID: shotID,
                status: .failed,
                message: "生图服务商尚未配置 API Key"
            )
            return
        }

        let outputDirectory = workflowStore.assetsDirectory(workflowID: project.workflowID, runID: runID)
        projectStore.beginReferenceGeneration(projectID: projectID, shotID: shotID)
        imageTasks[shotID] = Task { [weak self] in
            do {
                let artifact = try await adapter.generate(
                    request: ImageGenerationRequest(
                        prompt: prompt,
                        model: model,
                        size: configuration.size.isEmpty ? provider.defaultSize : configuration.size
                    ),
                    provider: provider,
                    apiKey: apiKey,
                    outputDirectory: outputDirectory
                ) { event in
                    await MainActor.run {
                        projectStore.updateReferenceGeneration(
                            projectID: projectID,
                            shotID: shotID,
                            progress: event.fraction,
                            message: event.message
                        )
                    }
                }
                try Task.checkCancellation()
                projectStore.addReferenceImages(
                    projectID: projectID,
                    shotID: shotID,
                    relativePaths: ["Assets/\(artifact.fileURL.lastPathComponent)"],
                    source: .generated
                )
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                projectStore.finishReferenceGeneration(
                    projectID: projectID,
                    shotID: shotID,
                    status: cancelled ? .cancelled : .failed,
                    message: cancelled ? "参考图生成已取消" : error.localizedDescription
                )
            }
            self?.imageTasks[shotID] = nil
        }
    }

    /// 取消一个镜头正在执行的参考图生成。
    func cancelReferenceImage(
        shotID: UUID,
        projectID: UUID,
        projectStore: ProjectStore,
        markCancelled: Bool = true
    ) {
        guard let task = imageTasks.removeValue(forKey: shotID) else { return }
        task.cancel()
        if markCancelled {
            projectStore.finishReferenceGeneration(
                projectID: projectID,
                shotID: shotID,
                status: .cancelled,
                message: "参考图生成已取消"
            )
        }
    }

    /// 按已确认配置生成镜头视频，参考图最多使用适配器允许的数量。
    func generateVideo(
        projectID: UUID,
        shotID: UUID,
        configuration: ProjectVideoGenerationConfiguration,
        settings: SettingsStore,
        workflowStore: WorkflowStore,
        projectStore: ProjectStore
    ) {
        cancelVideo(shotID: shotID, projectID: projectID, projectStore: projectStore, markCancelled: false)
        guard let project = projectStore.project(id: projectID),
              let runID = project.workflowRunID,
              let shot = project.storyboardShots.first(where: { $0.id == shotID }),
              let provider = settings.videoProvider(id: configuration.providerID),
              let adapter = registry.videoAdapter(id: provider.adapterID)
        else {
            projectStore.finishVideoGeneration(
                projectID: projectID,
                shotID: shotID,
                status: .failed,
                message: "缺少关联运行或有效生视频服务商"
            )
            return
        }

        let prompt = shot.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !model.isEmpty else {
            projectStore.finishVideoGeneration(
                projectID: projectID,
                shotID: shotID,
                status: .failed,
                message: "提示词和视频模型不能为空"
            )
            return
        }

        let apiKey = settings.videoAPIKey(for: provider.id)
        if provider.kind != .pixmax, apiKey.isEmpty {
            projectStore.finishVideoGeneration(
                projectID: projectID,
                shotID: shotID,
                status: .failed,
                message: "生视频服务商尚未配置 API Key"
            )
            return
        }

        let descriptor = adapter.descriptor
        let capability = descriptor.videoCapability(for: model)
        let maximumReferences = capability?.maximumReferenceImages ?? descriptor.maximumReferenceImages
        let referenceURLs = shot.referenceImages.compactMap {
            workflowStore.artifactURL(
                relativePath: $0.relativePath,
                workflowID: project.workflowID,
                runID: runID
            )
        }.prefix(max(0, maximumReferences))
        let outputDirectory = workflowStore.assetsDirectory(workflowID: project.workflowID, runID: runID)

        projectStore.beginVideoGeneration(projectID: projectID, shotID: shotID)
        videoTasks[shotID] = Task { [weak self] in
            do {
                let artifact = try await adapter.generate(
                    request: VideoGenerationRequest(
                        prompt: prompt,
                        model: model,
                        aspectRatio: configuration.aspectRatio,
                        resolution: configuration.resolution,
                        durationSeconds: configuration.durationSeconds,
                        includeAudio: configuration.includeAudio,
                        referenceImageURLs: Array(referenceURLs)
                    ),
                    provider: provider,
                    apiKey: apiKey,
                    outputDirectory: outputDirectory
                ) { event in
                    await MainActor.run {
                        projectStore.updateVideoGeneration(
                            projectID: projectID,
                            shotID: shotID,
                            progress: event.fraction,
                            message: event.message
                        )
                    }
                }
                try Task.checkCancellation()
                projectStore.completeVideoGeneration(
                    projectID: projectID,
                    shotID: shotID,
                    relativePath: "Assets/\(artifact.fileURL.lastPathComponent)",
                    aspectRatio: configuration.aspectRatio,
                    durationSeconds: configuration.durationSeconds
                )
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                projectStore.finishVideoGeneration(
                    projectID: projectID,
                    shotID: shotID,
                    status: cancelled ? .cancelled : .failed,
                    message: cancelled ? "视频生成已取消；远端任务可能仍在继续" : error.localizedDescription
                )
            }
            self?.videoTasks[shotID] = nil
        }
    }

    /// 取消一个镜头正在执行的视频生成。
    func cancelVideo(
        shotID: UUID,
        projectID: UUID,
        projectStore: ProjectStore,
        markCancelled: Bool = true
    ) {
        guard let task = videoTasks.removeValue(forKey: shotID) else { return }
        task.cancel()
        if markCancelled {
            projectStore.finishVideoGeneration(
                projectID: projectID,
                shotID: shotID,
                status: .cancelled,
                message: "视频生成已取消；远端任务可能仍在继续"
            )
        }
    }

    /// 取消当前界面启动的全部媒体任务。
    func cancelAll(projectID: UUID, projectStore: ProjectStore) {
        for shotID in Array(imageTasks.keys) {
            cancelReferenceImage(shotID: shotID, projectID: projectID, projectStore: projectStore)
        }
        for shotID in Array(videoTasks.keys) {
            cancelVideo(shotID: shotID, projectID: projectID, projectStore: projectStore)
        }
    }
}
