import SwiftUI

struct PlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String
    var badge: String? = "即将推出"

    var body: some View {
        EmptyStateView(
            title: title,
            message: message,
            systemImage: systemImage,
            badge: badge
        )
        .background(AppTheme.bgBase)
    }
}
