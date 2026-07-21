/// 应用入口文件。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// 黑妞短剧应用入口。
///
/// 创建并注入全局状态：
/// - ``SettingsStore``：服务商、提示词与备份等配置
/// - ``KnowledgeStore``：全局知识库、向量索引与检索
/// - ``WorkflowStore``：全局节点工作流与运行历史
///
/// 主界面为 ``MainView``，默认窗口约 1440×860。
/// HeiNiuApp
///
/// `HeiNiuApp` 类型定义。
@main
struct HeiNiuApp: App {
    /// 全局设置仓库（服务商 / 提示词 / 生图生视频 / 备份）。
    @State private var settings = SettingsStore()
    /// 全局知识库。
    @State private var knowledgeStore = KnowledgeStore()
    /// 全局节点工作流与运行历史。
    @State private var workflowStore = WorkflowStore()

    /// 场景：主窗口。
    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(settings)
                .environment(knowledgeStore)
                .environment(workflowStore)
                .frame(minWidth: 1200, minHeight: 720)
                .background(AppTheme.bgBase)
        }
        .defaultSize(width: 1440, height: 860)
    }
}
