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
/// - SeeAlso: ``KeychainHelper``, ``DataStorage``
enum AppPaths {
    /// Application Support 下的应用根目录。
    static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("HeiNiu", isDirectory: true)
    }

    /// 设置文件（服务商、提示词、生图/生视频、MCP 等）。
    static var settingsFileURL: URL {
        applicationSupportRoot.appendingPathComponent("settings.json", isDirectory: false)
    }

    /// 黑妞角色列表。
    static var agentsFileURL: URL {
        applicationSupportRoot.appendingPathComponent("agents.json", isDirectory: false)
    }

    /// 黑妞对话历史。
    static var conversationsFileURL: URL {
        applicationSupportRoot.appendingPathComponent("conversations.json", isDirectory: false)
    }

    /// 知识库索引（元数据 + 抽取文本）。
    static var knowledgeIndexFileURL: URL {
        applicationSupportRoot.appendingPathComponent("knowledge.json", isDirectory: false)
    }

    /// 技能库。
    static var skillsFileURL: URL {
        applicationSupportRoot.appendingPathComponent("skills.json", isDirectory: false)
    }

    /// 插件库。
    static var pluginsFileURL: URL {
        applicationSupportRoot.appendingPathComponent("plugins.json", isDirectory: false)
    }

    /// 知识库原文件根目录。
    static var knowledgeRoot: URL {
        applicationSupportRoot.appendingPathComponent("Knowledge", isDirectory: true)
    }

    /// 指定黑妞的知识库目录。
    /// - Parameter agentID: 黑妞 ID。
    /// - Returns: `Knowledge/<agentID>/` 目录 URL。
    static func knowledgeDirectory(for agentID: UUID) -> URL {
        knowledgeRoot.appendingPathComponent(agentID.uuidString, isDirectory: true)
    }

    /// 确保 Application Support 根目录与知识库根目录存在。
    static func ensureDirectories() {
        let fm = FileManager.default
        for url in [applicationSupportRoot, knowledgeRoot] {
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    /// 确保某黑妞的知识库目录存在并返回。
    /// - Parameter agentID: 黑妞 ID。
    /// - Returns: 已创建（或已存在）的目录 URL。
    static func ensureKnowledgeDirectory(for agentID: UUID) -> URL {
        let dir = knowledgeDirectory(for: agentID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
