/// 配置导入导出与本机路径说明。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// BackupSettingsView
///
/// `BackupSettingsView` 类型定义。
struct BackupSettingsView: View {
    /// onSaved。
    @Environment(SettingsStore.self) private var settings
    @Environment(KnowledgeStore.self) private var knowledge
    var onSaved: () -> Void = {}

    @State private var importMode: SettingsImportMode = .merge
    @State private var importAPIKeys = true

    @State private var statusMessage: String?
    @State private var statusOK: Bool?
    @State private var pendingBackup: SettingsBackup?
    @State private var showImportConfirm = false
    @State private var isBusy = false

    /// SwiftUI 视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("备份与迁移")
                    .font(.title3.weight(.semibold))
                Text("换机器时导出配置包，在新电脑导入即可恢复")
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            StudioCard(title: "本机存储位置") {
                VStack(alignment: .leading, spacing: 12) {
                    storageRow(
                        title: "配置文件（不含 Key）",
                        value: settings.localSettingsPath,
                        systemImage: "doc.text"
                    )
                    storageRow(
                        title: "API Key",
                        value: "本机钥匙串 · service = \(Bundle.main.bundleIdentifier ?? "cn.codable.heiniu")",
                        systemImage: "key.fill"
                    )
                    Text("日常自动保存在上述位置。导出文件用于跨设备迁移；密钥默认不进配置文件。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

            StudioCard(title: "导出", subtitle: "生成一份 JSON 配置包，可拷贝到 U 盘 / 网盘 / AirDrop") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("配置包不包含 API Key 或知识库内容。密钥需在新设备重新填写；知识资料请在知识库页面单独迁移。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)

                    HStack(spacing: 10) {
                        Button {
                            exportBackup()
                        } label: {
                            Label(isBusy ? "导出中…" : "导出配置…", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(AppTheme.accent, in: Capsule())
                                .foregroundStyle(.black.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)

                        summaryChips
                    }
                }
            }

            StudioCard(title: "导入", subtitle: "从另一台机器的配置包恢复") {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("导入方式")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        Picker("导入方式", selection: $importMode) {
                            ForEach(SettingsImportMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(importMode.detail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    Toggle(isOn: $importAPIKeys) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("若旧版备份含 Key，一并写入钥匙串")
                            Text("新版备份不含 Key；无 Key 的备份不会清空本机已有密钥（合并时）")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)

                    Button {
                        pickImportFile()
                    } label: {
                        Label("选择配置文件…", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppTheme.bgElevated, in: Capsule())
                            .overlay(Capsule().stroke(AppTheme.strokeStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }

            if let statusMessage {
                HStack(spacing: 8) {
                    Image(systemName: statusOK == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(statusMessage)
                        .font(.callout)
                }
                .foregroundStyle(statusOK == true ? AppTheme.success : AppTheme.danger)
            }
        }
        .confirmationDialog(
            importConfirmTitle,
            isPresented: $showImportConfirm,
            titleVisibility: .visible
        ) {
            Button(importMode == .replace ? "替换并导入" : "合并导入", role: importMode == .replace ? .destructive : nil) {
                if let backup = pendingBackup {
                    applyImport(backup)
                }
            }
            Button("取消", role: .cancel) {
                pendingBackup = nil
            }
        } message: {
            Text(importConfirmMessage)
        }
    }

    /// summaryChips。
    private var summaryChips: some View {
        HStack(spacing: 8) {
            StatusBadge(text: "LLM \(settings.providers.count)", style: .neutral)
            StatusBadge(text: "提示词 \(settings.promptItems.count)", style: .neutral)
            StatusBadge(text: "生图 \(settings.imageProviders.count)", style: .neutral)
            StatusBadge(text: "生视频 \(settings.videoProviders.count)", style: .neutral)
        }
    }

    /// storageRow
    ///
    /// 执行 `storageRow` 相关逻辑。
    private func storageRow(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(AppTheme.textPrimary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.stroke, lineWidth: 1)
                )
        }
    }

    /// importConfirmTitle。
    private var importConfirmTitle: String {
        importMode == .replace ? "替换本机全部配置？" : "合并导入配置？"
    }

    /// importConfirmMessage。
    private var importConfirmMessage: String {
        guard let backup = pendingBackup else { return "" }
        /// keysNote。
        let keysNote: String
        if backup.includeAPIKeys {
            keysNote = importAPIKeys ? "备份含 API Key，将写入钥匙串。" : "备份含 API Key，但本次不导入密钥。"
        } else {
            keysNote = "备份不含 API Key，导入后需在本机重新填写。"
        }
        return """
        备份时间：\(backup.exportedAt.formatted(date: .abbreviated, time: .shortened))
        LLM \(backup.providers.count) · 提示词 \(backup.promptItems.count) · 生图 \(backup.imageProviders.count) · 生视频 \(backup.videoProviders.count)
        \(keysNote)
        """
    }

    // MARK: - Actions

    /// exportBackup
    ///
    /// 执行 `exportBackup` 相关逻辑。
    private func exportBackup() {
        isBusy = true
        defer { isBusy = false }

        do {
            let data = try settings.exportBackupData(includeAPIKeys: false)
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = defaultExportFileName()
            panel.allowedContentTypes = [.json]
            panel.message = "将导出不含 API Key 和知识库内容的配置包"

            guard panel.runModal() == .OK, let url = panel.url else {
                statusMessage = "已取消导出"
                statusOK = false
                return
            }

            try data.write(to: url, options: .atomic)
            statusMessage = "已导出到 \(url.lastPathComponent)"
            statusOK = true
            onSaved()
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
            statusOK = false
        }
    }

    /// pickImportFile
    ///
    /// 执行 `pickImportFile` 相关逻辑。
    private func pickImportFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.message = "选择黑妞短剧配置备份文件"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            let data = try Data(contentsOf: url)
            let backup = try settings.decodeBackup(from: data)
            pendingBackup = backup
            showImportConfirm = true
        } catch {
            statusMessage = "无法读取配置：\(error.localizedDescription)"
            statusOK = false
        }
    }

    /// applyImport
    ///
    /// 执行 `applyImport` 相关逻辑。
    private func applyImport(_ backup: SettingsBackup) {
        settings.importBackup(backup, mode: importMode, importAPIKeys: importAPIKeys)
        knowledge.markAllPending()
        pendingBackup = nil
        statusMessage = importMode == .replace ? "已替换本机配置" : "已合并导入配置"
        statusOK = true
        onSaved()
    }

    /// defaultExportFileName
    ///
    /// 执行 `defaultExportFileName` 相关逻辑。
    private func defaultExportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let stamp = formatter.string(from: Date())
        return "黑妞短剧-settings-\(stamp)-no-keys.json"
    }
}
