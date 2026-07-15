/// 全局 MCP 服务器清单与表单/JSON 编辑。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// 全局 MCP 服务器清单（配置 → MCP）
struct MCPSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(HeiNiuAgentStore.self) private var agents
    @State private var editing: MCPServer?
    @State private var creating: MCPServer?
    @State private var pendingDelete: MCPServer?

    /// SwiftUI 视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MCP 服务器")
                        .font(.title3.weight(.semibold))
                    Text("支持表单配置或粘贴 JSON；各黑妞在编辑页选择禁用 / 自动 / 手动")
                        .font(.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Button {
                    creating = MCPServer(name: "新 MCP 服务器")
                } label: {
                    Label("添加服务器", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.accent, in: Capsule())
                        .foregroundStyle(.black.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            if settings.mcpServers.isEmpty {
                StudioCard {
                    EmptyStateView(
                        title: "还没有 MCP 服务器",
                        message: "可用表单填写，或直接粘贴 Cursor / Claude 风格的 MCP JSON。",
                        systemImage: "server.rack",
                        actionTitle: "添加服务器",
                        action: { creating = MCPServer(name: "新 MCP 服务器") }
                    )
                    .frame(minHeight: 240)
                }
            } else {
                ForEach(settings.sortedMCPServers) { server in
                    serverRow(server)
                }
            }
        }
        .sheet(item: $editing) { server in
            MCPServerEditorSheet(server: server) { updated in
                settings.updateMCPServer(updated)
            }
            .frame(width: 560, height: 620)
        }
        .sheet(item: $creating) { server in
            MCPServerEditorSheet(server: server) { updated in
                if settings.mcpServer(id: updated.id) == nil {
                    settings.mcpServers.append(updated)
                    settings.save()
                } else {
                    settings.updateMCPServer(updated)
                }
            }
            .frame(width: 560, height: 620)
        }
        .confirmationDialog(
            "删除「\(pendingDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = pendingDelete?.id {
                    settings.deleteMCPServer(id: id)
                    agents.purgeMCPReferences(serverID: id)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }

    /// serverRow
    ///
    /// 执行 `serverRow` 相关逻辑。
    private func serverRow(_ server: MCPServer) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(server.name)
                        .font(.headline)
                    StatusBadge(text: server.transport.displayName, style: .accent)
                    if !server.isEnabled {
                        StatusBadge(text: "已禁用", style: .neutral)
                    }
                }
                Text(server.subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
            Toggle("启用", isOn: Binding(
                get: { server.isEnabled },
                set: { on in
                    var s = server
                    s.isEnabled = on
                    settings.updateMCPServer(s)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)

            Button {
                editing = server
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                pendingDelete = server
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(AppTheme.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
        .opacity(server.isEnabled ? 1 : 0.65)
    }
}

// MARK: - Editor (Form / JSON)

/// MCPEditorMode
///
/// `MCPEditorMode` 类型定义。
private enum MCPEditorMode: String, CaseIterable, Identifiable {
    /// form。
    case form
    /// json。
    case json

    /// 唯一标识符。
    var id: String { rawValue }

    /// 标题。
    var title: String {
        switch self {
        case .form: "表单"
        case .json: "JSON"
        }
    }
}

/// MCPServerEditorSheet
///
/// `MCPServerEditorSheet` 类型定义。
struct MCPServerEditorSheet: View {
    /// onSave。
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MCPServer
    let onSave: (MCPServer) -> Void

    @State private var mode: MCPEditorMode = .form
    @State private var argsText: String = ""
    @State private var jsonText: String = ""
    @State private var jsonError: String?
    @State private var jsonHint: String?

    /// 初始化方法
    ///
    /// 初始化方法。
    init(server: MCPServer, onSave: @escaping (MCPServer) -> Void) {
        _draft = State(initialValue: server)
        self.onSave = onSave
        _argsText = State(initialValue: server.arguments.joined(separator: " "))
        _jsonText = State(initialValue: MCPJSONCodec.encodePretty(server))
    }

    /// SwiftUI 视图内容。
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("编辑方式", selection: $mode) {
                    ForEach(MCPEditorMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .onChange(of: mode) { old, new in
                    switch (old, new) {
                    case (.form, .json):
                        // 表单 → JSON：同步当前表单
                        applyArgsToDraft()
                        jsonText = MCPJSONCodec.encodePretty(draft)
                        jsonError = nil
                        jsonHint = "可粘贴完整 mcpServers 片段，或单台服务器对象"
                    case (.json, .form):
                        // JSON → 表单：尝试解析
                        applyJSONToDraft(showError: true)
                    default:
                        break
                    }
                }

                Group {
                    switch mode {
                    case .form:
                        formEditor
                    case .json:
                        jsonEditor
                    }
                }
            }
            .background(AppTheme.bgBase)
            .navigationTitle("MCP 服务器")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    // MARK: - Form

    /// formEditor。
    private var formEditor: some View {
        Form {
            Section("基本") {
                TextField("名称", text: $draft.name)
                Picker("传输", selection: $draft.transport) {
                    ForEach(MCPTransport.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                Text(draft.transport.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("启用", isOn: $draft.isEnabled)
            }

            if draft.transport == .stdio {
                Section("Stdio") {
                    TextField("命令 / 可执行路径", text: $draft.command)
                    TextField("参数（空格分隔）", text: $argsText)
                }
            } else {
                Section("远程") {
                    TextField("URL", text: $draft.url)
                }
            }

            Section("环境变量") {
                TextEditor(text: $draft.envText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)
                Text("每行一个 KEY=VALUE")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("备注") {
                TextField("可选说明", text: $draft.notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - JSON

    /// jsonEditor。
    private var jsonEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("粘贴 MCP 配置 JSON")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20)

            Text(jsonHint ?? "支持：单台对象、{ \"name\": { command, args… } }、{ \"mcpServers\": { … } }")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.horizontal, 20)

            TextEditor(text: $jsonText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.bgElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(jsonError == nil ? AppTheme.stroke : AppTheme.danger.opacity(0.6), lineWidth: 1)
                )
                .padding(.horizontal, 20)

            HStack(spacing: 10) {
                Button("从当前表单生成") {
                    applyArgsToDraft()
                    jsonText = MCPJSONCodec.encodePretty(draft)
                    jsonError = nil
                    jsonHint = "已从当前配置生成"
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)

                Button("校验并应用") {
                    applyJSONToDraft(showError: true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)

                Spacer()
            }
            .padding(.horizontal, 20)

            if let jsonError {
                Text(jsonError)
                    .font(.caption)
                    .foregroundStyle(AppTheme.danger)
                    .padding(.horizontal, 20)
            }

            Spacer(minLength: 8)
        }
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    // MARK: - Save / Sync

    /// applyArgsToDraft
    ///
    /// 执行 `applyArgsToDraft` 相关逻辑。
    private func applyArgsToDraft() {
        draft.arguments = argsText
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    /// applyJSONToDraft
    ///
    /// 执行 `applyJSONToDraft` 相关逻辑。
    private func applyJSONToDraft(showError: Bool) {
        do {
            let parsed = try MCPJSONCodec.decode(jsonText, fallbackID: draft.id)
            draft = parsed
            argsText = parsed.arguments.joined(separator: " ")
            jsonError = nil
            jsonHint = "JSON 已应用到表单字段"
        } catch {
            if showError {
                jsonError = error.localizedDescription
            }
        }
    }

    /// 将当前状态写入磁盘
    ///
    /// 将当前状态写入磁盘。
    private func save() {
        if mode == .json {
            applyJSONToDraft(showError: true)
            if jsonError != nil { return }
        } else {
            applyArgsToDraft()
        }
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.name.isEmpty { draft.name = "MCP 服务器" }
        onSave(draft)
        dismiss()
    }
}

// MARK: - JSON codec

/// MCPJSONCodec
///
/// `MCPJSONCodec` 类型定义。
enum MCPJSONCodec {
    /// DecodeError
    ///
    /// `DecodeError` 类型定义。
    enum DecodeError: LocalizedError {
        /// invalidJSON。
        case invalidJSON
        /// empty。
        case empty
        /// unsupported。
        case unsupported

        var errorDescription: String? {
            switch self {
            case .invalidJSON: "JSON 无法解析"
            case .empty: "JSON 为空"
            case .unsupported: "无法识别的 MCP JSON 结构"
            }
        }
    }

    /// encodePretty
    ///
    /// 执行 `encodePretty` 相关逻辑。
    static func encodePretty(_ server: MCPServer) -> String {
        // 输出常见 mcpServers 片段，便于复制到其它工具
        var entry: [String: Any] = [:]
        switch server.transport {
        case .stdio:
            entry["command"] = server.command
            if !server.arguments.isEmpty {
                entry["args"] = server.arguments
            }
        case .sse, .http:
            entry["url"] = server.url
            entry["transport"] = server.transport.rawValue
        }
        if let env = envDictionary(from: server.envText), !env.isEmpty {
            entry["env"] = env
        }
        if !server.notes.isEmpty {
            entry["notes"] = server.notes
        }
        entry["disabled"] = !server.isEnabled

        /// root。
        let root: [String: Any] = [
            "mcpServers": [
                server.name: entry
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{\n  \"mcpServers\": {}\n}"
        }
        return text
    }

    /// decode
    ///
    /// 执行 `decode` 相关逻辑。
    static func decode(_ text: String, fallbackID: UUID) throws -> MCPServer {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DecodeError.empty }
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data)
        else {
            throw DecodeError.invalidJSON
        }

        // 1) { "mcpServers": { "name": { ... } } }
        if let dict = obj as? [String: Any] {
            if let servers = dict["mcpServers"] as? [String: Any],
               let (name, raw) = servers.first,
               let entry = raw as? [String: Any]
            {
                return parseEntry(name: name, entry: entry, id: fallbackID)
            }

            // 2) { "name": { command/args 或 url } }  — 单 key 且 value 是对象
            if serversLike(dict), let (name, raw) = dict.first, let entry = raw as? [String: Any] {
                return parseEntry(name: name, entry: entry, id: fallbackID)
            }

            // 3) 直接是单台服务器对象 { command, args } / { url }
            if dict["command"] != nil || dict["url"] != nil {
                let name = (dict["name"] as? String) ?? "MCP 服务器"
                return parseEntry(name: name, entry: dict, id: fallbackID)
            }
        }

        throw DecodeError.unsupported
    }

    /// serversLike
    ///
    /// 执行 `serversLike` 相关逻辑。
    private static func serversLike(_ dict: [String: Any]) -> Bool {
        guard dict.count == 1, let value = dict.values.first as? [String: Any] else { return false }
        return value["command"] != nil || value["url"] != nil || value["args"] != nil
    }

    /// parseEntry
    ///
    /// 执行 `parseEntry` 相关逻辑。
    private static func parseEntry(name: String, entry: [String: Any], id: UUID) -> MCPServer {
        let command = entry["command"] as? String ?? ""
        let url = entry["url"] as? String ?? ""
        /// args。
        let args: [String] = {
            if let arr = entry["args"] as? [String] { return arr }
            if let arr = entry["arguments"] as? [String] { return arr }
            if let s = entry["args"] as? String {
                return s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            }
            return []
        }()

        /// MCP 传输类型。
        let transport: MCPTransport = {
            if let t = entry["transport"] as? String {
                return MCPTransport(rawValue: t.lowercased()) ?? (url.isEmpty ? .stdio : .http)
            }
            if !url.isEmpty { return .sse }
            return .stdio
        }()

        /// 环境变量文本（KEY=VALUE 每行）。
        let envText: String = {
            if let env = entry["env"] as? [String: String] {
                return env.keys.sorted().map { "\($0)=\(env[$0] ?? "")" }.joined(separator: "\n")
            }
            if let env = entry["env"] as? [String: Any] {
                return env.keys.sorted().compactMap { key -> String? in
                    guard let val = env[key] else { return nil }
                    return "\(key)=\(val)"
                }.joined(separator: "\n")
            }
            return entry["envText"] as? String ?? ""
        }()

        let disabled = entry["disabled"] as? Bool ?? false
        let notes = entry["notes"] as? String ?? ""

        return MCPServer(
            id: id,
            name: name,
            transport: transport,
            command: command,
            arguments: args,
            url: url,
            envText: envText,
            notes: notes,
            isEnabled: !disabled
        )
    }

    /// envDictionary
    ///
    /// 执行 `envDictionary` 相关逻辑。
    private static func envDictionary(from text: String) -> [String: String]? {
        var dict: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, let eq = s.firstIndex(of: "=") else { continue }
            let key = String(s[..<eq]).trimmingCharacters(in: .whitespaces)
            let val = String(s[s.index(after: eq)...])
            if !key.isEmpty { dict[key] = val }
        }
        return dict
    }
}
