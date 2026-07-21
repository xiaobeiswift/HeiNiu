/// PromptItem 模块。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// 提示词库中的一条可复用提示词。
///
/// 按 ``PromptCategory`` 分组；可绑定 LLM 服务商与模型。
///
/// - Note: 提示词库条目按短剧创作类别独立管理。
struct PromptItem: Identifiable, Codable, Hashable {
    /// 唯一 ID。
    var id: UUID
    /// 所属创作分类。
    var category: PromptCategory
    /// 显示名称。
    var name: String
    /// 提示词模板正文（可含 `{{variable}}`）。
    var template: String
    /// 绑定的 LLM 服务商；`nil` 表示未绑定。
    var providerID: UUID?
    /// 模型 ID。
    var model: String
    /// 采样温度。
    var temperature: Double
    /// 是否为系统内置；内置条目只读，只能复制为自定义副本。
    var isBuiltIn: Bool
    /// 同分类内排序权重，越小越靠前。
    var sortOrder: Int
    /// 最近更新时间。
    var updatedAt: Date

    /// 默认温度。
    static let defaultTemperature: Double = 0.7

    /// 创建提示词条目。
    init(
        id: UUID = UUID(),
        category: PromptCategory,
        name: String,
        template: String,
        providerID: UUID? = nil,
        model: String = "",
        temperature: Double = PromptItem.defaultTemperature,
        isBuiltIn: Bool = false,
        sortOrder: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.template = template
        self.providerID = providerID
        self.model = model
        self.temperature = temperature
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }

    /// 容错解码。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        category = try container.decodeIfPresent(PromptCategory.self, forKey: .category) ?? .script
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名提示词"
        template = try container.decodeIfPresent(String.self, forKey: .template) ?? ""
        providerID = try container.decodeIfPresent(UUID.self, forKey: .providerID)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? Self.defaultTemperature
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 唯一标识符。
        case id, category, name, template, providerID, model, temperature, isBuiltIn, sortOrder, updatedAt
    }
}
