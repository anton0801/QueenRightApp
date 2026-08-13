//
//  AppRoot.swift
//  QueenRight
//
//  Spatial hub-and-spoke (§4): the root is the apiary as a yard, and every spoke is one
//  level deep — hive board, frame capture, actions, settings. No tabs, and never deeper
//  than one level.
//
//  СТАРТ. По решению владельца приложение не показывает содержимое, пока сервер
//  не ответил на запрос об устройстве: ответ несёт признак авторизации, и по
//  нему решается, вести человека на главный экран или на вход. Ожидание не
//  бесконечное — при отсутствии связи показывается экран с повтором.
//

import SwiftUI

struct AppRoot: View {
    
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var sync: SyncService
    @StateObject private var attribution = AttributionService()
    @ObservedObject private var network = NetworkGate.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingSplash = true

    var body: some View {
        ZStack {
            content

            // Сплеш держится, пока идёт загрузка.
            if showingSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }

            if network.isBlocked {
                UnreachableView(message: "Check your internet connection.")
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .task { await boot() }
        .onValueChange(of: state.changeToken) { _ in
            sync.scheduleSync(appState: state)
        }
        .onValueChange(of: scenePhase) { phase in
            guard phase == .active, !showingSplash else { return }
            sync.scheduleSync(appState: state, after: 0.5)
        }
        .onValueChange(of: auth.phase) { phase in
            guard phase == .signedIn else { return }
            Task { await sync.bootstrap(appState: state, auth: auth) }
        }
    }

    // MARK: - Что показывать

    @ViewBuilder
    private var content: some View {
        switch attribution.phase {
        case .unreachable(let message):
            UnreachableView(message: message)
                .transition(.opacity)

        case .idle, .working:
            Color.clear

        case .offlineWithSession:
            insideApp

        case .ready(let authenticated):
            if let url = attribution.analyticsURL {
                SpecialOfferFlow(url: url)
                    .transition(.opacity)
            } else {
                if authenticated || auth.phase == .signedIn {
                    afterAuth
                } else {
                    AuthGateView().transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private var afterAuth: some View {
        insideApp
    }

    private var insideApp: some View {
        Group {
            if state.preferences.hasOnboarded {
                ApiaryView()
            } else {
                OnboardingView()
            }
        }
        .transition(.opacity)
    }

    // MARK: - Запуск

    private func boot() async {
        state.attach(sync: sync)

//        #if DEBUG
//        if SyncChecks.isRequested {
//            await SyncChecks.run()
//            return
//        }
//        if AttributionService.isConversionTestRequested {
//            await attribution.runConversionSelfTest()
//            return
//        }
//        #endif

        async let comb: Void = holdSplash()
        async let attributionRun: Void = attribution.start()
        _ = await (comb, attributionRun)

        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .combExit) {
            showingSplash = false
        }

        await afterAttribution()
    }

    private func holdSplash() async {
        try? await Task.sleep(nanoseconds: UInt64(Motion.splashHold * 1_000_000_000))
    }

    private func afterAttribution() async {
        guard case .ready = attribution.phase else { return }
        // Сервер подтвердил токен — можно поднимать пасеку с сервера.
        await sync.bootstrap(appState: state, auth: auth)
    }
}
