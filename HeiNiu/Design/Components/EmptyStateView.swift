import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "tray"
    var badge: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 88, height: 88)
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(spacing: 8) {
                if let badge {
                    StatusBadge(text: badge, style: .accent)
                }
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(AppTheme.accent, in: Capsule())
                        .foregroundStyle(.black.opacity(0.85))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
