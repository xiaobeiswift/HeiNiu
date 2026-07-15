import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case providers
    case prompts
    case imageGen
    case videoGen
    case backup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .providers: "服务商"
        case .prompts: "提示词"
        case .imageGen: "生图"
        case .videoGen: "生视频"
        case .backup: "备份"
        }
    }

    var systemImage: String {
        switch self {
        case .providers: "server.rack"
        case .prompts: "text.book.closed"
        case .imageGen: "photo.artframe"
        case .videoGen: "video.badge.waveform"
        case .backup: "externaldrive.badge.timemachine"
        }
    }

    static var tabItems: [StudioTabItem] {
        allCases.map { StudioTabItem(id: $0.rawValue, title: $0.title, systemImage: $0.systemImage) }
    }
}

struct SettingsView: View {
    @State private var paneRaw: String = SettingsPane.providers.rawValue
    @State private var showSaved = false
    @State private var savedHideTask: Task<Void, Never>?

    private var pane: SettingsPane {
        SettingsPane(rawValue: paneRaw) ?? .providers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 16)

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
        .frame(width: 960, height: 720)
}
