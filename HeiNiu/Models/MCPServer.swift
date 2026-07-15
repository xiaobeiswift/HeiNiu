/// MCP 服务器与传输类型。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// MCP 传输方式：Stdio / SSE / HTTP。
///
enum MCPTransport: String, Codable, CaseIterable, Identifiable, Hashable {
    /// stdio。
    case stdio
    /// sse。
    case sse
    /// http。
    case http

    /// 唯一标识符。
    var id: String { rawValue }

    /// 界面显示名称。
    var displayName: String {
        switch self {
        case .stdio: "Stdio"
        case .sse: "SSE"
        case .http: "HTTP"
        }
    }

    /// 提示文案。
    var hint: String {
        switch self {
        case .stdio: "本地命令启动（command + args）"
        case .sse: "Server-Sent Events 远程端点"
        case .http: "HTTP 传输端点"
        }
    }
}

/// 全局 MCP 服务器配置。
///
/// 可在「配置 → MCP」用表单或 JSON 编辑；黑妞通过 ``AgentMCPMode`` 选择是否使用。
///
/// - SeeAlso: ``MCPTransport``, ``SettingsStore/mcpServers``
///
struct MCPServer: Identifiable, Codable, Hashable {
    /// 唯一标识符。
    var id: UUID
    /// 显示名称。
    var name: String
    /// MCP 传输类型。
    var transport: MCPTransport
    /// stdio: 可执行文件路径或命令
    var command: String
    /// 命令行参数。
    var arguments: [String]
    /// sse / http
    var url: String
    /// 环境变量 KEY=VALUE，每行一个
    var envText: String
    /// 备注。
    var notes: String
    /// 是否启用。
    var isEnabled: Bool
    /// 创建时间。
    var createdAt: Date
    /// 最近更新时间。
    var updatedAt: Date

    /// 初始化方法
    ///
    /// 初始化方法。
    init(
        id: UUID = UUID(),
        name: String,
        transport: MCPTransport = .stdio,
        command: String = "",
        arguments: [String] = [],
        url: String = "",
        envText: String = "",
        notes: String = "",
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.command = command
        self.arguments = arguments
        self.url = url
        self.envText = envText
        self.notes = notes
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 副标题或说明文案。
    var subtitle: String {
        switch transport {
        case .stdio:
            let args = arguments.joined(separator: " ")
            let cmd = command.isEmpty ? "未设置命令" : command
            return args.isEmpty ? "\(transport.displayName) · \(cmd)" : "\(transport.displayName) · \(cmd) \(args)"
        case .sse, .http:
            return "\(transport.displayName) · \(url.isEmpty ? "未设置 URL" : url)"
        }
    }

    /// 初始化方法
    ///
    /// 初始化方法。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "MCP 服务器"
        transport = try c.decodeIfPresent(MCPTransport.self, forKey: .transport) ?? .stdio
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        arguments = try c.decodeIfPresent([String].self, forKey: .arguments) ?? []
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        envText = try c.decodeIfPresent(String.self, forKey: .envText) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// CodingKeys
    ///
    /// `CodingKeys` 类型定义。
    private enum CodingKeys: String, CodingKey {
        /// 唯一标识符。
        case id, name, transport, command, arguments, url, envText, notes, isEnabled, createdAt, updatedAt
    }
}
