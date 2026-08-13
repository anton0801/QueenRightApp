//
//  QueenRightApp.swift
//  QueenRight
//
//  Entry point. Firebase is brought up defensively so a build with no bundled
//  configuration still launches straight into a fully working local app (§14).
//  Debug builds run the engine self-tests, which assert the acceptance criteria in §11
//  and the anti-generic invariants in §10 on every launch.
//

import SwiftUI

@main
struct QueenRightApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var auth = AuthService()
    @StateObject private var sync = SyncService()

    init() {
        FirebaseService.configureIfPossible()
        #if DEBUG
        EngineChecks.run()
        #endif
    }

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
