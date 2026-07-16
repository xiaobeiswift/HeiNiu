/// 提示词模板变量替换。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// 将 `{{key}}` 替换为上下文值；未知键替换为空串。
///
/// 默认 MainActor isolation 下仍标 `nonisolated`，便于在后台拼超长提示词。
enum PromptTemplate {
    /// - Parameters:
    ///   - template: 含 `{{var}}` 的模板。
    ///   - values: 变量表。
    /// - Returns: 替换后的文本。
    nonisolated static func render(_ template: String, values: [String: String]) -> String {
        var result = template
        // 先替换已知键
        for (key, value) in values {
            let token = "{{\(key)}}"
            result = result.replacingOccurrences(of: token, with: value)
        }
        // 清掉残留 {{...}}
        if let regex = try? NSRegularExpression(pattern: #"\{\{[^}]+\}\}"#, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 从项目 + 流水线已有产物组装常用变量。
    nonisolated static func context(
        project: ProjectItem,
        pipeline: ProjectPipeline
    ) -> [String: String] {
        let duration: String = {
            if let s = project.episodeDurationSeconds, s > 0 {
                return "\(s) 秒"
            }
            return "90 秒"
        }()
        let episodes: String = {
            if let n = project.targetEpisodeCount, n > 0 { return "\(n)" }
            return "未指定"
        }()

        let brief = [
            project.logline.isEmpty ? nil : "卖点：\(project.logline)",
            project.synopsis.isEmpty ? nil : "概要：\(project.synopsis)",
            project.genre.isEmpty ? nil : "题材：\(project.genre)",
            project.audience.isEmpty ? nil : "受众：\(project.audience)",
            "目标单集时长：\(duration)",
            "预估集数：\(episodes)",
            project.notes.isEmpty ? nil : "备注：\(project.notes)",
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

        return [
            "brief": brief.isEmpty ? project.name : brief,
            "product": project.name,
            "style": project.genre,
            "source": pipeline.step(.script).outputText,
            "script": pipeline.step(.script).outputText,
            "segments": pipeline.step(.segment).outputText,
            "characters": pipeline.step(.characters).outputText,
            "scenes": pipeline.step(.scenes).outputText,
            "items": pipeline.step(.items).outputText,
            "duration": duration,
            "name": project.name,
            "location": "",
            "mood": "",
            "traits": "",
            "details": "",
            "subject": "",
            "camera": "",
            "shot": "",
            "storyboard": pipeline.step(.segment).outputText,
        ]
    }
}
