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

    /// 确保 Application Support 根目录与知识库目录存在。
    static func ensureDirectories() {
        let fm = FileManager.default
        for url in [applicationSupportRoot, knowledgeBaseRoot, knowledgeFilesRoot] {
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

}
