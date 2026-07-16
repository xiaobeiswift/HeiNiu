/// 黑妞对话：消息、附件、触发面板、上下文占用。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// HeiNiuChatView
///
/// `HeiNiuChatView` 类型定义。
struct HeiNiuChatView: View {
    @Environment(HeiNiuAgentStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    /// 按 ID 查找黑妞。
    let agent: HeiNiuAgent
    /// onEdit。
    @Binding var conversationID: UUID?
    var onEdit: () -> Void

    @State private var input = ""
    @State private var isSending = false
    @State private var isTranslating = false
    @State private var errorMessage: String?
    @State private var attachments: [ChatAttachment] = []
    @State private var activeSkillIDs: Set<UUID> = []
    /// 当前激活的对话模式（/goal 等），与技能分开
    @State private var activeModeCommand: String?
    @State private var insertedSnippets: [(id: UUID, title: String, text: String)] = []
    @State private var showContextDetail = false
    @State private var selectedPaletteIndex: Int = 0
    /// 全界面拖放高亮
    /// 输入框触发的面板类型
    @State private var isDropTargeted = false
    /// 流式自动滚底节流，避免每个 token 都带动画重排
    @State private var lastAutoScrollAt: Date = .distantPast
    @FocusState private var inputFocused: Bool
    private enum PaletteKind: Equatable {
        /// 命令名（不含前缀）。
        case command   // /
        /// mention。
        case mention   // @
        /// 按命令名查找可用技能。
        case skill     // $ 或 ¥
        /// session。
        case session   // #
    }

    /// ActiveToken
    ///
    /// `ActiveToken` 类型定义。
    private struct ActiveToken {
        var kind: PaletteKind
        var query: String
        var startIndex: String.Index
    }

    /// PaletteRow
    ///
    /// `PaletteRow` 类型定义。
    private enum PaletteRow: Identifiable {
        /// 模式。
        case mode(ChatMode)
        /// 按命令名查找可用技能。
        case skill(HeiNiuSkill)
        /// mentionAttachment。
        case mentionAttachment(ChatAttachment)
        /// mentionKnowledge。
        case mentionKnowledge(KnowledgeItem)
        /// session。
        case session(HeiNiuConversation)

        var id: String {
            switch self {
            case .mode(let m): "mode-\(m.command)"
            case .skill(let s): "skill-\(s.id.uuidString)"
            case .mentionAttachment(let a): "att-\(a.id.uuidString)"
            case .mentionKnowledge(let k): "kb-\(k.id.uuidString)"
            case .session(let c): "sess-\(c.id.uuidString)"
            }
        }

        var primary: String {
            switch self {
            case .mode(let m): m.slash
            case .skill(let s): "$\(s.command)"
            case .mentionAttachment(let a): "@\(a.name)"
            case .mentionKnowledge(let k): "@\(k.name)"
            case .session(let c): "#\(c.title)"
            }
        }

        var secondary: String {
            switch self {
            case .mode(let m): m.summary
            case .skill(let s): s.summary
            case .mentionAttachment(let a): "本轮附件 · \(a.charCount) 字符"
            case .mentionKnowledge(let k): "知识库 · \(k.charCount) 字符"
            case .session(let c): "\(c.messages.count) 条消息"
            }
        }
    }

    /// conversation。
    private var conversation: HeiNiuConversation? {
        store.conversation(id: conversationID)
    }

    /// history。
    private var history: [HeiNiuConversation] {
        store.conversations(for: agent.id)
    }

    /// 估算当前对话的上下文占用。
    private var contextUsage: ContextUsage {
        store.contextUsage(
            for: agent,
            conversation: conversation,
            draft: input,
            attachments: attachments,
            insertedSessionTexts: insertedSnippets.map(\.text),
            activeSkillIDs: Array(activeSkillIDs)
        )
    }

    /// 解析输入末尾未完成的触发 token：/ @ $ ¥ #
    private var activeToken: ActiveToken? {
        guard let last = input.last else { return nil }
        // 若最后是空白，无活跃 token
        if last.isWhitespace || last == "\n" { return nil }

        /// triggers。
        let triggers: Set<Character> = ["/", "@", "$", "¥", "#"]
        guard let at = input.lastIndex(where: { triggers.contains($0) }) else { return nil }
        let after = input[input.index(after: at)..<input.endIndex]
        // token 内不能有空白
        if after.contains(where: { $0.isWhitespace || $0 == "\n" }) { return nil }

        let ch = input[at]
        /// 类型枚举。
        let kind: PaletteKind? = {
            switch ch {
            case "/": return .command
            case "@": return .mention
            case "$", "¥": return .skill
            case "#": return .session
            default: return nil
            }
        }()
        guard let kind else { return nil }
        return ActiveToken(kind: kind, query: String(after).lowercased(), startIndex: at)
    }

    /// availableSkills。
    private var availableSkills: [HeiNiuSkill] {
        /// base。
        let base: [HeiNiuSkill]
        if agent.enabledSkillIDs.isEmpty {
            base = store.sortedSkills
        } else {
            let allowed = Set(agent.enabledSkillIDs)
            base = store.sortedSkills.filter { allowed.contains($0.id) }
        }
        // 过滤：所属插件被禁用的技能不可用
        return base.filter { skill in
            guard let pid = skill.pluginID else { return true }
            return store.plugin(id: pid)?.isEnabled != false
        }
    }

    /// paletteRows。
    private var paletteRows: [PaletteRow] {
        guard let token = activeToken else { return [] }
        let q = token.query
        switch token.kind {
        case .command:
            return BuiltInChatModes.all
                .filter {
                    q.isEmpty
                        || $0.command.hasPrefix(q)
                        || $0.name.lowercased().contains(q)
                        || $0.summary.lowercased().contains(q)
                }
                .map { .mode($0) }
        case .skill:
            return availableSkills
                .filter {
                    q.isEmpty
                        || $0.command.lowercased().hasPrefix(q)
                        || $0.name.lowercased().contains(q)
                        || $0.summary.lowercased().contains(q)
                }
                .map { .skill($0) }
        case .mention:
            var rows: [PaletteRow] = attachments
                .filter { q.isEmpty || $0.name.lowercased().contains(q) }
                .map { .mentionAttachment($0) }
            rows += store.knowledge(for: agent.id)
                .filter { $0.enabled }
                .filter { q.isEmpty || $0.name.lowercased().contains(q) }
                .map { .mentionKnowledge($0) }
            return rows
        case .session:
            return store.insertableConversations(excluding: conversationID)
                .filter {
                    let agentName = store.agent(id: $0.agentID)?.name ?? ""
                    return q.isEmpty
                        || $0.title.lowercased().contains(q)
                        || agentName.lowercased().contains(q)
                }
                .map { .session($0) }
        }
    }

    /// isPaletteVisible。
    private var isPaletteVisible: Bool {
        activeToken != nil
    }

    /// paletteTitle。
    private var paletteTitle: String {
        switch activeToken?.kind {
        case .command: return "命令"
        case .skill: return "技能"
        case .mention: return "提及"
        case .session: return "插入会话"
        case .none: return ""
        }
    }

    /// SwiftUI 视图内容。
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)

