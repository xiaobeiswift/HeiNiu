/// 卡片式分镜审核、参考图管理与单镜头媒体生成。

import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

/// 一个项目的卡片式分镜审核内容。
struct StoryboardReviewView: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorkflowStore.self) private var workflowStore
    @Environment(SettingsStore.self) private var settings
    @Environment(ProjectMediaGenerator.self) private var mediaGenerator

    let projectID: UUID
    let onRerun: () -> Void

    @State private var notes = ""
    @State private var generationRequest: StoryboardGenerationRequest?
    @State private var shotToDelete: ProjectStoryboardShot?
    @State private var alertMessage: String?

    private var project: ProjectRecord? { projectStore.project(id: projectID) }

    var body: some View {
        if let project {
            VStack(spacing: 18) {
                shotList(project)
                reviewNotes
                warnings(project)
                reviewActions(project)
            }
            .onAppear { notes = project.reviewNotes }
            .onChange(of: projectID) { _, _ in notes = self.project?.reviewNotes ?? "" }
            .sheet(item: $generationRequest) { request in
                generationSheet(request)
            }
            .confirmationDialog(
                "删除“\(shotToDelete?.title ?? "这个分镜")”？",
                isPresented: Binding(
                    get: { shotToDelete != nil },
                    set: { if !$0 { shotToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除分镜", role: .destructive) {
                    if let shotID = shotToDelete?.id {
                        projectStore.deleteStoryboardShot(projectID: projectID, shotID: shotID)
                    }
                    shotToDelete = nil
                }
                Button("取消", role: .cancel) { shotToDelete = nil }
            } message: {
                Text("只删除卡片和媒体关联，运行目录中的原始图片与视频不会被删除。")
            }
            .alert(
                "操作未完成",
                isPresented: Binding(
                    get: { alertMessage != nil },
                    set: { if !$0 { alertMessage = nil } }
                )
            ) {
                Button("好") { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "未知错误")
            }
        }
    }

    @ViewBuilder
    private func shotList(_ project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("分镜卡片")
                        .font(.title2.weight(.bold))
                    Text("参考图、提示词和生成视频按镜头集中审核")
                        .font(.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Button {
                    projectStore.addStoryboardShot(projectID: projectID)
                } label: {
                    Label("添加分镜", systemImage: "plus")
                }
            }

            if project.storyboardShots.isEmpty {
                StudioCard {
                    EmptyStateView(
                        title: "还没有分镜卡片",
                        message: "工作流没有输出可拆分的分镜文本，可以手动添加第一个镜头。",
                        systemImage: "rectangle.stack.badge.plus",
                        actionTitle: "添加分镜",
                        action: { projectStore.addStoryboardShot(projectID: projectID) }
                    )
                    .frame(minHeight: 260)
                }
            } else {
                ForEach(project.storyboardShots.sorted(by: { $0.order < $1.order })) { shot in
                    StoryboardShotCard(
                        projectID: projectID,
                        workflowID: project.workflowID,
                        runID: project.workflowRunID,
                        shot: shot,
                        prompt: promptBinding(shotID: shot.id),
                        onImportImages: { urls in importImages(urls, for: shot.id, project: project) },
                        onGenerateImage: { generationRequest = .referenceImage(shot.id) },
                        onCancelImage: {
                            mediaGenerator.cancelReferenceImage(
                                shotID: shot.id,
                                projectID: projectID,
                                projectStore: projectStore
                            )
                        },
                        onRemoveImage: { referenceID in
                            projectStore.removeReferenceImage(
                                projectID: projectID,
                                shotID: shot.id,
                                referenceID: referenceID
                            )
                        },
                        onGenerateVideo: { generationRequest = .video(shot.id) },
                        onCancelVideo: {
                            mediaGenerator.cancelVideo(
                                shotID: shot.id,
                                projectID: projectID,
                                projectStore: projectStore
                            )
                        },
                        onDelete: { shotToDelete = shot }
                    )
                }
            }
        }
    }

    private var reviewNotes: some View {
        StudioCard(title: "审核意见", subtitle: "可选，记录修改说明或通过理由。") {
            TextEditor(text: $notes)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.stroke))
        }
    }

    @ViewBuilder
    private func warnings(_ project: ProjectRecord) -> some View {
        if !project.runWarnings.isEmpty {
            StudioCard(title: "运行提醒") {
                ForEach(project.runWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func reviewActions(_ project: ProjectRecord) -> some View {
        let isGeneratingMedia = project.storyboardShots.contains {
            $0.referenceGenerationStatus == .generating || $0.videoStatus == .generating
        }
        return HStack {
            Button("重新运行", action: onRerun)
                .disabled(isGeneratingMedia)
            Spacer()
            Button("保存修改") {
                projectStore.saveStoryboardReview(projectID: projectID, notes: notes)
            }
            Button("审核通过") {
                projectStore.approveStoryboardReview(projectID: projectID, notes: notes)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.success)
            .disabled(
                isGeneratingMedia ||
                project.storyboardShots.isEmpty ||
                project.storyboardShots.contains { $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            )
        }
    }

    @ViewBuilder
    private func generationSheet(_ request: StoryboardGenerationRequest) -> some View {
        switch request {
        case .referenceImage(let shotID):
            if let shot = project?.storyboardShots.first(where: { $0.id == shotID }) {
                ProjectImageGenerationSheet(shot: shot) { configuration in
                    generationRequest = nil
                    mediaGenerator.generateReferenceImage(
                        projectID: projectID,
                        shotID: shotID,
                        configuration: configuration,
                        settings: settings,
                        workflowStore: workflowStore,
                        projectStore: projectStore
                    )
                }
            }
        case .video(let shotID):
            if let shot = project?.storyboardShots.first(where: { $0.id == shotID }) {
                ProjectVideoGenerationSheet(shot: shot) { configuration in
                    generationRequest = nil
                    mediaGenerator.generateVideo(
                        projectID: projectID,
                        shotID: shotID,
                        configuration: configuration,
                        settings: settings,
                        workflowStore: workflowStore,
                        projectStore: projectStore
                    )
                }
            }
        }
    }

    private func promptBinding(shotID: UUID) -> Binding<String> {
        Binding(
            get: {
                projectStore.project(id: projectID)?
                    .storyboardShots.first(where: { $0.id == shotID })?.prompt ?? ""
            },
            set: { projectStore.updateStoryboardPrompt(projectID: projectID, shotID: shotID, prompt: $0) }
        )
    }

    private func importImages(_ urls: [URL], for shotID: UUID, project: ProjectRecord) {
        guard let runID = project.workflowRunID else {
            alertMessage = "项目没有关联的工作流运行，无法保存参考图片。"
            return
        }
        do {
            let paths = try workflowStore.importProjectReferenceImages(
                urls,
                workflowID: project.workflowID,
                runID: runID
            )
            projectStore.addReferenceImages(
                projectID: projectID,
                shotID: shotID,
                relativePaths: paths,
                source: .imported
            )
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

/// 当前显示的媒体生成确认页。
private enum StoryboardGenerationRequest: Identifiable {
    case referenceImage(UUID)
    case video(UUID)

    var id: String {
        switch self {
        case .referenceImage(let id): "image-\(id.uuidString)"
        case .video(let id): "video-\(id.uuidString)"
        }
    }
}

/// 单个分镜的三栏卡片。
private struct StoryboardShotCard: View {
    @Environment(WorkflowStore.self) private var workflowStore

    let projectID: UUID
    let workflowID: UUID
    let runID: UUID?
    let shot: ProjectStoryboardShot
    @Binding var prompt: String
    let onImportImages: ([URL]) -> Void
    let onGenerateImage: () -> Void
    let onCancelImage: () -> Void
    let onRemoveImage: (UUID) -> Void
    let onGenerateVideo: () -> Void
    let onCancelVideo: () -> Void
    let onDelete: () -> Void

    @State private var selectedReferenceID: UUID?
    @State private var showImageImporter = false

    private var selectedReference: ProjectReferenceImage? {
        shot.referenceImages.first(where: { $0.id == selectedReferenceID }) ?? shot.referenceImages.first
    }

    var body: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        referencePanel
                            .frame(minWidth: 250, maxWidth: .infinity)
                        promptPanel
                            .frame(minWidth: 290, maxWidth: .infinity)
                        videoPanel
                            .frame(width: 230)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        referencePanel
                        promptPanel
                        videoPanel
                    }
                }
            }
        }
        .onAppear(perform: normalizeSelection)
        .onChange(of: shot.referenceImages.map(\.id)) { _, _ in normalizeSelection() }
        .fileImporter(
            isPresented: $showImageImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { onImportImages(Array(urls.prefix(9 - shot.referenceImages.count))) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(String(format: "分镜 %02d", shot.order))
                .font(.headline)
            Text(shot.title)
                .font(.callout)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
            Text("· \(shot.durationSeconds) 秒")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
            Spacer()
            StatusBadge(
                text: shot.videoStatus == .generating
                    ? generationTitle
                    : shot.videoStatus.title,
                style: shot.videoStatus.badgeStyle,
                systemImage: shot.videoStatus.systemImage
            )
            Menu {
                Button("删除分镜", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .disabled(shot.referenceGenerationStatus == .generating || shot.videoStatus == .generating)
        }
    }

    private var generationTitle: String {
        guard let progress = shot.videoProgress else { return "生成中" }
        return "生成中 \(Int((progress * 100).rounded()))%"
    }

    private var referencePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("参考图片", trailing: "\(shot.referenceImages.count) / 9")
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.bgElevated)
                if let reference = selectedReference,
                   let url = mediaURL(relativePath: reference.relativePath) {
                    LocalProjectImage(url: url)
                        .padding(10)
                } else {
                    VStack(spacing: 9) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 28))
                        Text(shot.referenceImages.isEmpty ? "暂无参考图片" : "图片文件已丢失")
                            .font(.caption)
                    }
                    .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .frame(minHeight: 270)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.stroke))

            if !shot.referenceImages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(shot.referenceImages) { reference in
                            Button {
                                selectedReferenceID = reference.id
                            } label: {
                                Group {
                                    if let url = mediaURL(relativePath: reference.relativePath) {
                                        LocalProjectImage(url: url)
                                    } else {
                                        Image(systemName: "photo.badge.exclamationmark")
                                            .foregroundStyle(AppTheme.textTertiary)
                                    }
                                }
                                .frame(width: 46, height: 46)
                                .background(AppTheme.bgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(
                                            selectedReference?.id == reference.id ? AppTheme.accent : AppTheme.stroke,
                                            lineWidth: selectedReference?.id == reference.id ? 2 : 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .help(reference.name)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 8) {
                Button {
                    showImageImporter = true
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .disabled(shot.referenceImages.count >= 9)

                if shot.referenceGenerationStatus == .generating {
                    Button(role: .destructive, action: onCancelImage) {
                        Label("取消生图", systemImage: "xmark")
                    }
                } else {
                    Button(action: onGenerateImage) {
                        Label("生成参考图", systemImage: "sparkles")
                    }
                    .disabled(shot.referenceImages.count >= 9)
                }

                if let selectedReference {
                    Button(role: .destructive) { onRemoveImage(selectedReference.id) } label: {
                        Image(systemName: "trash")
                    }
                    .help("从当前分镜移除所选图片")
                }
            }

            if shot.referenceGenerationStatus == .generating {
                ProgressView(value: shot.referenceGenerationProgress)
            }
            if let message = shot.referenceGenerationMessage,
               shot.referenceGenerationStatus != .idle {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(shot.referenceGenerationStatus == .failed ? AppTheme.danger : AppTheme.textTertiary)
                    .lineLimit(2)
            }
        }
    }

    private var promptPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("视频提示词", trailing: "镜头共用")
            TextEditor(text: $prompt)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 270)
                .padding(10)
                .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.stroke))
            HStack {
                Button {
                    let suffix = "\n镜头运动保持平滑，主体比例稳定，人物与商品外观在全过程保持一致。"
                    if !prompt.contains("镜头运动保持平滑") {
                        prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines) + suffix
                    }
                } label: {
                    Label("优化提示词", systemImage: "wand.and.stars")
                }
                Spacer()
                Label("自动保存", systemImage: "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private var videoPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("生成视频", trailing: shot.videoAspectRatio)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.bgElevated)
                videoContent
                    .padding(10)
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .frame(maxWidth: 230)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.stroke))

            HStack {
                Spacer()
                if shot.videoStatus == .generating {
                    Button(role: .destructive, action: onCancelVideo) {
                        Label("取消", systemImage: "xmark")
                    }
                } else {
                    Button(action: onGenerateVideo) {
                        Label(
                            shot.videoRelativePath == nil ? "生成视频" : "重新生成",
                            systemImage: shot.videoRelativePath == nil ? "sparkles" : "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Spacer()
            }

            if let message = shot.videoMessage, !message.isEmpty {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(shot.videoStatus == .failed ? AppTheme.danger : AppTheme.textTertiary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private var videoContent: some View {
        if shot.videoStatus == .generating {
            VStack(spacing: 12) {
                ProgressView(value: shot.videoProgress)
                    .controlSize(.large)
                Text(generationTitle)
                    .font(.headline)
                Text(shot.videoMessage ?? "正在生成视频")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        } else if let relativePath = shot.videoRelativePath,
                  let url = mediaURL(relativePath: relativePath) {
            ProjectVideoPlayer(url: url)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(spacing: 11) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 86, height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Text(shot.videoStatus == .failed ? "视频生成失败" : "暂无视频")
                    .font(.headline)
                Text(shot.videoStatus == .failed ? (shot.videoMessage ?? "请重试") : "确认参考图和提示词后开始生成")
                    .font(.caption)
                    .foregroundStyle(shot.videoStatus == .failed ? AppTheme.danger : AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(trailing)
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private func mediaURL(relativePath: String) -> URL? {
        guard let runID else { return nil }
        return workflowStore.artifactURL(
            relativePath: relativePath,
            workflowID: workflowID,
            runID: runID
        )
    }

    private func normalizeSelection() {
        if let selectedReferenceID,
           shot.referenceImages.contains(where: { $0.id == selectedReferenceID }) {
            return
        }
        selectedReferenceID = shot.referenceImages.first?.id
    }
}

/// 以原始比例展示一张运行目录内的图片。
private struct LocalProjectImage: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(AppTheme.textTertiary)
        }
    }
}

/// 使用系统播放器预览项目镜头 MP4。
private struct ProjectVideoPlayer: View {
    let url: URL
    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.replaceCurrentItem(with: AVPlayerItem(url: url)) }
            .onChange(of: url) { _, newURL in
                player.replaceCurrentItem(with: AVPlayerItem(url: newURL))
            }
            .onDisappear { player.pause() }
    }
}

/// 参考图生成前的服务商、模型和提示词确认页。
private struct ProjectImageGenerationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings

    let shot: ProjectStoryboardShot
    let onGenerate: (ProjectImageGenerationConfiguration) -> Void

    @State private var providerID: UUID?
    @State private var model = ""
    @State private var size = ImageProvider.defaultSize
    @State private var prompt: String

    init(
        shot: ProjectStoryboardShot,
        onGenerate: @escaping (ProjectImageGenerationConfiguration) -> Void
    ) {
        self.shot = shot
        self.onGenerate = onGenerate
        _prompt = State(initialValue: shot.prompt)
    }

    private var provider: ImageProvider? { settings.imageProvider(id: providerID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("生成参考图")
                    .font(.title2.weight(.bold))
                Text("生成结果会加入分镜 \(shot.order) 的参考图片，并产生一次模型调用。")
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if settings.imageProviders.isEmpty {
                EmptyStateView(
                    title: "还没有生图服务商",
                    message: "请先在设置中添加生图服务商并配置 API Key。",
                    systemImage: "photo.badge.exclamationmark"
                )
            } else {
                Form {
                    Picker("服务商", selection: $providerID) {
                        ForEach(settings.imageProviders) { provider in
                            Text(provider.name).tag(Optional(provider.id))
                        }
                    }
                    Picker("模型", selection: $model) {
                        ForEach(provider?.models ?? [], id: \.self) { Text($0).tag($0) }
                    }
                    Picker("尺寸", selection: $size) {
                        ForEach(ImageProvider.availableSizes, id: \.self) { Text($0).tag($0) }
                    }
                }
                .formStyle(.grouped)

                VStack(alignment: .leading, spacing: 7) {
                    Text("图片提示词")
                        .font(.subheadline.weight(.semibold))
                    TextEditor(text: $prompt)
                        .frame(minHeight: 150)
                        .padding(8)
                        .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.stroke))
                }
            }

            Spacer()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("确认生成") {
                    guard let providerID else { return }
                    onGenerate(ProjectImageGenerationConfiguration(
                        providerID: providerID,
                        model: model,
                        size: size,
                        prompt: prompt
                    ))
                }
                .buttonStyle(.borderedProminent)
                .disabled(providerID == nil || model.isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 620, height: 570)
        .onAppear(perform: selectImageDefaults)
        .onChange(of: providerID) { _, _ in selectImageProviderDefaults() }
    }

    private func selectImageDefaults() {
        if providerID == nil { providerID = settings.imageProviders.first?.id }
        selectImageProviderDefaults()
    }

    private func selectImageProviderDefaults() {
        guard let provider else { return }
        if !provider.models.contains(model) { model = provider.models.first ?? "" }
        size = ImageProvider.availableSizes.contains(provider.defaultSize)
            ? provider.defaultSize
            : ImageProvider.defaultSize
    }
}

/// 视频生成前的能力约束与付费操作确认页。
private struct ProjectVideoGenerationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings

    let shot: ProjectStoryboardShot
    let onGenerate: (ProjectVideoGenerationConfiguration) -> Void

    @State private var providerID: UUID?
    @State private var model = ""
    @State private var aspectRatio = "9:16"
    @State private var resolution = "720x1280"
    @State private var durationSeconds = 4
    @State private var includeAudio = false

    private var provider: VideoProvider? { settings.videoProvider(id: providerID) }
    private var descriptor: MediaAdapterDescriptor? {
        guard let provider else { return nil }
        return MediaAdapterRegistry.shared.videoAdapter(id: provider.adapterID)?.descriptor
    }
    private var capability: VideoModelCapability? { descriptor?.videoCapability(for: model) }
    private var aspectRatios: [String] {
        let values = capability?.aspectRatios ?? ["9:16"]
        return values.isEmpty ? ["9:16"] : values
    }
    private var resolutions: [String] {
        let values = capability?.resolutions ?? descriptor?.supportedSizes ?? []
        return values.isEmpty ? ["720x1280"] : values
    }
    private var durations: [Int] {
        let values = capability?.durations ?? descriptor?.supportedDurations ?? []
        return values.isEmpty ? VideoProvider.availableDurations : values
    }
    private var supportsAudio: Bool {
        capability?.supportsAudioGeneration ?? descriptor?.supportsAudioGeneration ?? false
    }
    private var maximumReferenceImages: Int {
        capability?.maximumReferenceImages ?? descriptor?.maximumReferenceImages ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("生成镜头视频")
                    .font(.title2.weight(.bold))
                Text("分镜 \(shot.order) · 将使用最多 \(min(shot.referenceImages.count, maximumReferenceImages)) 张参考图，并产生一次视频模型调用。")
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if settings.videoProviders.isEmpty {
                EmptyStateView(
                    title: "还没有生视频服务商",
                    message: "请先在设置中添加生视频服务商并完成鉴权。",
                    systemImage: "video.badge.exclamationmark"
                )
            } else {
                Form {
                    Picker("服务商", selection: $providerID) {
                        ForEach(settings.videoProviders) { provider in
                            Text(provider.name).tag(Optional(provider.id))
                        }
                    }
                    Picker("模型", selection: $model) {
                        ForEach(provider?.models ?? [], id: \.self) { Text($0).tag($0) }
                    }
                    Picker("画面比例", selection: $aspectRatio) {
                        ForEach(aspectRatios, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("分辨率", selection: $resolution) {
                        ForEach(resolutions, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("时长", selection: $durationSeconds) {
                        ForEach(durations, id: \.self) { Text("\($0) 秒").tag($0) }
                    }
                    if supportsAudio {
                        Toggle("同时生成声音", isOn: $includeAudio)
                    }
                }
                .formStyle(.grouped)

                StudioCard(title: "本次提示词") {
                    Text(shot.prompt)
                        .font(.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(6)
                }
            }

            Spacer()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("确认生成") {
                    guard let providerID else { return }
                    onGenerate(ProjectVideoGenerationConfiguration(
                        providerID: providerID,
                        model: model,
                        aspectRatio: aspectRatio,
                        resolution: resolution,
                        durationSeconds: durationSeconds,
                        includeAudio: includeAudio
                    ))
                }
                .buttonStyle(.borderedProminent)
                .disabled(providerID == nil || model.isEmpty || shot.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 640, height: 610)
        .onAppear(perform: selectVideoDefaults)
        .onChange(of: providerID) { _, _ in selectVideoProviderDefaults() }
        .onChange(of: model) { _, _ in normalizeVideoCapability() }
    }

    private func selectVideoDefaults() {
        if providerID == nil { providerID = settings.videoProviders.first?.id }
        selectVideoProviderDefaults()
    }

    private func selectVideoProviderDefaults() {
        guard let provider else { return }
        if !provider.models.contains(model) { model = provider.models.first ?? "" }
        durationSeconds = provider.defaultDurationSeconds
        normalizeVideoCapability()
    }

    private func normalizeVideoCapability() {
        if !aspectRatios.contains(aspectRatio) {
            aspectRatio = aspectRatios.contains("9:16") ? "9:16" : (aspectRatios.first ?? "9:16")
        }
        if !resolutions.contains(resolution) {
            resolution = preferredVerticalResolution(in: resolutions) ?? resolutions.first ?? "720x1280"
        }
        if !durations.contains(durationSeconds) {
            durationSeconds = durations.min(by: { abs($0 - shot.durationSeconds) < abs($1 - shot.durationSeconds) })
                ?? durations.first
                ?? 4
        }
        if !supportsAudio { includeAudio = false }
    }

    private func preferredVerticalResolution(in values: [String]) -> String? {
        values.first { value in
            let parts = value.lowercased().split(separator: "x").compactMap { Int($0) }
            return parts.count == 2 && parts[1] > parts[0]
        }
    }
}

private extension ProjectMediaStatus {
    var badgeStyle: StatusBadge.Style {
        switch self {
        case .idle, .cancelled: .neutral
        case .generating: .accent
        case .succeeded: .success
        case .failed: .danger
        }
    }

    var systemImage: String {
        switch self {
        case .idle: "video.badge.plus"
        case .generating: "arrow.trianglehead.2.clockwise.rotate.90"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "stop.circle"
        }
    }
}
