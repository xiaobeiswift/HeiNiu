/// 项目卡片列表、新建运行与分镜审核闭环。

import SwiftUI

/// 项目模块入口。
struct ProjectsHomeView: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorkflowStore.self) private var workflowStore
    @Environment(SettingsStore.self) private var settings
    @Environment(KnowledgeStore.self) private var knowledge

    @State private var executor = WorkflowExecutor()
    @State private var navigationPath: [UUID] = []
    @State private var runningProjectID: UUID?
    @State private var sheetRequest: ProjectSheetRequest?
    @State private var projectActionError: String?
    @State private var projectToDelete: ProjectRecord?

    private var hasActiveWorkflowRun: Bool {
        [.running, .waitingForKnowledge].contains(workflowStore.activeRun?.status) || executor.isRunning
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.45)
                projectGrid
            }
            .background(AppTheme.bgBase)
            .navigationDestination(for: UUID.self) { projectID in
                ProjectDetailView(
                    projectID: projectID,
                    onRerun: { requestRerun(projectID: projectID) },
                    onCancel: cancelRunningProject,
                    onRetryKnowledge: { presentKnowledgeWizard(projectID: projectID) }
                )
                .sheet(item: detailSheetRequest) { request in
                    projectSheet(for: request)
                }
                .alert("项目操作没有完成", isPresented: detailActionErrorPresented) {
                    Button("知道了", role: .cancel) { projectActionError = nil }
                } message: {
                    Text(projectActionError ?? "请稍后重试")
                }
            }
        }
        .sheet(item: rootSheetRequest) { request in
            projectSheet(for: request)
        }
        .alert("项目操作没有完成", isPresented: rootActionErrorPresented) {
            Button("知道了", role: .cancel) { projectActionError = nil }
        } message: {
            Text(projectActionError ?? "请稍后重试")
        }
        .confirmationDialog(
            "删除项目“\(projectToDelete?.name ?? "")”？",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除项目卡片", role: .destructive) {
                if let id = projectToDelete?.id {
                    navigationPath.removeAll { $0 == id }
                    projectStore.deleteProject(id: id)
                }
                projectToDelete = nil
            }
            Button("取消", role: .cancel) { projectToDelete = nil }
        } message: {
            Text("项目卡片和审核内容会被删除；关联的全局工作流运行历史与媒体仍会保留。")
        }
        .onAppear(perform: reconcileRunningProject)
        .onChange(of: workflowStore.activeRun) { _, run in
            handleRunChange(run)
        }
    }

    private var rootActionErrorPresented: Binding<Bool> {
        Binding(
            get: { navigationPath.isEmpty && projectActionError != nil },
            set: { if !$0 { projectActionError = nil } }
        )
    }

    private var detailActionErrorPresented: Binding<Bool> {
        Binding(
            get: { !navigationPath.isEmpty && projectActionError != nil },
            set: { if !$0 { projectActionError = nil } }
        )
    }

    /// 导航根页只呈现列表态发起的弹窗，避免详情页请求被不可见的根页截获。
    private var rootSheetRequest: Binding<ProjectSheetRequest?> {
        Binding(
            get: { navigationPath.isEmpty ? sheetRequest : nil },
            set: { sheetRequest = $0 }
        )
    }

    /// 进入项目详情后，由当前可见的导航目的页呈现重新运行或补库弹窗。
    private var detailSheetRequest: Binding<ProjectSheetRequest?> {
        Binding(
            get: { navigationPath.isEmpty ? nil : sheetRequest },
            set: { sheetRequest = $0 }
        )
    }

    @ViewBuilder
    private func projectSheet(for request: ProjectSheetRequest) -> some View {
        switch request.destination {
        case .newProject:
            NewProjectSheet(workflows: workflowStore.workflows) { name, workflowID, inputs in
                createAndRun(name: name, workflowID: workflowID, inputs: inputs)
            }
        case .rerun(let rerun):
            if let workflow = workflowStore.workflow(id: rerun.workflowID) {
                WorkflowRunPreflightSheet(
                    workflow: workflow,
                    targetNodeID: nil,
                    onRun: { inputs in
                        startRerun(projectID: rerun.projectID, workflow: workflow, inputs: inputs)
                    }
                )
            } else {
                MissingProjectSheet(message: "找不到项目绑定的工作流，无法重新运行。")
            }
        case .knowledgeGap(let gap):
            WorkflowRunPreflightSheet(
                workflow: gap.workflow,
                targetNodeID: nil,
                onRun: { inputs in
                    startKnowledgeChild(request: gap, inputs: inputs)
                }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("项目")
                    .font(.largeTitle.weight(.bold))
                Text("选择工作流运行，完成后进入分镜审核")
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            if let message = executor.statusMessage, executor.isRunning {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Button {
                presentNewProject()
            } label: {
                Label("新建项目", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .foregroundStyle(.black)
            .disabled(hasActiveWorkflowRun || workflowStore.workflows.isEmpty)
            .help(hasActiveWorkflowRun ? "当前有工作流正在运行" : "创建项目并填写本次工作流输入")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var projectGrid: some View {
        if projectStore.projects.isEmpty {
            EmptyStateView(
                title: "还没有项目",
                message: "新建项目并选择一个工作流，确认后会立即开始运行。",
                systemImage: "square.grid.2x2",
                actionTitle: workflowStore.workflows.isEmpty ? nil : "新建项目",
                action: workflowStore.workflows.isEmpty ? nil : { presentNewProject() }
            )
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(projectStore.projects) { project in
                        NavigationLink(value: project.id) {
                            ProjectCardView(
                                project: project,
                                activeRun: activeRun(for: project)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if ![.running, .awaitingKnowledge].contains(project.status) {
                                Button("重新运行") { requestRerun(projectID: project.id) }
                            }
                            Divider()
                            Button("删除", role: .destructive) { projectToDelete = project }
                                .disabled([.running, .awaitingKnowledge].contains(project.status))
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func activeRun(for project: ProjectRecord) -> WorkflowRun? {
        guard workflowStore.activeRun?.id == project.workflowRunID else { return nil }
        return workflowStore.activeRun
    }

    private func createAndRun(
        name: String,
        workflowID: UUID,
        inputs: [String: WorkflowValue]
    ) {
        guard let workflow = workflowStore.workflow(id: workflowID) else { return }
        let projectID = projectStore.createProject(name: name, workflow: workflow)
        run(projectID: projectID, workflow: workflow, inputs: inputs)
    }

    private func requestRerun(projectID: UUID) {
        guard !hasActiveWorkflowRun else {
            projectActionError = "当前还有工作流正在运行或等待补资料，请先完成或取消后再重新运行。"
            return
        }
        guard let project = projectStore.project(id: projectID) else {
            projectActionError = "找不到这个项目，可能已经被删除。"
            return
        }
        guard let workflow = workflowStore.workflow(id: project.workflowID) else {
            projectActionError = "找不到项目绑定的工作流“\(project.workflowName)”。"
            return
        }
        sheetRequest = ProjectSheetRequest(destination: .rerun(
            ProjectRerunRequest(projectID: projectID, workflowID: workflow.id)
        ))
    }

    private func presentNewProject() {
        guard !hasActiveWorkflowRun else {
            projectActionError = "当前还有工作流正在运行或等待补资料，请完成后再新建项目。"
            return
        }
        sheetRequest = ProjectSheetRequest(destination: .newProject)
    }

    private func startRerun(
        projectID: UUID,
        workflow: WorkflowDefinition,
        inputs: [String: WorkflowValue]
    ) {
        projectStore.prepareForRerun(projectID: projectID, workflow: workflow)
        run(projectID: projectID, workflow: workflow, inputs: inputs)
    }

    private func run(
        projectID: UUID,
        workflow: WorkflowDefinition,
        inputs: [String: WorkflowValue]
    ) {
        runningProjectID = projectID
        if let runID = executor.start(
            workflow: workflow,
            targetNodeID: nil,
            runtimeInputs: inputs,
            settings: settings,
            knowledge: knowledge,
            store: workflowStore
        ) {
            projectStore.bindRun(projectID: projectID, runID: runID)
        } else {
            projectStore.markLaunchFailed(
                projectID: projectID,
                message: executor.statusMessage ?? "工作流未能启动"
            )
            runningProjectID = nil
        }
    }

    private func cancelRunningProject() {
        guard let projectID = runningProjectID, let project = projectStore.project(id: projectID) else { return }
        if project.status == .awaitingKnowledge, let runID = project.workflowRunID {
            let shouldCancelChild = executor.isRunning && workflowStore.activeRun?.parentRunID == runID
            guard let run = workflowStore.cancelWaitingRun(workflowID: project.workflowID, runID: runID),
                  let workflow = workflowStore.workflow(id: project.workflowID)
            else { return }
            if shouldCancelChild { executor.cancel() }
            sheetRequest = nil
            projectStore.synchronize(projectID: projectID, run: run, workflow: workflow)
            runningProjectID = nil
        } else {
            executor.cancel()
        }
    }

    private func handleRunChange(_ run: WorkflowRun?) {
        guard let run, let projectID = runningProjectID else { return }
        if let parentRunID = run.parentRunID {
            guard run.status != .running,
                  let project = projectStore.project(id: projectID),
                  project.workflowRunID == parentRunID,
                  let parent = workflowStore.storedRun(workflowID: project.workflowID, runID: parentRunID),
                  let workflow = workflowStore.workflow(id: project.workflowID)
            else { return }
            if [.succeeded, .warning].contains(run.status) {
                Task { @MainActor in
                    for _ in 0..<300 where executor.isRunning {
                        try? await Task.sleep(for: .milliseconds(10))
                    }
                    guard let currentParent = workflowStore.storedRun(
                        workflowID: project.workflowID,
                        runID: parentRunID
                    ), currentParent.status == .waitingForKnowledge else { return }
                    if !executor.resume(workflow: workflow, run: currentParent, settings: settings, knowledge: knowledge, store: workflowStore) {
                        workflowStore.activateRun(currentParent)
                        projectActionError = "补库已完成，但父工作流暂时无法恢复，请点击“继续补库”重试。"
                    }
                }
            } else {
                workflowStore.activateRun(parent)
                projectActionError = run.warnings.last ?? "补库子运行失败或已取消，父项目仍保持待补资料状态。"
            }
            return
        }
        guard
              let project = projectStore.project(id: projectID),
              project.workflowRunID == run.id,
              let workflow = workflowStore.workflow(id: project.workflowID)
        else { return }
        if run.status == .running {
            if project.status != .running {
                projectStore.synchronize(projectID: projectID, run: run, workflow: workflow)
            }
            return
        }

        let shouldOpenReview = projectStore.synchronize(
            projectID: projectID,
            run: run,
            workflow: workflow
        )
        if run.status == .waitingForKnowledge {
            Task { @MainActor in
                for _ in 0..<300 where executor.isRunning {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                presentKnowledgeWizard(projectID: projectID)
            }
            return
        }
        runningProjectID = nil
        if shouldOpenReview {
            navigationPath = [projectID]
        }
    }

    private func reconcileRunningProject() {
        guard let project = projectStore.projects.first(where: { [.running, .awaitingKnowledge].contains($0.status) }) else { return }
        runningProjectID = project.id
        guard let runID = project.workflowRunID else {
            projectStore.markLaunchFailed(projectID: project.id, message: "项目没有关联到有效运行")
            runningProjectID = nil
            return
        }
        if let activeRun = workflowStore.activeRun, activeRun.id == runID {
            handleRunChange(activeRun)
            return
        }
        if project.status == .awaitingKnowledge {
            workflowStore.failInterruptedKnowledgeChildren(parentRunID: runID)
        }
        workflowStore.loadRuns(workflowID: project.workflowID)
        if let storedRun = workflowStore.runsByWorkflowID[project.workflowID]?.first(where: { $0.id == runID }),
           let workflow = workflowStore.workflow(id: project.workflowID) {
            let shouldOpenReview = projectStore.synchronize(
                projectID: project.id,
                run: storedRun,
                workflow: workflow
            )
            if storedRun.status == .waitingForKnowledge {
                workflowStore.activateRun(storedRun)
                presentKnowledgeWizard(projectID: project.id)
            }
            if ![.running, .waitingForKnowledge].contains(storedRun.status) { runningProjectID = nil }
            if shouldOpenReview { navigationPath = [project.id] }
        } else {
            projectStore.markLaunchFailed(projectID: project.id, message: "找不到项目关联的工作流运行记录")
            runningProjectID = nil
        }
    }

    private func presentKnowledgeWizard(projectID: UUID) {
        guard !executor.isRunning,
              projectActionError == nil,
              sheetRequest == nil,
              let project = projectStore.project(id: projectID),
              let runID = project.workflowRunID,
              let parent = workflowStore.storedRun(workflowID: project.workflowID, runID: runID),
              parent.status == .waitingForKnowledge,
              let category = WorkflowKnowledgeCategory.allCases.first(where: { candidate in
                  parent.pendingKnowledgeGaps.contains { $0.requirement.category == candidate }
              }),
              let baseWorkflow = workflowStore.workflow(id: WorkflowDefinition.knowledgeImportWorkflowID)
        else { return }
        var childWorkflow = baseWorkflow
        let gaps = parent.pendingKnowledgeGaps.filter { $0.requirement.category == category }
        let instructions = gaps.map { gap in
            let aliases = gap.requirement.aliases.isEmpty ? "无" : gap.requirement.aliases.joined(separator: "、")
            return "- \(gap.requirement.name)；身份/用途：\(gap.requirement.role.isEmpty ? "原文明确要素" : gap.requirement.role)；别名：\(aliases)。必须写入可精确检索该身份的标题、标签和正文。"
        }.joined(separator: "\n")
        for index in childWorkflow.nodes.indices where childWorkflow.nodes[index].kind == .runtimeInput {
            switch childWorkflow.nodes[index].configuration.parameterName {
            case "整理要求":
                childWorkflow.nodes[index].configuration.text = "为父项目补齐以下\(category.title)资料：\n\(instructions)"
            case "知识整理提示词":
                childWorkflow.nodes[index].configuration.promptItemID = settings.promptItems.first {
                    $0.category == .knowledgeImport && $0.name == category.knowledgeImportPromptName
                }?.id ?? UUID()
                childWorkflow.nodes[index].configuration.promptSnapshot = promptTemplate(for: category)
            default:
                break
            }
        }
        sheetRequest = ProjectSheetRequest(destination: .knowledgeGap(
            ProjectKnowledgeGapRequest(
                projectID: projectID,
                parentRunID: parent.id,
                category: category,
                workflow: childWorkflow
            )
        ))
    }

    private func startKnowledgeChild(
        request: ProjectKnowledgeGapRequest,
        inputs: [String: WorkflowValue]
    ) {
        guard let project = projectStore.project(id: request.projectID) else { return }
        if let childID = executor.start(
            workflow: request.workflow,
            targetNodeID: nil,
            runtimeInputs: inputs,
            settings: settings,
            knowledge: knowledge,
            store: workflowStore,
            parentRunID: request.parentRunID,
            knowledgeGapCategory: request.category
        ) {
            workflowStore.appendChildRun(
                childID,
                toParentWorkflowID: project.workflowID,
                parentRunID: request.parentRunID
            )
        } else {
            projectActionError = executor.statusMessage ?? "补库工作流未能启动"
        }
    }

    private func promptTemplate(for category: WorkflowKnowledgeCategory) -> String {
        switch category {
        case .character: DefaultPrompts.characterKnowledgeImportPromptTemplate
        case .product: DefaultPrompts.productKnowledgeImportPromptTemplate
        case .vehicleScene: DefaultPrompts.vehicleKnowledgeImportPromptTemplate
        }
    }
}

/// 项目页使用一份弹窗请求，并交给当前可见的导航层级呈现。
private struct ProjectSheetRequest: Identifiable {
    enum Destination {
        case newProject
        case rerun(ProjectRerunRequest)
        case knowledgeGap(ProjectKnowledgeGapRequest)
    }

    var id = UUID()
    var destination: Destination
}

/// 一个等待用户重新填写运行输入的项目请求。
private struct ProjectRerunRequest {
    var projectID: UUID
    var workflowID: UUID
}

/// 一次按类别顺序执行的补库请求。
private struct ProjectKnowledgeGapRequest: Identifiable {
    var id = UUID()
    var projectID: UUID
    var parentRunID: UUID
    var category: WorkflowKnowledgeCategory
    var workflow: WorkflowDefinition
}

/// 弹窗呈现期间工作流意外丢失时的可见兜底，而不是显示一个空白窗口。
private struct MissingProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textSecondary)
            Button("关闭") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 420, height: 220)
    }
}

/// 单个项目卡片。
private struct ProjectCardView: View {
    let project: ProjectRecord
    let activeRun: WorkflowRun?

    private var completedNodeCount: Int {
        activeRun?.nodeRuns.filter {
            [.succeeded, .warning, .skipped].contains($0.status)
        }.count ?? 0
    }

    var body: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.accentSoft)
                            .frame(width: 42, height: 42)
                        Image(systemName: "movieclapper")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    Spacer()
                    StatusBadge(
                        text: project.status.title,
                        style: project.status.badgeStyle,
                        systemImage: project.status.systemImage
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                    Label(project.workflowName, systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                if let activeRun, activeRun.status == .running {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(
                            value: Double(completedNodeCount),
                            total: Double(max(1, activeRun.nodeRuns.count))
                        )
                        Text("已处理 \(completedNodeCount) / \(activeRun.nodeRuns.count) 个节点")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                } else if let error = project.lastError, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(AppTheme.danger)
                        .lineLimit(2)
                } else {
                    Text(project.storyboardDraft.isEmpty ? "等待生成分镜内容" : "分镜稿已生成，可进入审核")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(2)
                }

                HStack {
                    Text(project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    Spacer()
                    Label(project.status == .running ? "查看进度" : "查看项目", systemImage: "chevron.right")
                }
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }
}

/// 项目运行详情与分镜审核页。
private struct ProjectDetailView: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorkflowStore.self) private var workflowStore

    let projectID: UUID
    let onRerun: () -> Void
    let onCancel: () -> Void
    let onRetryKnowledge: () -> Void

    private var project: ProjectRecord? { projectStore.project(id: projectID) }
    private var run: WorkflowRun? {
        guard workflowStore.activeRun?.id == project?.workflowRunID else { return nil }
        return workflowStore.activeRun
    }
    private var workflow: WorkflowDefinition? { workflowStore.workflow(id: project?.workflowID) }

    var body: some View {
        Group {
            if let project {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        detailHeader(project)
                        switch project.status {
                        case .running:
                            runningContent(project)
                        case .awaitingKnowledge:
                            waitingKnowledgeContent(project)
                        case .awaitingReview, .approved:
                            reviewContent(project)
                        case .failed, .cancelled:
                            failedContent(project)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 1180)
                    .frame(maxWidth: .infinity)
                }
            } else {
                EmptyStateView(
                    title: "项目不存在",
                    message: "这个项目可能已经被删除。",
                    systemImage: "questionmark.folder"
                )
            }
        }
        .background(AppTheme.bgBase)
        .navigationTitle(project?.status == .running ? "项目运行" : "分镜审核")
    }

    private func detailHeader(_ project: ProjectRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(project.name)
                    .font(.largeTitle.weight(.bold))
                Label(project.workflowName, systemImage: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            StatusBadge(
                text: project.status.title,
                style: project.status.badgeStyle,
                systemImage: project.status.systemImage
            )
        }
    }

    private func runningContent(_ project: ProjectRecord) -> some View {
        StudioCard(title: "正在运行工作流", subtitle: "完成后会自动切换到分镜审核。") {
            VStack(alignment: .leading, spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                if let run {
                    ForEach(run.nodeRuns) { nodeRun in
                        HStack(spacing: 9) {
                            Image(systemName: nodeRun.status.systemImage)
                                .foregroundStyle(nodeRun.status == .failed ? AppTheme.danger : AppTheme.textSecondary)
                                .frame(width: 18)
                            Text(workflow?.nodes.first(where: { $0.id == nodeRun.nodeID })?.displayTitle ?? "节点")
                            Spacer()
                            Text(nodeRun.status.title)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                } else {
                    Text("正在准备运行记录…")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                HStack {
                    Spacer()
                    Button("停止运行", role: .destructive, action: onCancel)
                }
            }
        }
    }

    private func reviewContent(_ project: ProjectRecord) -> some View {
        StoryboardReviewView(projectID: project.id, onRerun: onRerun)
    }

    private func waitingKnowledgeContent(_ project: ProjectRecord) -> some View {
        StudioCard(title: "等待补齐创作资料", subtitle: "补库完成后会从知识核验节点继续，不会重复调用已完成的要素提取。") {
            VStack(alignment: .leading, spacing: 10) {
                if let run {
                    ForEach(run.pendingKnowledgeGaps) { gap in
                        Label("\(gap.requirement.category.title)：\(gap.requirement.name)", systemImage: "books.vertical")
                            .font(.callout.weight(.medium))
                        Text(gap.message)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                } else {
                    Text(project.lastError ?? "正在读取待补资料清单…")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                HStack {
                    Spacer()
                    Button("取消项目", role: .destructive, action: onCancel)
                    Button("继续补库", action: onRetryKnowledge)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func failedContent(_ project: ProjectRecord) -> some View {
        StudioCard(title: project.status.title) {
            VStack(alignment: .leading, spacing: 14) {
                Label(
                    project.lastError ?? "工作流没有完成",
                    systemImage: project.status == .cancelled ? "stop.circle" : "xmark.circle"
                )
                .foregroundStyle(project.status == .cancelled ? AppTheme.textSecondary : AppTheme.danger)
                HStack {
                    Spacer()
                    Button("重新运行", action: onRerun)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

}

/// 新建项目表单，只选择项目名与要执行的全局工作流。
private struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings

    let workflows: [WorkflowDefinition]
    let onCreate: (String, UUID, [String: WorkflowValue]) -> Void

    @State private var name = ""
    @State private var workflowID: UUID?
    @State private var configuringWorkflowID: UUID?

    init(
        workflows: [WorkflowDefinition],
        onCreate: @escaping (String, UUID, [String: WorkflowValue]) -> Void
    ) {
        self.workflows = workflows
        self.onCreate = onCreate
        _workflowID = State(initialValue: workflows.first?.id)
    }

    private var workflow: WorkflowDefinition? {
        workflows.first { $0.id == workflowID }
    }

    private var validationIssues: [WorkflowValidationIssue] {
        guard let workflow else { return [] }
        return WorkflowValidator.validate(workflow, settings: settings)
    }

    private var hasBlockingIssue: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || workflow == nil
            || validationIssues.contains { $0.severity == .error }
    }

    @ViewBuilder
    var body: some View {
        if let configuringWorkflowID,
           let workflow = workflows.first(where: { $0.id == configuringWorkflowID }) {
            WorkflowRunPreflightSheet(
                workflow: workflow,
                targetNodeID: nil,
                onBack: { self.configuringWorkflowID = nil },
                onRun: { inputs in
                    onCreate(name, workflow.id, inputs)
                }
            )
        } else {
            projectSetup
        }
    }

    private var projectSetup: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("新建项目")
                        .font(.title2.weight(.semibold))
                    Text("选择工作流后，下一步填写本次运行输入")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("下一步") {
                    guard let workflowID else { return }
                    configuringWorkflowID = workflowID
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .foregroundStyle(.black)
                .disabled(hasBlockingIssue)
            }
            .padding(20)
            Divider()

            Form {
                Section("项目信息") {
                    TextField("项目名称", text: $name)
                    Picker("执行工作流", selection: $workflowID) {
                        ForEach(workflows) { workflow in
                            Text(workflow.name).tag(Optional(workflow.id))
                        }
                    }
                }

                if let workflow {
                    Section("运行预览") {
                        LabeledContent("节点数量", value: "\(workflow.nodes.count)")
                        let estimate = WorkflowValidator.estimateCosts(workflow)
                        LabeledContent(
                            "最多调用",
                            value: "LLM \(estimate.llmCalls) · 生图 \(estimate.imageCalls) · 视频 \(estimate.videoCalls)"
                        )
                        Text("下一步填写或选择本次运行需要的文本、素材和文件夹。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }

                if !validationIssues.isEmpty {
                    Section("运行检查") {
                        ForEach(validationIssues) { issue in
                            Label(
                                issue.message,
                                systemImage: issue.severity == .error
                                    ? "xmark.circle.fill"
                                    : "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(issue.severity == .error ? AppTheme.danger : .orange)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 620, height: 560)
    }
}

private extension ProjectStatus {
    var badgeStyle: StatusBadge.Style {
        switch self {
        case .running, .awaitingKnowledge, .awaitingReview: .accent
        case .approved: .success
        case .failed: .danger
        case .cancelled: .neutral
        }
    }

    var systemImage: String {
        switch self {
        case .running: "clock.arrow.circlepath"
        case .awaitingKnowledge: "books.vertical.fill"
        case .awaitingReview: "doc.text.magnifyingglass"
        case .approved: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "stop.circle"
        }
    }
}

private extension WorkflowNodeRunStatus {
    var systemImage: String {
        switch self {
        case .pending: "circle"
        case .running: "arrow.trianglehead.2.clockwise.rotate.90"
        case .waiting: "books.vertical.fill"
        case .succeeded: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "stop.circle"
        }
    }
}
