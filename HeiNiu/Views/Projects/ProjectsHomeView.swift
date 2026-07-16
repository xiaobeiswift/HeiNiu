/// 短剧项目首页：操作卡片 + 筛选 + 最近项目网格。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import AppKit
import SwiftUI

/// 最近项目筛选（对齐参考布局：全部 / 本地新建 / 外部文件夹）。
private enum ProjectHomeFilter: String, CaseIterable, Identifiable {
    case all
    case local
    case external

    var id: String { rawValue }

    func title(local: Int, external: Int, total: Int) -> String {
        switch self {
        case .all: "全部 \(total)"
        case .local: "本地新建 \(local)"
        case .external: "外部文件夹 \(external)"
        }
    }
}

/// 项目主页。
///
/// 顶栏：新建空白 / 打开文件夹；下方最近项目卡片网格。
/// 点卡片进入详情；v1 无集数实体。
struct ProjectsHomeView: View {
    @Environment(ProjectStore.self) private var projects
    @Environment(HeiNiuAgentStore.self) private var agents

    /// 侧栏跳到某位黑妞（可选）。
    var onOpenAgent: ((UUID) -> Void)? = nil

    @State private var selectedID: UUID?
    @State private var filter: ProjectHomeFilter = .all
    @State private var editorItem: ProjectItem?
    @State private var pendingDelete: ProjectItem?
    /// 新建：只填名称。
    @State private var showCreateSheet = false
    @State private var newProjectName = ""

    private var localCount: Int {
        projects.projects.filter { !$0.isExternalFolder }.count
    }

    private var externalCount: Int {
        projects.projects.filter(\.isExternalFolder).count
    }

    private var filteredProjects: [ProjectItem] {
        projects.sortedProjects.filter { item in
            switch filter {
            case .all: true
            case .local: !item.isExternalFolder
            case .external: item.isExternalFolder
            }
        }
    }

    private var selectedProject: ProjectItem? {
        projects.project(id: selectedID)
    }

    var body: some View {
        Group {
            if let project = selectedProject {
                projectDetail(project)
            } else {
                homeBrowser
            }
        }
        .background(AppTheme.bgBase)
        .sheet(isPresented: $showCreateSheet) {
            ProjectNameSheet(name: $newProjectName) {
                commitCreateProject()
            }
            .frame(width: 420, height: 200)
        }
        .sheet(item: $editorItem) { item in
            ProjectEditorView(project: item) { updated in
                projects.updateProject(updated)
                selectedID = updated.id
            }
            .frame(width: 560, height: 620)
        }
        .confirmationDialog(
            "删除「\(pendingDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = pendingDelete?.id {
                    projects.deleteProject(id: id)
                    if selectedID == id { selectedID = nil }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("仅删除项目记录，不会影响黑妞对话。")
        }
    }

    // MARK: - Home browser
    //
    // 设计理念（暗色工作台）：
    // 1) 主次：主行动 = 琥珀实心；次行动 = 描边卡片，绝不用两坨灰
    // 2) 温度：AppTheme.accent（暖琥珀）贯穿主按钮/选中态，对齐黑妞品牌
    // 3) 层次：背景最深 → 卡片抬一层 → 封面再抬一层，阴影克制
    // 4) 节奏：大操作区 → 筛选 → 网格，一眼能「开干」

