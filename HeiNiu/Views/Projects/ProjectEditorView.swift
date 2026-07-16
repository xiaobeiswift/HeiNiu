/// 项目新建 / 编辑表单。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import SwiftUI

/// 项目编辑 sheet。
struct ProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss

    /// 编辑中的项目草稿。
    @State private var draft: ProjectItem
    /// 保存回调。
    var onSave: (ProjectItem) -> Void

    /// 预估集数文本（空 = nil）。
    @State private var episodeCountText: String
    /// 单集秒数文本（空 = nil）。
    @State private var durationText: String

    init(project: ProjectItem, onSave: @escaping (ProjectItem) -> Void) {
        _draft = State(initialValue: project)
        self.onSave = onSave
        _episodeCountText = State(
            initialValue: project.targetEpisodeCount.map(String.init) ?? ""
        )
        _durationText = State(
            initialValue: project.episodeDurationSeconds.map(String.init) ?? ""
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("编辑项目")
                    .font(.headline)
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.textSecondary)
                Button("保存") { save() }
                    .buttonStyle(.plain)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StudioCard(title: "基本信息") {
                        VStack(alignment: .leading, spacing: 12) {
                            labeledField("名称") {
                                TextField("例如：青蛇与小和尚", text: $draft.name)
                                    .textFieldStyle(.roundedBorder)
                            }
                            labeledField("一句话卖点") {
                                TextField("logline / 钩子", text: $draft.logline)
                                    .textFieldStyle(.roundedBorder)
                            }
                            labeledField("题材") {
                                TextField("都市反转 / 古装甜宠…", text: $draft.genre)
                                    .textFieldStyle(.roundedBorder)
                            }
                            labeledField("受众") {
                                TextField("女频 18–28 / 下沉市场…", text: $draft.audience)
                                    .textFieldStyle(.roundedBorder)
                            }
                            labeledField("状态") {
                                Picker("状态", selection: $draft.status) {
                                    ForEach(ProjectStatus.allCases) { s in
                                        Text(s.title).tag(s)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }
                    }

                    StudioCard(title: "故事概要") {
                        TextEditor(text: $draft.synopsis)
                            .font(.body)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    StudioCard(title: "创作参数", subtitle: "可选预估，不是真实集数。不确定就留空。") {
                        VStack(alignment: .leading, spacing: 12) {
                            labeledField("预估集数") {
                                TextField("例如 12", text: $episodeCountText)
                                    .textFieldStyle(.roundedBorder)
                            }
                            labeledField("单集秒数") {
                                TextField("例如 90", text: $durationText)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    StudioCard(title: "备注") {
                        TextEditor(text: $draft.notes)
                            .font(.body)
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(20)
            }
        }
        .background(AppTheme.bgBase)
    }

    private func labeledField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            content()
        }
    }

    private func save() {
        var cleaned = draft
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.name.isEmpty { cleaned.name = "未命名项目" }
        cleaned.logline = cleaned.logline.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.synopsis = cleaned.synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.genre = cleaned.genre.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.audience = cleaned.audience.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.notes = cleaned.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let count = Int(episodeCountText.trimmingCharacters(in: .whitespacesAndNewlines))
        cleaned.targetEpisodeCount = (count ?? 0) > 0 ? count : nil

        let duration = Int(durationText.trimmingCharacters(in: .whitespacesAndNewlines))
        cleaned.episodeDurationSeconds = (duration ?? 0) > 0 ? duration : nil

        onSave(cleaned)
        dismiss()
    }
}
