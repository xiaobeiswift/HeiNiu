/// PromptCategory 模块。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// 提示词库的创作环节分类。
///
/// 每个分类下可挂多条 ``PromptItem``。
/// 生图 / 生视频的**文案模板**也在此管理；接口配置在各自设置页。
enum PromptCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    /// 剧本相关。
    case script
    /// 分镜相关。
    case storyboard
    /// 生图提示词。
    case image
    /// 生视频提示词。
    case video
    /// 角色提取与描述。
    case character
    /// 场景提取与氛围。
    case scene
    /// 物品 / 道具 / 产品。
    case item
    /// 图片资料理解、提炼与知识库入库。
    case knowledgeImport

    /// 稳定标识符（等于 `rawValue`）。
    var id: String { rawValue }

    /// 界面显示名称。
    var displayName: String {
        switch self {
        case .script: "剧本"
        case .storyboard: "分镜"
        case .image: "生图"
        case .video: "生视频"
        case .character: "角色"
        case .scene: "场景"
        case .item: "物品"
        case .knowledgeImport: "知识库添加"
        }
    }

    /// SF Symbol 名称。
    var systemImage: String {
        switch self {
        case .script: "doc.text"
        case .storyboard: "rectangle.split.3x1"
        case .image: "photo.artframe"
        case .video: "video.badge.waveform"
        case .character: "person.2"
        case .scene: "building.2"
        case .item: "shippingbox"
        case .knowledgeImport: "books.vertical.fill"
        }
    }

    /// 分类副标题（列表说明）。
    var subtitle: String {
        switch self {
        case .script: "大纲、对白、润色与改编"
        case .storyboard: "镜头表、节奏与运镜"
        case .image: "角色图、场景图、分镜参考"
        case .video: "镜头视频与风格提示"
        case .character: "角色卡与外形描述"
        case .scene: "场景卡与氛围描述"
        case .item: "道具、产品与关键物件"
        case .knowledgeImport: "图片理解、知识提炼与入库"
        }
    }

    /// 该分类模板中建议使用的变量名（不含花括号）。
    var suggestedVariables: [String] {
        switch self {
        case .script: ["brief", "product", "source", "style"]
        case .storyboard: ["script", "product", "duration"]
        case .image: ["subject", "style", "camera", "product"]
        case .video: ["shot", "storyboard", "style", "product"]
        case .character: ["script", "name", "traits"]
        case .scene: ["script", "location", "mood"]
        case .item: ["script", "name", "product", "details"]
        case .knowledgeImport: ["filename", "requirements"]
        }
    }

    /// 带 `{{ }}` 的变量芯片文案。
    var variableChips: [String] {
        suggestedVariables.map { "{{\($0)}}" }
    }
}
