import SwiftUI

struct StudioCard<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            content()
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: AnyView?

    init(_ title: String, trailing: AnyView? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            if let trailing {
                trailing
            }
        }
    }
}
