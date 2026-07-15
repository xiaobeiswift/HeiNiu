/// 从本地文件抽取可注入上下文的文本。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation
import UniformTypeIdentifiers

/// TextExtractor
///
/// `TextExtractor` 类型定义。
enum TextExtractor {
    /// 从本地文件抽取可注入上下文的文本；不支持的类型返回文件名说明
    static func extract(from url: URL, maxCharacters: Int = 80_000) -> (text: String, byteSize: Int, mime: String) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let size = values?.fileSize ?? 0
        let type = values?.contentType
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        let name = url.lastPathComponent

        /// textExtensions。
        let textExtensions: Set<String> = [
            "txt", "md", "markdown", "json", "csv", "tsv", "log",
            "swift", "py", "js", "ts", "tsx", "jsx", "html", "css",
            "xml", "yaml", "yml", "toml", "ini", "env", "sh", "zsh",
            "c", "h", "cpp", "m", "mm", "java", "kt", "go", "rs", "rb",
            "prompt", "srt", "vtt",
        ]

        let ext = url.pathExtension.lowercased()
        if textExtensions.contains(ext)
            || type?.conforms(to: .plainText) == true
            || type?.conforms(to: .sourceCode) == true
            || type?.conforms(to: .json) == true
            || type?.conforms(to: .xml) == true
            || type?.conforms(to: .html) == true
            || type?.conforms(to: .commaSeparatedText) == true
        {
            if let data = try? Data(contentsOf: url),
               let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
            {
                return (truncate(raw, max: maxCharacters), size, mime)
            }
        }

        // PDF / 图片等：先给占位说明（后续可接 OCR/PDFKit）
        if type?.conforms(to: .pdf) == true || ext == "pdf" {
            let note = "【PDF 文件：\(name)，\(size) 字节。当前版本请粘贴关键段落或导出为 txt/md 以进入知识库。】"
            return (note, size, "application/pdf")
        }
        if type?.conforms(to: .image) == true {
            let note = "【图片：\(name)。当前聊天以文本上下文为主，可在描述中说明画面内容。】"
            return (note, size, mime)
        }

        let note = "【已附加文件：\(name)（\(ext.isEmpty ? "未知类型" : ext)，\(size) 字节）。未能自动抽取正文，请补充说明。】"
        return (note, size, mime)
    }

    /// 截断过长文本
    ///
    /// 截断过长文本。
    static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        let idx = text.index(text.startIndex, offsetBy: max)
        return String(text[..<idx]) + "\n\n…（已截断，原长度 \(text.count) 字符）"
    }
}
