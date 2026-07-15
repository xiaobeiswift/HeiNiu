import SwiftUI

struct ModelTagList: View {
    @Binding var models: [String]
    @State private var newModel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if models.isEmpty {
                Text("尚未添加模型")
                    .font(.callout)
                    .foregroundStyle(AppTheme.textTertiary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(models, id: \.self) { model in
                        HStack(spacing: 6) {
                            Text(model)
                                .font(.caption.monospaced())
                            Button {
                                models.removeAll { $0 == model }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppTheme.textTertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.bgElevated, in: Capsule())
                        .overlay(Capsule().stroke(AppTheme.stroke, lineWidth: 1))
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("添加模型 ID，例如 gpt-4o", text: $newModel)
                    .textFieldStyle(.plain)
                    .font(.callout.monospaced())
                    .studioField()
                    .onSubmit { add() }

                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(newModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func add() {
        let name = newModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !models.contains(name) {
            models.append(name)
        }
        newModel = ""
    }
}

/// Simple wrapping layout for tags/chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            width = max(width, x - spacing)
        }

        return (CGSize(width: width, height: y + rowHeight), frames)
    }
}

struct ChipSelector: View {
    let items: [String]
    @Binding var selection: String

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let selected = selection == item
                Button {
                    selection = item
                } label: {
                    Text(item)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(selected ? AppTheme.accent : AppTheme.textSecondary)
                        .background(
                            Capsule().fill(selected ? AppTheme.accentSoft : AppTheme.bgElevated)
                        )
                        .overlay(
                            Capsule().stroke(selected ? AppTheme.accent.opacity(0.35) : AppTheme.stroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
