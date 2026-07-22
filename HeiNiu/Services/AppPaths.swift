/// AppPaths 模块。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// 应用本地数据路径。
///
/// 所有持久化文件位于：
/// `~/Library/Application Support/HeiNiu/`
///
/// - Important: API Key **不**存放于此目录，而在钥匙串中。
/// - SeeAlso: ``KeychainHelper``；数据目录约定见文档「DataStorage」。
enum AppPaths {
    /// Application Support 下的应用根目录。
    static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("HeiNiu", isDirectory: true)
    }

    /// 设置文件（服务商、提示词、生图/生视频等）。
    static var settingsFileURL: URL {
        applicationSupportRoot.appendingPathComponent("settings.json", isDirectory: false)
    }

    /// 知识库根目录。
    static var knowledgeBaseRoot: URL {
        applicationSupportRoot.appendingPathComponent("KnowledgeBase", isDirectory: true)
    }

    /// 知识库 SQLite 数据库。
    static var knowledgeDatabaseURL: URL {
        knowledgeBaseRoot.appendingPathComponent("knowledge.sqlite", isDirectory: false)
    }

    /// 知识库原文件目录。
    static var knowledgeFilesRoot: URL {
        knowledgeBaseRoot.appendingPathComponent("Files", isDirectory: true)
    }

    /// 节点工作流根目录。
    static var workflowsRoot: URL {
        applicationSupportRoot.appendingPathComponent("Workflows", isDirectory: true)
    }

    /// 全部工作流模板定义文件。
    static var workflowDefinitionsURL: URL {
        workflowsRoot.appendingPathComponent("workflows.json", isDirectory: false)
    }

    /// 工作流运行历史根目录。
    static var workflowRunsRoot: URL {
        workflowsRoot.appendingPathComponent("Runs", isDirectory: true)
    }

    /// 项目卡片与分镜审核数据根目录。
    static var projectsRoot: URL {
        applicationSupportRoot.appendingPathComponent("Projects", isDirectory: true)
    }

    /// 当前项目看板文件；与历史根目录 `projects.json` 区分。
    static var projectBoardURL: URL {
        projectsRoot.appendingPathComponent("project-board.json", isDirectory: false)
    }

    /// 指定工作流的一次运行目录。
    static func workflowRunRoot(workflowID: UUID, runID: UUID) -> URL {
        workflowRunsRoot
            .appendingPathComponent(workflowID.uuidString, isDirectory: true)
            .appendingPathComponent(runID.uuidString, isDirectory: true)
    }

    /// 指定运行保存图片和视频的目录。
    static func workflowRunAssets(workflowID: UUID, runID: UUID) -> URL {
        workflowRunRoot(workflowID: workflowID, runID: runID)
            .appendingPathComponent("Assets", isDirectory: true)
    }

    /// 确保 Application Support 根目录与知识库目录存在。
    static func ensureDirectories() {
        let fm = FileManager.default
        for url in [
            applicationSupportRoot,
            knowledgeBaseRoot,
            knowledgeFilesRoot,
            workflowsRoot,
            workflowRunsRoot,
            projectsRoot,
        ] {
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

}
