import Foundation

/// 提示词库中的一条可复用提示词
struct PromptItem: Identifiable, Codable, Hashable {
    var id: UUID
    var category: PromptCategory
    var name: String
    var template: String
    var providerID: UUID?
    var model: String
    var temperature: Double
    /// 是否为系统预置（可改模板，删除时给确认提示）
    var isBuiltIn: Bool
    var sortOrder: Int
    var updatedAt: Date

    static let defaultTemperature: Double = 0.7

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

    private enum CodingKeys: String, CodingKey {
        case id, category, name, template, providerID, model, temperature, isBuiltIn, sortOrder, updatedAt
    }
}
