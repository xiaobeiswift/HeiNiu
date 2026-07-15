import Foundation

/// 创作环节分类：每个分类下可挂多条提示词
enum PromptCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case script
    case storyboard
    case image
    case video
    case character
    case scene
    case item

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .script: "剧本"
        case .storyboard: "分镜"
        case .image: "生图"
        case .video: "生视频"
        case .character: "角色"
        case .scene: "场景"
        case .item: "物品"
        }
    }

    var systemImage: String {
        switch self {
        case .script: "doc.text"
        case .storyboard: "rectangle.split.3x1"
        case .image: "photo.artframe"
        case .video: "video.badge.waveform"
        case .character: "person.2"
        case .scene: "building.2"
        case .item: "shippingbox"
        }
    }

    var subtitle: String {
        switch self {
        case .script: "大纲、对白、润色与改编"
        case .storyboard: "镜头表、节奏与运镜"
        case .image: "角色图、场景图、分镜参考"
        case .video: "镜头视频与风格提示"
        case .character: "角色卡与外形描述"
        case .scene: "场景卡与氛围描述"
        case .item: "道具、产品与关键物件"
        }
    }

    /// 该分类下常用变量（新建提示词时作为提示）
    var suggestedVariables: [String] {
        switch self {
        case .script: ["brief", "product", "source", "style"]
        case .storyboard: ["script", "product", "duration"]
        case .image: ["subject", "style", "camera", "product"]
        case .video: ["shot", "storyboard", "style", "product"]
        case .character: ["script", "name", "traits"]
        case .scene: ["script", "location", "mood"]
        case .item: ["script", "name", "product", "details"]
        }
    }

    var variableChips: [String] {
        suggestedVariables.map { "{{\($0)}}" }
    }
}
