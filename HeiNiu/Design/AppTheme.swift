import SwiftUI

enum AppTheme {
    // MARK: - Colors

    static let accent = Color(red: 0.93, green: 0.62, blue: 0.28) // warm amber
    static let accentSoft = accent.opacity(0.16)
    static let success = Color(red: 0.35, green: 0.78, blue: 0.52)
    static let danger = Color(red: 0.95, green: 0.38, blue: 0.38)

    static let bgBase = Color(nsColor: .windowBackgroundColor)
    static let bgSidebar = Color(nsColor: .controlBackgroundColor)
    static let bgCard = Color(nsColor: .controlBackgroundColor)
    static let bgElevated = Color.primary.opacity(0.06)
    static let stroke = Color.primary.opacity(0.08)
    static let strokeStrong = Color.primary.opacity(0.14)

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary.opacity(0.7)

    // MARK: - Metrics

    static let contentMaxWidth: CGFloat = 760
    static let cardRadius: CGFloat = 14
    static let chipRadius: CGFloat = 8
    static let cardPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 14
    static let sidebarWidth: CGFloat = 210

    // MARK: - Shadows

    static func cardShadow() -> some View {
        Color.clear
    }
}

// MARK: - Auto-save helper

@MainActor
final class DebouncedAction {
    private var task: Task<Void, Never>?
    private let delayMs: UInt64

    init(delayMs: UInt64 = 400) {
        self.delayMs = delayMs
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func flush(_ action: @MainActor () -> Void) {
        task?.cancel()
        task = nil
        action()
    }
}

// MARK: - View helpers

extension View {
    func studioContentWidth() -> some View {
        frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
    }

    func studioField() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            )
    }
}
