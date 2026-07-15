import SwiftUI

@main
struct HeiNiuApp: App {
    @State private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(settings)
                .frame(minWidth: 1040, minHeight: 680)
                .background(AppTheme.bgBase)
        }
        .defaultSize(width: 1280, height: 820)
    }
}
