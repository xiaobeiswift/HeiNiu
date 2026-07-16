/// 项目创作流水线：左侧步骤栏 + 右侧工作区。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import AppKit
import SwiftUI

/// 分步流程面板：左栏流程、右栏当前步骤产物。
struct ProjectPipelineView: View {
    @Environment(ProjectStore.self) private var projects
    @Environment(SettingsStore.self) private var settings

    let project: ProjectItem

    @State private var pipeline: ProjectPipeline
    @State private var selectedKind: PipelineStepKind = .script
    @State private var isRunning = false
    @State private var banner: String?

    init(project: ProjectItem, pipeline: ProjectPipeline) {
        self.project = project
        _pipeline = State(initialValue: pipeline)
        _selectedKind = State(initialValue: pipeline.currentKind)
    }

    private var selectedStep: PipelineStep {
        pipeline.step(selectedKind)
    }

    var body: some View {
        HStack(spacing: 0) {
            stepRail
                .frame(width: 200)
                .background(AppTheme.bgSidebar.opacity(0.55))

            Divider().opacity(0.45)

            stepWorkspace
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.bgBase)
        .onChange(of: project.id) { _, _ in
            pipeline = projects.pipeline(for: project.id)
            selectedKind = pipeline.currentKind
            banner = nil
        }
    }

    // MARK: - Left rail

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("创作流程")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("一步一步推进")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(PipelineStepKind.allCases.enumerated()), id: \.element.id) { index, kind in
                        if index > 0 {
                            // 竖向连接线
                            Rectangle()
                                .fill(AppTheme.strokeStrong)
                                .frame(width: 1, height: 10)
                                .padding(.leading, 22)
                        }
                        stepRow(kind)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
    }

    private func stepRow(_ kind: PipelineStepKind) -> some View {
        let step = pipeline.step(kind)
        let selected = selectedKind == kind
        return Button {
            select(kind)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(selected ? AppTheme.accent : AppTheme.bgElevated)
                        .frame(width: 26, height: 26)
                    if step.status == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(selected ? Color.black.opacity(0.8) : AppTheme.success)
                    } else if step.status == .running {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("\(kind.order)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(selected ? Color.black.opacity(0.8) : AppTheme.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.callout.weight(selected ? .semibold : .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text(step.status.title)
                        .font(.caption2)
                        .foregroundStyle(statusColor(step.status))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? AppTheme.accentSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? AppTheme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right workspace

    private var stepWorkspace: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶栏：标题 + 操作
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedKind.title)
                        .font(.title3.weight(.semibold))
                    Text(selectedKind.subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }
                Spacer()
                StatusBadge(
                    text: selectedStep.status.title,
                    style: badgeStyle(selectedStep.status)
                )
                Button {
                    Task { await runSelected() }
                } label: {
                    HStack(spacing: 6) {
                        if isRunning && selectedStep.status == .running {
                            ProgressView().controlSize(.small)
                        }
                        Text(runButtonTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(canRun ? Color.black.opacity(0.85) : AppTheme.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(canRun ? AppTheme.accent : AppTheme.bgElevated))
                }
                .buttonStyle(.plain)
                .disabled(!canRun || isRunning)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            if let err = selectedStep.errorMessage, selectedStep.status == .failed {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(AppTheme.danger)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            if !selectedKind.isTextStep {
                Text("此步依赖生图/生视频接口，当前版本先完成文本链路；可在「设置」里预先配置服务商。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            Divider().opacity(0.4)

            // 产物区
            if selectedStep.hasOutput {
                ScrollView {
                    Text(selectedStep.outputText)
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().opacity(0.4)
                HStack(spacing: 16) {
                    Button("复制结果") {
                        copyText(selectedStep.outputText)
                        banner = "已复制"
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)

                    if let next = nextKind(after: selectedKind) {
                        Button("下一步：\(next.title)") {
                            select(next)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                    if let banner {
                        Text(banner)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            } else {
                VStack(spacing: 12) {
                    Spacer(minLength: 24)
                    Image(systemName: selectedKind.isTextStep ? "text.badge.plus" : "sparkles.rectangle.stack")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(AppTheme.accent.opacity(0.85))
                    Text(idleHint)
                        .font(.callout)
                        .foregroundStyle(AppTheme.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    if let banner {
                        Text(banner)
                            .font(.caption)
                            .foregroundStyle(AppTheme.danger)
                    }
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            }
        }
    }

    // MARK: - Logic

    private var canRun: Bool {
        if isRunning { return false }
        if !selectedKind.isTextStep { return false }
        switch selectedKind {
        case .script:
            return true
        case .segment, .characters, .scenes, .items:
            return pipeline.step(.script).status == .done
        case .shotPrompts:
            return pipeline.step(.segment).status == .done
        case .images, .video:
            return false
        }
    }

    private var runButtonTitle: String {
        if isRunning && selectedStep.status == .running { return "生成中…" }
        if selectedStep.status == .done { return "重新生成" }
        if !selectedKind.isTextStep { return "即将支持" }
        return "开始"
    }

    private var idleHint: String {
        switch selectedKind {
        case .script:
            return "将使用项目名称、卖点、概要等作为简报，调用提示词库「剧本」模板生成。"
        case .segment:
            return "需要先有剧本。将把剧本切成可拍段落。"
        case .characters, .scenes, .items:
            return "基于剧本（与分段，如有）提取结构化设定卡。"
        case .images:
            return "需要人物/场景/物品卡完成后，再调用生图服务商。"
        case .shotPrompts:
            return "基于分段与资产卡，为每段写提示词并匹配人物场景物品。"
        case .video:
            return "需要段落提示词完成后，再调用生视频服务商。"
        }
    }

    private func select(_ kind: PipelineStepKind) {
        selectedKind = kind
        var pipe = pipeline
        pipe.currentKind = kind
        pipeline = pipe
        projects.savePipeline(pipe)
        banner = nil
    }

    private func runSelected() async {
        banner = nil
        isRunning = true
        defer { isRunning = false }
        // 乐观更新 running 态
        var running = pipeline
        running.updateStep(selectedKind) { $0.status = .running; $0.errorMessage = nil }
        pipeline = running

        do {
            let next = try await projects.runPipelineStep(
                selectedKind,
                projectID: project.id,
                settings: settings
            )
            pipeline = next
            banner = "「\(selectedKind.title)」已完成"
        } catch {
            pipeline = projects.pipeline(for: project.id)
            banner = error.localizedDescription
        }
    }

    private func nextKind(after kind: PipelineStepKind) -> PipelineStepKind? {
        let all = PipelineStepKind.allCases
        guard let i = all.firstIndex(of: kind), i + 1 < all.count else { return nil }
        return all[i + 1]
    }

    private func badgeStyle(_ status: PipelineStepStatus) -> StatusBadge.Style {
        switch status {
        case .idle: .neutral
        case .running: .accent
        case .done: .success
        case .failed: .danger
        }
    }

    private func statusColor(_ status: PipelineStepStatus) -> Color {
        switch status {
        case .idle: AppTheme.textTertiary
        case .running: AppTheme.accent
        case .done: AppTheme.success
        case .failed: AppTheme.danger
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
