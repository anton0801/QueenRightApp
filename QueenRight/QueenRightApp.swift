import SwiftUI

@main
struct QueenRightApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var auth = AuthService()
    @StateObject private var sync = SyncService()

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environmentObject(state)
                .environmentObject(state.weatherService)
                .environmentObject(auth)
                .environmentObject(sync)
                .preferredColorScheme(state.preferences.appearance.colorScheme)
                .tint(Palette.accent)
        }
    }
}

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