                HStack(spacing: 0) {
                    chatColumn
                    if !history.isEmpty {
                        Divider().opacity(0.4)
                        historyRail
                            .frame(width: 200)
                    }
                }
            }

            // 全界面拖放遮罩
            if isDropTargeted {
                dropOverlay
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { restoreConversationIfNeeded() }
        .onChange(of: agent.id) { _, _ in
            restoreConversationIfNeeded(force: true)
            resetComposer()
        }
        .onChange(of: paletteRows.map(\.id)) { _, _ in
            selectedPaletteIndex = 0
        }
        .onChange(of: activeToken?.kind) { _, _ in
            selectedPaletteIndex = 0
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    /// dropOverlay。
    private var dropOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.92)

            Color.black.opacity(0.28)

            VStack(spacing: 14) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 28, weight: .semibold))
                Text("松开以添加附件")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    /// header。
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(agent.accentColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: agent.iconSymbol)
                    .font(.title3)
                    .foregroundStyle(agent.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.headline)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            let kbCount = store.knowledge(for: agent.id).count
            if kbCount > 0 {
                StatusBadge(text: "知识库 \(kbCount)", style: .neutral, systemImage: "books.vertical")
            }

            Button("编辑") { onEdit() }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)

            Button {
                let c = store.startConversation(agentID: agent.id)
                conversationID = c.id
                resetComposer()
            } label: {
                Label("新对话", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppTheme.bgElevated, in: Capsule())
                    .overlay(Capsule().stroke(AppTheme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// statusLine。
    private var statusLine: String {
        let provider = settings.provider(id: agent.providerID)?.name ?? "未绑定服务商"
        let model = agent.model.isEmpty ? "未选模型" : agent.model
        let effort = agent.reasoningEffort == .none ? nil : agent.reasoningEffort.displayName
        if let effort {
            return "\(provider) · \(model) · 思考\(effort)"
        }
        return "\(provider) · \(model)"
    }

    /// 输入区是否可点「译英」。
    private var canTranslate: Bool {
        !isSending
            && !isTranslating
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Chat

    /// chatColumn。
    private var chatColumn: some View {
        VStack(spacing: 0) {
            // 消息列表独立：输入/上下文估算变化时不重绘整段剧本
            ChatTranscriptView(
                messages: conversation?.messages ?? [],
                isSending: isSending,
                agent: agent,
                conversationID: conversationID,
                emptySubtitle: agent.subtitle,
                starters: agent.conversationStarters,
                onPickStarter: { starter in
                    input = starter
                    Task { await send() }
                },
                lastAutoScrollAt: $lastAutoScrollAt
            )
            .equatable()

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }

            composer
        }
    }

    // MARK: - Composer

    /// composer。
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isPaletteVisible {
                triggerPalette
            }

            if !attachments.isEmpty || !insertedSnippets.isEmpty || !activeSkillIDs.isEmpty || activeModeCommand != nil {
                chipsRow
            }

            VStack(alignment: .leading, spacing: 8) {
                if !attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(attachments) { att in
                                attachmentChip(att)
                            }
                        }
                    }
                }

                TextField("消息…  /命令  @提及  $技能  #会话", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($inputFocused)
                    .onSubmit { handleSubmit() }
                    .onChange(of: input) { _, newValue in
                        // 拖文件进输入框常会变成完整路径：转成附件 chip
                        convertDroppedPathsInInput(newValue)
                    }

                HStack(spacing: 8) {
                    Button {
                        pickFiles()
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(AppTheme.textSecondary)
                            .background(AppTheme.bgCard.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(AppTheme.stroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("添加附件")

                    Text("/ 命令 · @ 提及 · $ 技能 · # 会话")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 6)

                    // 译英：把输入框原文翻成英文，写回输入框（不进会话）
                    Button {
                        Task { await translateInputToEnglish() }
                    } label: {
                        HStack(spacing: 4) {
                            if isTranslating {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "globe")
                                    .font(.caption)
                            }
                            Text(isTranslating ? "翻译中" : "译英")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(canTranslate || isTranslating ? AppTheme.textSecondary : AppTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppTheme.bgCard.opacity(0.55), in: Capsule())
                        .overlay(Capsule().stroke(AppTheme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canTranslate)
                    .help(
                        settings.hasTranslationModelConfigured
                            ? "将输入框译成英文（全局翻译模型）"
                            : "将输入框译成英文（未配置全局翻译模型，使用当前黑妞模型）"
                    )

                    Button {
                        showContextDetail.toggle()
                    } label: {
                        ContextUsageBar(usage: contextUsage, compact: true)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("上下文容量 \(contextUsage.percentText)")
                    .popover(isPresented: $showContextDetail, arrowEdge: .bottom) {
                        ContextUsageBar(usage: contextUsage, compact: false)
                            .padding(4)
                            .presentationCompactAdaptation(.popover)
                    }

                    // 思考等级：发送键旁边
                    Menu {
                        ForEach(ReasoningEffort.allCases) { level in
                            Button {
                                setReasoningEffort(level)
                            } label: {
                                if agent.reasoningEffort == level {
                                    Label(level.displayName, systemImage: "checkmark")
                                } else {
                                    Text(level.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                                .font(.caption)
                            Text(agent.reasoningEffort == .none ? "思考" : "思考·\(agent.reasoningEffort.displayName)")
                                .font(.caption.weight(.medium))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppTheme.bgCard.opacity(0.55), in: Capsule())
                        .overlay(Capsule().stroke(AppTheme.stroke, lineWidth: 1))
                    }
                    .menuStyle(.borderlessButton)
                    .help("思考等级")

                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(canSend ? agent.accentColor : AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.bgCard.opacity(0.95))
    }

    /// attachmentChip
    ///
    /// 执行 `attachmentChip` 相关逻辑。
    private func attachmentChip(_ att: ChatAttachment) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(att.isImage ? Color.blue.opacity(0.2) : AppTheme.bgCard)
                    .frame(width: 28, height: 28)
                Image(systemName: att.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(att.isImage ? .blue : AppTheme.textSecondary)
            }
            Text(att.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
            Button {
                attachments.removeAll { $0.id == att.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }


    /// 统一触发面板：/ @ $ # 
    private var triggerPalette: some View {
        let rows = paletteRows
        return VStack(alignment: .leading, spacing: 0) {
            Text(paletteTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            if rows.isEmpty {
                Text(emptyPaletteHint)
                    .font(.callout)
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(rows.prefix(10).enumerated()), id: \.element.id) { index, row in
                    let selected = index == selectedPaletteIndex
                    Button {
                        applyPaletteRow(row)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(row.primary)
                                .font(.body.monospaced().weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(1)
                                .frame(minWidth: 96, alignment: .leading)
                            Text(row.secondary)
                                .font(.callout)
                                .foregroundStyle(selected ? AppTheme.textSecondary : AppTheme.textTertiary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? Color.primary.opacity(0.10) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .onHover { if $0 { selectedPaletteIndex = index } }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle").font(.caption)
                Text(paletteFooterHint)
                    .font(.caption)
            }
            .foregroundStyle(AppTheme.textTertiary)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.strokeStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }

    /// emptyPaletteHint。
    private var emptyPaletteHint: String {
        switch activeToken?.kind {
        case .command: return "没有匹配的命令"
        case .skill: return "没有匹配的技能（可在配置 → 技能 添加）"
        case .mention: return "没有可提及的附件或知识库条目"
        case .session: return "没有可插入的会话"
        case .none: return "无匹配项"
        }
    }

    /// paletteFooterHint。
    private var paletteFooterHint: String {
        switch activeToken?.kind {
        case .command: return "/ 唤起命令 · 回车选中"
        case .skill: return "$ 或 ¥ 唤起技能 · 回车选中"
        case .mention: return "@ 提及附件 / 知识库 · 回车选中"
        case .session: return "# 插入其它会话 · 回车选中"
        case .none: return "回车选中"
        }
    }

    /// currentModeLabel。
    private var currentModeLabel: String? {
        if let cmd = activeModeCommand,
           let mode = BuiltInChatModes.mode(command: cmd)
        {
            return mode.name
        }
        if let id = activeSkillIDs.first,
           let skill = store.skills.first(where: { $0.id == id })
        {
            return skill.name
        }
        return nil
    }

    /// composerToolButton
    ///
    /// 执行 `composerToolButton` 相关逻辑。
    private func composerToolButton(
        _ systemImage: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(isActive ? AppTheme.accent : AppTheme.textSecondary)
                .background(
                    (isActive ? AppTheme.accentSoft : AppTheme.bgCard.opacity(0.6)),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isActive ? AppTheme.accent.opacity(0.35) : AppTheme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// chipsRow。
    private var chipsRow: some View {
        FlowLayout(spacing: 6) {
            if let cmd = activeModeCommand,
               let mode = BuiltInChatModes.mode(command: cmd)
            {
                chip(mode.slash, systemImage: "switch.2") {
                    activeModeCommand = nil
                }
            }
            ForEach(Array(activeSkillIDs), id: \.self) { id in
                if let skill = store.skills.first(where: { $0.id == id }) {
                    chip(skill.slash, systemImage: "bolt.fill") {
                        activeSkillIDs.remove(id)
                    }
                }
            }
            ForEach(insertedSnippets, id: \.id) { snip in
                chip(snip.title, systemImage: "bubble.left.and.bubble.right") {
                    insertedSnippets.removeAll { $0.id == snip.id }
                }
            }
        }
    }

    /// chip
    ///
    /// 执行 `chip` 相关逻辑。
    private func chip(_ title: String, systemImage: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(title)
                .font(.caption)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundStyle(AppTheme.accent)
        .background(AppTheme.accentSoft, in: Capsule())
    }


    /// replaceActiveToken
    ///
    /// 执行 `replaceActiveToken` 相关逻辑。
    private func replaceActiveToken(with replacement: String) {
        guard let token = activeToken else {
            input = replacement
            return
        }
        var s = input
        s.replaceSubrange(token.startIndex..<s.endIndex, with: replacement)
        input = s
    }

    /// applyPaletteRow
    ///
    /// 执行 `applyPaletteRow` 相关逻辑。
    private func applyPaletteRow(_ row: PaletteRow) {
        switch row {
        case .mode(let mode):
            activeModeCommand = mode.command
            activeSkillIDs = []
            replaceActiveToken(with: mode.slash + " ")
        case .skill(let skill):
            activeModeCommand = nil
            activeSkillIDs = [skill.id]
            replaceActiveToken(with: "$" + skill.command + " ")
        case .mentionAttachment(let att):
            // 提及附件：写入 @文件名，并确保已在 attachments
            replaceActiveToken(with: "@" + att.name + " ")
        case .mentionKnowledge(let item):
            // 提及知识库：把正文作为插入片段
            let title = item.name
            let text = "【提及知识库：\(item.name)】\n\(item.extractedText)"
            if !insertedSnippets.contains(where: { $0.id == item.id }) {
                insertedSnippets.append((id: item.id, title: title, text: text))
            }
            replaceActiveToken(with: "")
        case .session(let conv):
            let text = store.formatConversationForInsert(conv)
            if !insertedSnippets.contains(where: { $0.id == conv.id }) {
                insertedSnippets.append((id: conv.id, title: conv.title, text: text))
            }
            replaceActiveToken(with: "")
        }
        selectedPaletteIndex = 0
        inputFocused = true
    }

    /// handleSubmit
    ///
    /// 执行 `handleSubmit` 相关逻辑。
    private func handleSubmit() {
        if isPaletteVisible {
            let rows = Array(paletteRows.prefix(10))
            if rows.indices.contains(selectedPaletteIndex) {
                applyPaletteRow(rows[selectedPaletteIndex])
                return
            }
            if let first = rows.first {
                applyPaletteRow(first)
                return
            }
            return
        }
        Task { await send() }
    }

    // MARK: - History

    /// historyRail。
    private var historyRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("历史")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(history) { item in
                        Button {
                            conversationID = item.id
                            /* palette closed via token */
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.caption.weight(conversationID == item.id ? .semibold : .regular))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(2)
                                Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(conversationID == item.id ? AppTheme.accentSoft : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("删除", role: .destructive) {
                                store.deleteConversation(id: item.id)
                                if conversationID == item.id {
                                    restoreConversationIfNeeded(force: true)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .background(AppTheme.bgSidebar.opacity(0.6))
    }

    // MARK: - Actions

    /// canSend。
    private var canSend: Bool {
        !isSending && (
            !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !attachments.isEmpty
                || !insertedSnippets.isEmpty
        )
    }

    /// 恢复当前黑妞的最近会话；不自动新建空对话。
    ///
    /// - Parameter force: 为 true 时忽略现有 `conversationID`，重新选最近一条（切角色/删会话后用）。
    private func restoreConversationIfNeeded(force: Bool = false) {
        if !force,
           let conversationID,
           let existing = store.conversation(id: conversationID),
           existing.agentID == agent.id {
            return
        }

        let list = store.conversations(for: agent.id)
        // 优先恢复有内容的最近会话，避免反复落到空的「新对话」
        if let preferred = list.first(where: { !$0.messages.isEmpty }) ?? list.first {
            conversationID = preferred.id
        } else {
            conversationID = nil
        }
    }

    /// 发送前保证有会话：先恢复，没有历史再新建。
    private func ensureConversation() {
        restoreConversationIfNeeded()
        if conversationID == nil {
            let c = store.startConversation(agentID: agent.id)
            conversationID = c.id
        }
    }

    /// resetComposer
    ///
    /// 执行 `resetComposer` 相关逻辑。
    private func resetComposer() {
        input = ""
        errorMessage = nil
        attachments = []
        activeSkillIDs = []
        activeModeCommand = nil
        insertedSnippets = []
    }

    /// 更新当前黑妞的思考等级并持久化。
    private func setReasoningEffort(_ level: ReasoningEffort) {
        var updated = agent
        updated.reasoningEffort = level
        store.updateAgent(updated)
    }

    /// 将输入框内容翻译为英文并写回（不发送、不入会话）。
    private func translateInputToEnglish() async {
        let source = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !isTranslating, !isSending else { return }

        isTranslating = true
        errorMessage = nil
        defer { isTranslating = false }

        do {
            let translated = try await store.translateToEnglish(
                source,
                agent: agent,
                settings: settings
            )
            input = translated
            inputFocused = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// pickFiles
    ///
    /// 执行 `pickFiles` 相关逻辑。
    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .plainText, .utf8PlainText, .utf16PlainText,
            .sourceCode, .json, .xml, .html, .commaSeparatedText,
            .pdf, .image, .data,
        ]
        panel.message = "选择要附加到本轮对话的文件"
        guard panel.runModal() == .OK else { return }
        addAttachmentURLs(panel.urls)
    }

    /// handleDrop
    ///
    /// 执行 `handleDrop` 相关逻辑。
    @discardableResult
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    /// 远程端点 URL。
                    let url: URL? = {
                        if let data = item as? Data {
                            return URL(dataRepresentation: data, relativeTo: nil)
                        }
                        if let url = item as? URL { return url }
                        if let str = item as? String { return URL(fileURLWithPath: str) }
                        return nil
                    }()
                    guard let url else { return }
                    Task { @MainActor in
                        addAttachmentURLs([url])
                    }
                }
            }
        }
        return handled
    }

    /// addAttachmentURLs
    ///
    /// 执行 `addAttachmentURLs` 相关逻辑。
    private func addAttachmentURLs(_ urls: [URL]) {
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let fileName = url.lastPathComponent
            // 已存在同名附件则跳过
            if attachments.contains(where: { $0.name == fileName }) { continue }

            let extract = TextExtractor.extract(from: url)
            /// imageExts。
            let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
            let isImage = imageExts.contains(url.pathExtension.lowercased())
            attachments.append(
                ChatAttachment(
                    name: fileName,
                    extractedText: extract.text,
                    byteSize: extract.byteSize,
                    isImage: isImage
                )
            )
            // 若输入框里粘进了完整路径，清掉
            stripPathFromInput(matching: url)
        }
    }

    /// 拖进 TextField 时系统常粘贴绝对路径 → 转成 chip 后移除路径文本
    private func convertDroppedPathsInInput(_ text: String) {
        // 匹配 /Users/... 或 file:// 路径
        let pattern = #"(?:file://)?(/Users/[^\s]+|/(?:private/)?(?:Users|Volumes|tmp)/[^\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return }

        var urls: [URL] = []
        for match in matches {
            let path = ns.substring(with: match.range(at: 1))
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            }
        }
        guard !urls.isEmpty else { return }

        addAttachmentURLs(urls)

        // 从输入中删除这些路径
        var cleaned = text
        for url in urls {
            let path = url.path
            cleaned = cleaned.replacingOccurrences(of: "file://" + path, with: "")
            cleaned = cleaned.replacingOccurrences(of: path, with: "")
        }
        cleaned = cleaned
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned != text {
            input = cleaned
        }
    }

    /// stripPathFromInput
    ///
    /// 执行 `stripPathFromInput` 相关逻辑。
    private func stripPathFromInput(matching url: URL) {
        let path = url.path
        var cleaned = input
        cleaned = cleaned.replacingOccurrences(of: "file://" + path, with: "")
        cleaned = cleaned.replacingOccurrences(of: path, with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned != input {
            input = cleaned
        }
    }

    /// buildPackage
    ///
    /// 执行 `buildPackage` 相关逻辑。
    private func buildPackage() -> HeiNiuAgentStore.SendPackage {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var skillCommands: [String] = []
        var modelBody = raw

        // 解析 /command rest —— 模式优先，其次技能
        if raw.hasPrefix("/") {
            let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let cmd = String(parts[0].dropFirst())
            let rest = parts.count > 1 ? String(parts[1]) : ""
            let resolved = store.resolveSlash(cmd)
            if let mode = resolved.mode {
                activeModeCommand = mode.command
                activeSkillIDs = []
                skillCommands.append(mode.command)
                modelBody = mode.template.replacingOccurrences(
                    of: "{{input}}",
                    with: rest.isEmpty ? "（用户未补充更多说明）" : rest
                )
                raw = rest.isEmpty ? mode.slash : "\(mode.slash) \(rest)"
            } else if let skill = resolved.skill {
                skillCommands.append(cmd)
                activeModeCommand = nil
                activeSkillIDs = [skill.id]
                modelBody = skill.template.replacingOccurrences(
                    of: "{{input}}",
                    with: rest.isEmpty ? "（用户未补充更多说明）" : rest
                )
                raw = rest.isEmpty ? skill.slash : "\(skill.slash) \(rest)"
            }
        } else if let modeCmd = activeModeCommand,
                  let mode = BuiltInChatModes.mode(command: modeCmd)
        {
            skillCommands.append(mode.command)
            modelBody = mode.template.replacingOccurrences(
                of: "{{input}}",
                with: raw.isEmpty ? "（用户未补充更多说明）" : raw
            )
        } else if !activeSkillIDs.isEmpty {
            if let skill = store.skills.first(where: { activeSkillIDs.contains($0.id) }) {
                skillCommands.append(skill.command)
                modelBody = skill.template.replacingOccurrences(
                    of: "{{input}}",
                    with: raw.isEmpty ? "（用户未补充更多说明）" : raw
                )
            }
        }

        var extras: [String] = []
        if !attachments.isEmpty {
            extras.append(contentsOf: attachments.map { "【附件：\($0.name)】\n\($0.extractedText)" })
        }
        if !insertedSnippets.isEmpty {
            extras.append(contentsOf: insertedSnippets.map(\.text))
        }
        if !extras.isEmpty {
            modelBody = ([modelBody] + extras)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n---\n\n")
        }

        return HeiNiuAgentStore.SendPackage(
            displayText: raw.isEmpty ? "（附带 \(attachments.count + insertedSnippets.count) 项上下文）" : raw,
            modelUserText: modelBody,
            skillCommands: skillCommands,
            attachmentNames: attachments.map(\.name),
            insertedSessionTitles: insertedSnippets.map(\.title)
        )
    }

    /// 发送用户消息并请求模型回复
    ///
    /// 发送用户消息并请求模型回复。
    private func send() async {
        ensureConversation()
        guard let conversationID else { return }

        // /compress：先把历史塞进 input，再请求模型，成功后用摘要替换会话
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCompress = isCompressCommand(trimmedInput)

        var package = buildPackage()
        if isCompress {
            package = buildCompressPackage(displayCommand: package.displayText)
        }

        input = ""
        let pendingSkills = activeSkillIDs
        attachments = []
        insertedSnippets = []
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            if isCompress {
                try await store.send(
                    package: package,
                    conversationID: conversationID,
                    settings: settings,
                    activeSkillIDs: Array(pendingSkills)
                )
                // 取刚生成的助手摘要，压缩历史
                if let latest = store.conversation(id: conversationID),
                   let summary = latest.messages.last(where: { $0.role == .assistant })?.content
                {
                    store.replaceConversationWithSummary(
                        conversationID: conversationID,
                        summary: summary,
                        userRequestDisplay: package.displayText
                    )
                }
            } else {
                try await store.send(
                    package: package,
                    conversationID: conversationID,
                    settings: settings,
                    activeSkillIDs: Array(pendingSkills)
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// isCompressCommand
    ///
    /// 执行 `isCompressCommand` 相关逻辑。
    private func isCompressCommand(_ raw: String) -> Bool {
        if raw.hasPrefix("/compress") { return true }
        if activeModeCommand == "compress" { return true }
        return false
    }

    /// buildCompressPackage
    ///
    /// 执行 `buildCompressPackage` 相关逻辑。
    private func buildCompressPackage(displayCommand: String) -> HeiNiuAgentStore.SendPackage {
        /// historyText。
        let historyText: String = {
            guard let conversation else { return "（当前无消息）" }
            return store.formatConversationForInsert(conversation, maxCharacters: 60_000)
        }()
        let mode = BuiltInChatModes.mode(command: "compress")
        let modelText = (mode?.template ?? "请压缩：\n{{input}}")
            .replacingOccurrences(of: "{{input}}", with: historyText)

        return HeiNiuAgentStore.SendPackage(
            displayText: displayCommand.hasPrefix("/compress") ? displayCommand : "/compress",
            modelUserText: modelText,
            skillCommands: ["compress"],
            attachmentNames: attachments.map(\.name),
            insertedSessionTitles: insertedSnippets.map(\.title)
        )
    }
}

// MARK: - Transcript

/// 消息滚动区：与输入框/上下文估算隔离，避免父视图状态导致整表重绘。
private struct ChatTranscriptView: View, Equatable {
    let messages: [ChatTurn]
    let isSending: Bool
    let agent: HeiNiuAgent
    let conversationID: UUID?
    let emptySubtitle: String
    let starters: [String]
    let onPickStarter: (String) -> Void
    @Binding var lastAutoScrollAt: Date

    private var accent: Color { agent.accentColor }

    static func == (lhs: ChatTranscriptView, rhs: ChatTranscriptView) -> Bool {
        // 避免对整段剧本做深比较（会拖慢输入框每一次击键）
        guard lhs.isSending == rhs.isSending,
              lhs.conversationID == rhs.conversationID,
              lhs.agent.id == rhs.agent.id,
              lhs.agent.accentHue == rhs.agent.accentHue,
              lhs.agent.model == rhs.agent.model,
              lhs.agent.providerID == rhs.agent.providerID,
              lhs.emptySubtitle == rhs.emptySubtitle,
              lhs.starters == rhs.starters,
              lhs.messages.count == rhs.messages.count
        else { return false }
        // 只比对 id + 长度 + 末条内容指纹
        if zip(lhs.messages, rhs.messages).contains(where: {
            $0.id != $1.id
                || $0.content.count != $1.content.count
                || ($0.reasoning?.count ?? 0) != ($1.reasoning?.count ?? 0)
        }) {
            return false
        }
        if let l = lhs.messages.last, let r = rhs.messages.last {
            return l.content == r.content && l.reasoning == r.reasoning
        }
        return true
    }

    private var streamingFingerprint: Int {
        guard isSending, let last = messages.last, last.role == .assistant else { return 0 }
        return (last.content.count + (last.reasoning?.count ?? 0)) / 64
    }

    private var hasStreamingAssistantBubble: Bool {
        isSending && messages.last?.role == .assistant
    }

    var body: some View {
        ScrollViewReader { proxy in
            messageScroll(proxy: proxy)
        }
    }

    @ViewBuilder
    private func messageScroll(proxy: ScrollViewProxy) -> some View {
        // 对齐历史实现：ScrollView → LazyVStack → MessageBubble(HStack+Spacer)
        // 不要 GeometryReader / containerRelativeFrame / 固定行宽，那些会把布局搞崩。
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if messages.isEmpty {
                    welcomeBlock
                }
                ForEach(messages) { message in
                    messageRow(message)
                }
                if isSending && !hasStreamingAssistantBubble {
                    typingIndicator
                }
                Color.clear
                    .frame(height: 1)
                    .id("bottom-anchor")
            }
            .padding(20)
        }
        .onChange(of: messages.count) { _, _ in
            scrollToBottom(proxy, animated: true, force: true)
        }
        .onChange(of: isSending) { _, sending in
            scrollToBottom(proxy, animated: !sending, force: true)
        }
        .onChange(of: streamingFingerprint) { _, _ in
            scrollToBottom(proxy, animated: false, force: false)
        }
        .onChange(of: conversationID) { _, _ in
            lastAutoScrollAt = .distantPast
            scrollToBottom(proxy, animated: false, force: true)
        }
        .onAppear {
            scrollToBottom(proxy, animated: false, force: true)
        }
    }

    private func messageRow(_ message: ChatTurn) -> some View {
        let streaming = isSending
            && message.role == .assistant
            && message.id == messages.last?.id
        return MessageBubble(
            message: message,
            agent: agent,
            conversationID: conversationID,
            isStreaming: streaming
        )
        .id(message.id)
    }

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("黑妞思考中…")
                .font(.callout)
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(.leading, 8)
        .id("typing")
    }

    private var welcomeBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(emptySubtitle.isEmpty ? "开始和她聊聊" : emptySubtitle)
                .font(.title3.weight(.semibold))
            Text("附件用回形针；/ 命令 · @ 提及 · $ 技能 · # 插入会话。知识库在「编辑」中配置。")
                .font(.callout)
                .foregroundStyle(AppTheme.textSecondary)

            if !starters.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(starters, id: \.self) { starter in
                        Button {
                            onPickStarter(starter)
                        } label: {
                            Text(starter)
                                .font(.callout)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundStyle(accent)
                                .background(accent.opacity(0.12), in: Capsule())
                                .overlay(Capsule().stroke(accent.opacity(0.28), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSending)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }

    private func scrollToBottom(
        _ proxy: ScrollViewProxy,
        animated: Bool,
        force: Bool
    ) {
        let now = Date()
        if !force, now.timeIntervalSince(lastAutoScrollAt) < 0.32 {
            return
        }
        lastAutoScrollAt = now
        DispatchQueue.main.async {
            let target: AnyHashable = {
                if isSending, hasStreamingAssistantBubble, let last = messages.last {
                    return last.id
                }
                if isSending, !hasStreamingAssistantBubble {
                    return "typing"
                }
                if let last = messages.last {
                    return last.id
                }
                return "bottom-anchor"
            }()
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            }
        }
    }
}

/// MessageBubble
///
/// 圆角对话气泡；长文默认折叠。底栏提供复制 / 自动翻译。
private struct MessageBubble: View, Equatable {
    @Environment(HeiNiuAgentStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    /// message。
    let message: ChatTurn
    /// 当前黑妞（翻译回退模型）。
    let agent: HeiNiuAgent
    /// 所属会话（写回译文）。
    let conversationID: UUID?
    /// 是否处于流式输出中（最后一条助手消息）。
    var isStreaming: Bool = false

    /// 超过该字符数时默认折叠正文（短剧一轮很容易上万字）。
    private static let collapseThreshold = 900
    /// 气泡统一最大宽度：多行正文都在此宽度内换行，避免折叠/展开时「一宽一窄」。
    private static let bubbleMaxWidth: CGFloat = 520

    @State private var reasoningExpanded = false
    @State private var bodyExpanded = false
    @State private var isTranslating = false
    @State private var actionHint: String?

    static func == (lhs: MessageBubble, rhs: MessageBubble) -> Bool {
        lhs.message.id == rhs.message.id
            && lhs.message.role == rhs.message.role
            && lhs.message.content == rhs.message.content
            && lhs.message.reasoning == rhs.message.reasoning
            && lhs.isStreaming == rhs.isStreaming
            && lhs.agent.id == rhs.agent.id
            && lhs.agent.accentHue == rhs.agent.accentHue
            && lhs.conversationID == rhs.conversationID
    }

    private var accent: Color { agent.accentColor }
    private var isUser: Bool { message.role == .user }

    private var shouldOfferCollapse: Bool {
        !isStreaming && message.content.count >= Self.collapseThreshold
    }

    /// 长文 / 多行 / 可折叠：用统一宽度，避免「同一组件一宽一窄」。
    private var usesUniformBubbleWidth: Bool {
        shouldOfferCollapse
            || bodyExpanded
            || isStreaming
            || message.content.count >= 80
            || message.content.contains("\n")
            || isTranslating
            || actionHint != nil
    }

    private var showsFullBody: Bool {
        isStreaming || bodyExpanded || !shouldOfferCollapse
    }

    private var displayBody: String {
        guard !showsFullBody else { return message.content }
        // 尽量在段落边界截断，观感不像硬切
        let prefix = String(message.content.prefix(Self.collapseThreshold))
        if let breakIndex = prefix.lastIndex(where: { $0 == "\n" || $0 == "。" || $0 == "！" || $0 == "？" }) {
            return String(prefix[...breakIndex]) + "…"
        }
        return prefix + "…"
    }

    private var canAct: Bool {
        !isStreaming
            && !isTranslating
            && !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var translateButtonTitle: String {
        if isTranslating { return "翻译中" }
        switch HeiNiuAgentStore.inferredDirection(for: message.content) {
        case .toEnglish: return "译英"
        case .toChinese: return "译中"
        case .auto: return "翻译"
        }
    }

    var body: some View {
        // 与 git 历史一致：HStack + 两侧 Spacer 负责左右贴边
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !isUser, message.hasReasoning {
                    reasoningBlock
                }

                if !message.content.isEmpty {
                    contentBubble
                    // 操作条放在气泡外，避免短消息被 Spacer 撑成宽条
                    if !isStreaming {
                        externalActionBar
                    }
                } else if isStreaming && !isUser {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(message.hasReasoning ? "正在组织回答…" : "黑妞思考中…")
                            .font(.callout)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.bgElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.stroke, lineWidth: 1)
                    )
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .onChange(of: isStreaming) { _, streaming in
            if streaming {
                bodyExpanded = true
            } else if message.content.count >= Self.collapseThreshold {
                bodyExpanded = false
            }
            if !streaming {
                reasoningExpanded = false
            }
        }
        .onChange(of: message.content) { _, _ in
            if !isTranslating { actionHint = nil }
        }
        .onAppear {
            if isStreaming {
                bodyExpanded = true
            }
        }
    }

    private var contentBubble: some View {
        Group {
            if usesUniformBubbleWidth {
                longContentBubble
            } else {
                shortContentBubble
            }
        }
        .contextMenu {
            Button("复制") { copyMessage() }
            Button(translateButtonTitle) {
                Task { await translateMessage() }
            }
            .disabled(!canAct || conversationID == nil)
        }
    }

    /// 「继续」等短气泡：只包文字，贴合内容宽度。
    private var shortContentBubble: some View {
        Text(displayBody)
            .font(.body)
            .foregroundStyle(isUser ? Color.black.opacity(0.85) : AppTheme.textPrimary)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isUser ? accent : AppTheme.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isUser ? Color.clear : AppTheme.stroke, lineWidth: 1)
            )
    }

    /// 长剧本：统一宽度；展开链接放在气泡内左下，复制/翻译在气泡外。
    private var longContentBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayBody)
                .font(.body)
                .foregroundStyle(isUser ? Color.black.opacity(0.85) : AppTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)

            if shouldOfferCollapse {
                Button {
                    bodyExpanded.toggle()
                } label: {
                    Text(bodyExpanded ? "收起" : "展开全文（\(message.content.count) 字）")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isUser ? Color.black.opacity(0.55) : AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: Self.bubbleMaxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isUser ? accent : AppTheme.bgElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isUser ? Color.clear : AppTheme.stroke, lineWidth: 1)
        )
    }

    /// 气泡下方操作：不进气泡，不改变气泡宽度。
    private var externalActionBar: some View {
        HStack(spacing: 8) {
            if let actionHint {
                Text(actionHint)
                    .font(.caption2)
                    .foregroundStyle(
                        actionHint.contains("失败") ? AppTheme.danger : AppTheme.textTertiary
                    )
                    .lineLimit(1)
            }

            bubbleTextButton(
                title: "复制",
                systemImage: "doc.on.doc",
                help: "复制全文",
                disabled: !canAct
            ) {
                copyMessage()
            }

            bubbleTextButton(
                title: translateButtonTitle,
                systemImage: "globe",
                help: "根据原文自动中译英或英译中，写回本条消息",
                disabled: !canAct || conversationID == nil,
                showsProgress: isTranslating
            ) {
                Task { await translateMessage() }
            }
        }
        .padding(.horizontal, 4)
    }

    private func bubbleTextButton(
        title: String,
        systemImage: String,
        help: String,
        disabled: Bool,
        showsProgress: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if showsProgress {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.semibold))
                }
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(disabled ? AppTheme.textTertiary : AppTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.bgCard.opacity(0.7), in: Capsule())
            .overlay(Capsule().stroke(AppTheme.stroke.opacity(0.8), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    private func copyMessage() {
        copyToPasteboard(message.content)
        actionHint = "已复制"
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if actionHint == "已复制" { actionHint = nil }
        }
    }

    private func translateMessage() async {
        guard canAct, let conversationID else { return }
        isTranslating = true
        actionHint = nil
        defer { isTranslating = false }

        do {
            let translated = try await store.translate(
                message.content,
                direction: .auto,
                agent: agent,
                settings: settings
            )
            store.replaceMessageContent(
                conversationID: conversationID,
                messageID: message.id,
                content: translated
            )
            // 译文可能很长，保持展开方便阅读
            if translated.count >= Self.collapseThreshold {
                bodyExpanded = true
            }
            actionHint = "已翻译"
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if actionHint == "已翻译" { actionHint = nil }
        } catch {
            actionHint = "翻译失败"
        }
    }

    private var reasoningBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                reasoningExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                    Text(isStreaming && message.content.isEmpty ? "思考中" : "思考过程")
                        .font(.caption.weight(.semibold))
                    if isStreaming && message.content.isEmpty {
                        ProgressView().controlSize(.mini)
                    }
                    Image(systemName: reasoningExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if reasoningExpanded {
                Text(message.reasoning ?? "")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .contextMenu {
                        Button("复制思考过程") { copyToPasteboard(message.reasoning ?? "") }
                    }
            }
        }
        // 折叠：贴合标题；展开：与长正文同宽
        .frame(
            width: reasoningExpanded ? Self.bubbleMaxWidth : nil,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.bgCard.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.stroke.opacity(0.9), lineWidth: 1)
        )
    }
}

private func copyToPasteboard(_ text: String) {
    guard !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
