import SwiftUI

struct KeyField: View {
    let title: String
    @Binding var text: String
    var footnote: String = "密钥仅保存在本机钥匙串"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)

            SecureField("sk-…", text: $text)
                .textFieldStyle(.plain)
                .font(.body.monospaced())
                .studioField()

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                Text(footnote)
                    .font(.caption)
            }
            .foregroundStyle(AppTheme.textTertiary)
        }
    }
}

struct StudioTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var monospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(monospaced ? .body.monospaced() : .body)
                .studioField()
        }
    }
}
