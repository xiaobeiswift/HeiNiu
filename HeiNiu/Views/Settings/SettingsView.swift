/// 设置页顶部分段容器。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// SettingsPane
///
/// `SettingsPane` 类型定义。
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    /// LLM 服务商列表
    ///
    /// LLM 服务商列表。
    case providers
    /// prompts。
    case prompts
    /// imageGen。
    case imageGen
    /// videoGen。
    case videoGen
    /// backup。
    case backup

    /// 唯一标识符。
    var id: String { rawValue }

    /// 标题。
    var title: String {
        switch self {
        case .providers: "服务商"
        case .prompts: "提示词"
        case .imageGen: "生图"
        case .videoGen: "生视频"
        case .backup: "备份"
        }
    }

    /// 用于 UI 的 SF Symbol。
    var systemImage: String {
        switch self {
        case .providers: "server.rack"
        case .prompts: "text.book.closed"
        case .imageGen: "photo.artframe"
        case .videoGen: "video.badge.waveform"
        case .backup: "externaldrive.badge.timemachine"
        }
    }

    /// tabItems。
    static var tabItems: [StudioTabItem] {
        allCases.map { StudioTabItem(id: $0.rawValue, title: $0.title, systemImage: $0.systemImage) }
    }
}

/// SettingsView
///
/// `SettingsView` 类型定义。
struct SettingsView: View {
    @State private var paneRaw: String = SettingsPane.providers.rawValue
    @State private var showSaved = false
    @State private var savedHideTask: Task<Void, Never>?

    /// pane。
    private var pane: SettingsPane {
        SettingsPane(rawValue: paneRaw) ?? .providers
    }

    /// SwiftUI 视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 16)

            // 统一外层滚动；提示词模板编辑器自身固定高度，不会再撑开此 ScrollView
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    switch pane {
                    case .providers:
                        ProvidersSettingsView(onSaved: flashSaved)
                    case .prompts:
                        PromptsSettingsView(onSaved: flashSaved)
                    case .imageGen:
                        ImageGenSettingsView(onSaved: flashSaved)
                    case .videoGen:
                        VideoGenSettingsView(onSaved: flashSaved)
                    case .backup:
                        BackupSettingsView(onSaved: flashSaved)
                    }
                }
                .studioContentWidth()
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            }
        }
        .background(AppTheme.bgBase)
    }

    /// header。
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.largeTitle.weight(.bold))
                    Text("LLM · 提示词库 · 生图 / 生视频 · 备份迁移")
                        .font(.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                AutoSaveIndicator(visible: showSaved)
            }

            StudioTabBar(items: SettingsPane.tabItems, selection: $paneRaw)
        }
        .studioContentWidth()
    }

    /// flashSaved
    ///
    /// 执行 `flashSaved` 相关逻辑。
    private func flashSaved() {
        showSaved = true
        savedHideTask?.cancel()
        savedHideTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            showSaved = false
        }
    }
}

#Preview {
    SettingsView()
        .environment(SettingsStore())
        .environment(KnowledgeStore())
        .environment(PixmaxSessionManager.shared)
        .frame(width: 960, height: 720)
}
