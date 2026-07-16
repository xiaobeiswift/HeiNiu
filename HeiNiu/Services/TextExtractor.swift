/// 从本地文件抽取可注入上下文的文本。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation
import UniformTypeIdentifiers

/// 从本地文件抽取可注入上下文的文本。
enum TextExtractor {
    /// 抽取结果。
    struct Result: Sendable {
        /// 正文或说明。
        var text: String
        /// 文件字节数。
        var byteSize: Int
        /// MIME 提示。
        var mime: String
        /// 是否成功读到可用正文（非占位说明）。
        var didExtractContent: Bool
        /// 失败原因（如有）。
        var errorMessage: String?
    }

    /// 从本地文件抽取可注入上下文的文本；不支持的类型返回文件名说明。
    ///
    /// 会尝试 `startAccessingSecurityScopedResource()`，适配面板/拖放路径。
    static func extract(from url: URL, maxCharacters: Int = 80_000) -> (text: String, byteSize: Int, mime: String) {
        let result = extractDetailed(from: url, maxCharacters: maxCharacters)
        return (result.text, result.byteSize, result.mime)
    }

    /// 带成功标记的抽取，便于 UI 提示。
    static func extractDetailed(from url: URL, maxCharacters: Int = 80_000) -> Result {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let standardized = url.standardizedFileURL
        let values = try? standardized.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .isRegularFileKey])
        let size = values?.fileSize ?? (try? Data(contentsOf: standardized).count) ?? 0
        let type = values?.contentType
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        let name = standardized.lastPathComponent
        let ext = standardized.pathExtension.lowercased()

        guard FileManager.default.fileExists(atPath: standardized.path) else {
            return Result(
                text: "【无法读取：文件不存在\n\(standardized.path)】",
                byteSize: 0,
                mime: mime,
                didExtractContent: false,
                errorMessage: "文件不存在"
            )
        }

        let textExtensions: Set<String> = [
            "txt", "md", "markdown", "json", "csv", "tsv", "log",
            "swift", "py", "js", "ts", "tsx", "jsx", "html", "css",
            "xml", "yaml", "yml", "toml", "ini", "env", "sh", "zsh",
            "c", "h", "cpp", "m", "mm", "java", "kt", "go", "rs", "rb",
            "prompt", "srt", "vtt", "fountain", "text", "rtf",
        ]

        let looksText = textExtensions.contains(ext)
            || type?.conforms(to: .plainText) == true
            || type?.conforms(to: .sourceCode) == true
            || type?.conforms(to: .json) == true
            || type?.conforms(to: .xml) == true
            || type?.conforms(to: .html) == true
            || type?.conforms(to: .commaSeparatedText) == true
            || type?.conforms(to: .rtf) == true
            || ext.isEmpty

        if looksText {
            if let raw = readText(from: standardized) {
                return Result(
                    text: truncate(raw, max: maxCharacters),
                    byteSize: size,
                    mime: mime,
                    didExtractContent: true,
                    errorMessage: nil
                )
            }
            // 文本类扩展但读失败：仍给出明确错误
            if textExtensions.contains(ext) {
                return Result(
                    text: "【无法读取文本文件：\(name)。请确认有权限访问，或复制正文粘贴。】",
                    byteSize: size,
                    mime: mime,
                    didExtractContent: false,
                    errorMessage: "读取失败"
                )
            }
        }

        if type?.conforms(to: .pdf) == true || ext == "pdf" {
            let note = "【PDF 文件：\(name)，\(size) 字节。当前版本请粘贴关键段落或导出为 txt/md。】"
            return Result(text: note, byteSize: size, mime: "application/pdf", didExtractContent: false, errorMessage: "PDF 暂不解析")
        }
        if type?.conforms(to: .image) == true {
            let note = "【图片：\(name)。当前以文本上下文为主，请补充画面描述。】"
            return Result(text: note, byteSize: size, mime: mime, didExtractContent: false, errorMessage: "图片暂不 OCR")
        }

        // 未知类型：再盲读一次，很多无扩展名/冷门扩展其实是 UTF-8 文本
        if let raw = readText(from: standardized), isMostlyPrintable(raw) {
            return Result(
                text: truncate(raw, max: maxCharacters),
                byteSize: size,
                mime: mime,
                didExtractContent: true,
                errorMessage: nil
            )
        }

        let note = "【已附加文件：\(name)（\(ext.isEmpty ? "未知类型" : ext)，\(size) 字节）。未能自动抽取正文，请复制内容粘贴。】"
        return Result(text: note, byteSize: size, mime: mime, didExtractContent: false, errorMessage: "无法抽取正文")
    }

    /// 若字符串本身就是本地文件路径 / file URL，返回对应 URL。
    static func fileURLIfPathOnly(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { return nil }

        if trimmed.lowercased().hasPrefix("file://"),
           let url = URL(string: trimmed),
           url.isFileURL {
            return url
        }

        // 绝对路径：/Users/... 或 /Volumes/...
        if trimmed.hasPrefix("/") {
            let url = URL(fileURLWithPath: trimmed)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            // 去掉可能的包裹引号
            let unquoted = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if unquoted != trimmed {
                let u = URL(fileURLWithPath: unquoted)
                if FileManager.default.fileExists(atPath: u.path) { return u }
            }
        }
        return nil
    }

    /// 截断过长文本。
    static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        let idx = text.index(text.startIndex, offsetBy: max)
        return String(text[..<idx]) + "\n\n…（已截断，原长度 \(text.count) 字符）"
    }

    // MARK: - Private

    private static func readText(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
        if let latin1 = String(data: data, encoding: .isoLatin1) { return latin1 }
        // 尽量用 lossy UTF-8
        return String(decoding: data, as: UTF8.self)
    }

    private static func isMostlyPrintable(_ text: String) -> Bool {
        let sample = text.prefix(4000)
        guard !sample.isEmpty else { return false }
        var bad = 0
        for ch in sample {
            if ch == "\u{FFFD}" || (ch.unicodeScalars.count == 1 && ch.unicodeScalars.first!.value < 9) {
                bad += 1
            }
        }
        return Double(bad) / Double(sample.count) < 0.05
    }
}
