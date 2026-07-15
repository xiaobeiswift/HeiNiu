import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case learn
    case scripts
    case storyboards
    case assets
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .learn: "学习"
        case .scripts: "剧本"
        case .storyboards: "分镜"
        case .assets: "资产库"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .learn: "graduationcap"
        case .scripts: "doc.text"
        case .storyboards: "rectangle.split.3x1"
        case .assets: "square.grid.2x2"
        case .settings: "gearshape"
        }
    }

    static let workspaceItems: [SidebarItem] = [.learn, .scripts, .storyboards, .assets]
    static let configItems: [SidebarItem] = [.settings]
}

struct MainView: View {
    @State private var selection: SidebarItem? = .settings

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: 180,
                    ideal: AppTheme.sidebarWidth,
                    max: 260
                )
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.bgBase)
        }
        .background(AppTheme.bgBase)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.accentSoft)
                        .frame(width: 28, height: 28)
                    Image(systemName: "film.stack")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("黑妞短剧")
                        .font(.headline)
                    Text("短剧创作工作台")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            List(selection: $selection) {
                Section {
                    ForEach(SidebarItem.workspaceItems) { item in
                        sidebarRow(item)
                    }
                } header: {
                    Text("工作台")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Section {
                    ForEach(SidebarItem.configItems) { item in
                        sidebarRow(item)
                    }
                } header: {
                    Text("配置")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)
        }
        .background(AppTheme.bgSidebar)
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .tag(item)
            .font(.body)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .learn:
            PlaceholderView(
                title: "学习",
                systemImage: "graduationcap",
                message: "从参考视频中提炼产品卖点、拍摄清单与提示词。",
                badge: "即将推出"
            )
        case .scripts:
            PlaceholderView(
                title: "剧本",
                systemImage: "doc.text",
                message: "根据简报或源文本生成短剧剧本。",
                badge: "即将推出"
            )
        case .storyboards:
            PlaceholderView(
                title: "分镜",
                systemImage: "rectangle.split.3x1",
                message: "将剧本拆成镜头，并生成视频提示词。",
                badge: "即将推出"
            )
        case .assets:
            PlaceholderView(
                title: "资产库",
                systemImage: "square.grid.2x2",
                message: "管理角色、场景与道具等可复用资产。",
                badge: "即将推出"
            )
        case .settings, .none:
            SettingsView()
        }
    }
}

#Preview {
    MainView()
        .environment(SettingsStore())
        .frame(width: 1180, height: 760)
}