    private var homeBrowser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("从这里开始")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("先立项记想法，或挂上本地素材夹。集数等剧本定了再拆。")
                        .font(.callout)
                        .foregroundStyle(AppTheme.textTertiary)
                }

                actionCards

                HStack(alignment: .center, spacing: 14) {
                    Text("最近项目")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    filterPills

                    Spacer(minLength: 0)
                }
                .padding(.top, 4)

                if filteredProjects.isEmpty {
                    emptyRecent
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 228, maximum: 268), spacing: 18, alignment: .top),
                        ],
                        spacing: 18
                    ) {
                        ForEach(filteredProjects) { item in
                            projectCard(item)
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionCards: some View {
        HStack(spacing: 14) {
            // 主行动：品牌琥珀，深色上的「唯一高饱和」
            actionCard(
                title: "新建空白项目",
                subtitle: "从一段文字或想法开始",
                systemImage: "plus",
                style: .primary,
                action: createBlankProject
            )
            // 次行动：同尺寸、低对比描边，不与主按钮抢戏
            actionCard(
                title: "打开已有文件夹",
                subtitle: "把素材文件夹变成项目",
                systemImage: "folder",
                style: .secondary,
                action: openExistingFolder
            )
            Spacer(minLength: 0)
        }
    }

    private enum ActionCardStyle {
        case primary
        case secondary
    }

    private func actionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        style: ActionCardStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(style == .primary ? Color.black.opacity(0.18) : AppTheme.accentSoft)
                        .frame(width: 46, height: 46)
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(style == .primary ? Color.black.opacity(0.82) : AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(style == .primary ? Color.black.opacity(0.88) : AppTheme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(style == .primary ? Color.black.opacity(0.55) : AppTheme.textTertiary)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 340, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(style == .primary ? AppTheme.accent : AppTheme.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        style == .primary ? Color.clear : AppTheme.strokeStrong,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: style == .primary
                    ? AppTheme.accent.opacity(0.28)
                    : Color.black.opacity(0.18),
                radius: style == .primary ? 14 : 8,
                y: 5
            )
        }
        .buttonStyle(.plain)
    }

    private var filterPills: some View {
        HStack(spacing: 0) {
            ForEach(ProjectHomeFilter.allCases) { f in
                let selected = filter == f
                Button {
                    filter = f
                } label: {
                    Text(f.title(local: localCount, external: externalCount, total: projects.projects.count))
                        .font(.caption.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.black.opacity(0.82) : AppTheme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(selected ? AppTheme.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule().fill(AppTheme.bgCard)
        )
        .overlay(
            Capsule().stroke(AppTheme.stroke, lineWidth: 1)
        )
    }

    private var emptyRecent: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 64, height: 64)
                Image(systemName: "film.stack")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }
            Text(projects.projects.isEmpty ? "还没有项目" : "此分类下暂无项目")
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("点上方琥珀色「新建空白项目」，或把素材夹挂进来。")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.bgCard.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }

    private func projectCard(_ item: ProjectItem) -> some View {
        Button {
            selectedID = item.id
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    // 封面：低饱和暖色系，围绕品牌琥珀，不用彩虹随机
                    LinearGradient(
                        colors: coverColors(for: item),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    // 轻暗角，让白字图标更稳
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack {
                        Spacer()
                        Image(systemName: item.isExternalFolder ? "folder.fill" : "film")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)

                    Text(item.status.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(10)
                }
                .frame(height: 148)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 16,
                        style: .continuous
                    )
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(item.cardTimestampText)
                        Text("·")
                        Text(item.relativeUpdatedText)
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.bgCard)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("打开") { selectedID = item.id }
            Button("编辑") { editorItem = item }
            if item.isExternalFolder, let path = item.folderPath {
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            Divider()
            Button("删除", role: .destructive) { pendingDelete = item }
        }
    }

    /// 封面色：以品牌琥珀为轴，按项目 ID 做小幅偏移，避免五颜六色。
    private func coverColors(for item: ProjectItem) -> [Color] {
        let seed = item.id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        // 琥珀附近：约 0.08（橙）± 小偏移
        let baseHue = 0.08
        let delta = Double(seed % 21 - 10) / 360.0 // ±10°
        let hue = (baseHue + delta + 1).truncatingRemainder(dividingBy: 1)
        if item.isExternalFolder {
            // 外部：略偏冷一点的深灰琥珀，暗示「素材夹」
            return [
                Color(hue: hue, saturation: 0.22, brightness: 0.42),
                Color(hue: hue, saturation: 0.28, brightness: 0.22),
            ]
        }
        return [
            Color(hue: hue, saturation: 0.55, brightness: 0.72),
            Color(hue: (hue + 0.03).truncatingRemainder(dividingBy: 1), saturation: 0.62, brightness: 0.38),
        ]
    }

    // MARK: - Detail

    private func projectDetail(_ project: ProjectItem) -> some View {
        // 顶栏 + 下方：左流程 / 右工作区（流程写在左边）
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    selectedID = nil
                } label: {
                    Label("最近项目", systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(1)
                    if !project.logline.isEmpty {
                        Text(project.logline)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Menu {
                    ForEach(ProjectStatus.allCases) { status in
                        Button {
                            setStatus(status, on: project)
                        } label: {
                            if project.status == status {
                                Label(status.title, systemImage: "checkmark")
                            } else {
                                Text(status.title)
                            }
                        }
                    }
                } label: {
                    StatusBadge(text: project.status.title, style: statusStyle(project.status))
                }
                .menuStyle(.borderlessButton)

                Menu {
                    Button("编辑项目信息") { editorItem = project }
                    if let path = project.folderPath, !path.isEmpty {
                        Button("在 Finder 中显示素材夹") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                    }
                    if let onOpenAgent, let writer = preferredWriterAgent() {
                        Button("用「\(writer.name)」聊聊") {
                            onOpenAgent(writer.id)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.4)

            ProjectPipelineView(
                project: project,
                pipeline: projects.pipeline(for: project.id)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailGrid(_ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    Text(row.0)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 72, alignment: .leading)
                    Text(row.1.isEmpty ? "—" : row.1)
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Actions

    private func createBlankProject() {
        // 默认名带时间戳，可直接回车创建
        newProjectName = "未命名项目 \(ProjectItem(name: "").cardTimestampText)"
        showCreateSheet = true
    }

    private func commitCreateProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = projects.addProject(named: name.isEmpty ? "未命名项目" : name)
        showCreateSheet = false
        newProjectName = ""
        selectedID = item.id
    }

    private func openExistingFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择文件夹"
        panel.message = "将素材文件夹登记为项目（不会移动文件）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let item = projects.importFolder(at: url)
        selectedID = item.id
    }

    private func setStatus(_ status: ProjectStatus, on project: ProjectItem) {
        var updated = project
        updated.status = status
        projects.updateProject(updated)
    }

    private func preferredWriterAgent() -> HeiNiuAgent? {
        let list = agents.sortedAgents
        if let named = list.first(where: { $0.name.contains("编剧") }) {
            return named
        }
        return list.first
    }

    private func statusStyle(_ status: ProjectStatus) -> StatusBadge.Style {
        switch status {
        case .idea, .planning: .neutral
        case .writing, .storyboard, .production: .accent
        case .done: .success
        case .archived: .neutral
        }
    }
}

/// 新建项目：只填名称的轻量 sheet。
private struct ProjectNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var name: String
    var onConfirm: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建空白项目")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("项目名")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                TextField("例如：青蛇与小和尚", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { onConfirm() }
            }

            Text("其它信息可之后在详情里再补。")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.textSecondary)
                Button("创建") { onConfirm() }
                    .buttonStyle(.plain)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .background(AppTheme.bgBase)
        .onAppear { focused = true }
    }
}
