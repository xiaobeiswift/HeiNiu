/// 应用入口文件。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// 黑妞短剧应用入口。
///
/// 创建并注入全局状态：
/// - ``SettingsStore``：服务商、提示词与备份等配置
/// - ``ProjectStore``：短剧项目立项看板
/// - ``KnowledgeStore``：全局知识库、向量索引与检索
///
/// 主界面为 ``MainView``，默认窗口约 1280×820。
/// HeiNiuApp
///
/// `HeiNiuApp` 类型定义。
@main
struct HeiNiuApp: App {
    /// 全局设置仓库（服务商 / 提示词 / 生图生视频 / 备份）。
    @State private var settings = SettingsStore()
    /// 短剧项目仓库（立项看板，与会话独立）。
    @State private var projectStore = ProjectStore()
    /// 全局知识库。
    @State private var knowledgeStore = KnowledgeStore()

    /// 场景：主窗口。
    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(settings)
                .environment(projectStore)
                .environment(knowledgeStore)
                .frame(minWidth: 1040, minHeight: 680)
                .background(AppTheme.bgBase)
        }
        .defaultSize(width: 1280, height: 820)
    }
}
