//
//  SyncChecks.swift
//  QueenRight
//
//  Интеграционная проверка синхронизации. В отличие от EngineChecks, которые
//  считают чистую математику, здесь гоняются НАСТОЯЩИЕ AppState, AuthService,
//  APIClient и SyncService против живого сервера — то есть ровно тот код, что
//  работает у пользователя, со всеми Keychain, ротацией токенов и версиями.
//
//  Запуск (только DEBUG):
//      xcrun simctl launch booted com.rights.QueenRight -SyncSelfTest
//
//  Обычный запуск приложения этот код не трогает.
//

import Foundation

#if DEBUG
enum SyncChecks {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-SyncSelfTest")
    }

    private static var passed = 0
    private static var failed = 0
    private static var failures: [String] = []

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            passed += 1
            print("  ok   \(name)")
        } else {
            failed += 1
            failures.append(name + (detail.isEmpty ? "" : " — \(detail)"))
            print("  FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    @MainActor
    static func run() async {
        print("[SyncChecks] адрес API: \(APIConfig.baseURL.absoluteString)")
        guard AuthService.isConfigured else {
            print("[SyncChecks] пропущено: API не настроен в этой сборке")
            return
        }

        // Чистый лист: тест не должен зависеть от прошлых запусков.
        TokenStore.clear()
        LocalStore.shared.wipeEverything()

        let appState = AppState()
        let auth = AuthService()
        let sync = SyncService()
        appState.attach(sync: sync)
        sync.reset()

        let stamp = UUID().uuidString.prefix(8)
        let email = "device.a.\(stamp)@example.com"
        let password = "integraciya-parol-1"

        // ── Регистрация настоящим AuthService
        auth.signUp(email: email, password: password)
        await settle(until: { auth.phase == .signedIn }, seconds: 10)
        check("устройство A: регистрация через AuthService", auth.phase == .signedIn,
              auth.errorMessage ?? "фаза \(auth.phase)")
        check("токен лёг в Keychain", TokenStore.hasSession)

        guard auth.phase == .signedIn else { report(); return }

        // ── Локальная пасека с ульем, как после онбординга
        let hive = Hive(
            name: "Улей А",
            boxes: [Box(kind: .brood, frames: (0..<11).map { _ in
                var f = Frame.drawn()
                f.sealedBroodFraction = 0.61
                f.openBroodFraction = 0.2
                f.storesFraction = 0.12
                return f
            })],
            queen: Queen(introducedYear: 2026, markColour: .white),
            positionX: 0.3, positionY: 0.4,
            lastInspection: Date().addingTimeInterval(-2 * 86400))

        appState.setApiary(Apiary(name: "Общая пасека", latitude: 51.35, longitude: -1.99,
                                  system: .national, hives: [hive]))

        // ── bootstrap: пасеки на сервере нет, значит её надо завести
        await sync.bootstrap(appState: appState, auth: auth)
        check("bootstrap завёл пасеку и синхронизировался",
              isDone(sync.status), "\(sync.status)")
        check("версия улья пришла с сервера", sync.serverVersion(for: hive.id) == 1,
              "\(sync.serverVersion(for: hive.id))")

        // ── Правка уезжает
        appState.updateHive(id: hive.id) { $0.name = "Улей А (переименован)" }
        await sync.sync(state: appState)
        check("правка ушла, версия выросла", sync.serverVersion(for: hive.id) == 2,
              "\(sync.serverVersion(for: hive.id))")

        // ── Приглашаем второе устройство
        guard let apiaryId = appState.apiary?.id else { report(); return }
        var code: String?
        do { code = try await sync.createInvite(apiaryId: apiaryId) } catch {
            check("создание инвайта", false, "\(error)")
        }
        check("инвайт-код получен с сервера", (code?.count ?? 0) == 6, code ?? "nil")

        // ── Устройство B: свой AppState, свой SyncService, тот же сервер
        let tokensA = (TokenStore.accessToken, TokenStore.refreshToken)
        TokenStore.clear()

        let stateB = AppState()
        let authB = AuthService()
        let syncB = SyncService()
        stateB.attach(sync: syncB)
        syncB.reset()

        authB.signUp(email: "device.b.\(stamp)@example.com", password: "integraciya-parol-2")
        await settle(until: { authB.phase == .signedIn }, seconds: 10)
        check("устройство B: регистрация", authB.phase == .signedIn)

        if let code {
            do {
                try await syncB.acceptInvite(code: code)
                check("устройство B присоединилось по коду", true)
            } catch {
                check("устройство B присоединилось по коду", false, "\(error)")
            }
        }

        // У B локально пусто — пасека и улей должны приехать с сервера.
        stateB.setApiary(Apiary(name: "-", latitude: 0, longitude: 0, system: .national, hives: []))
        await syncB.sync(state: stateB)

        check("на B приехала пасека", stateB.apiary?.name == "Общая пасека",
              stateB.apiary?.name ?? "nil")
        check("на B приехал улей", stateB.hives.count == 1, "\(stateB.hives.count)")
        check("на B приехало новое имя улья",
              stateB.hives.first?.name == "Улей А (переименован)",
              stateB.hives.first?.name ?? "nil")
        check("на B целы рамки",
              stateB.hives.first?.boxes.first?.frames.count == 11,
              "\(stateB.hives.first?.boxes.first?.frames.count ?? -1)")
        check("на B цел печатный расплод",
              abs((stateB.hives.first?.boxes.first?.frames.first?.sealedBroodFraction ?? 0) - 0.61) < 0.001)

        // ── Часы роения на B считаются по приехавшим данным
        if let hiveB = stateB.hives.first {
            let projection = stateB.projection(for: hiveB)
            check("на B прогноз считается по синхронизированным данным",
                  !projection.days.isEmpty && projection.daysSinceInspection >= 2,
                  "дней с осмотра: \(projection.daysSinceInspection)")
        }

        // ── Конфликт: B правит, потом A правит от устаревшей версии
        if let hiveB = stateB.hives.first {
            stateB.updateHive(id: hiveB.id) { $0.name = "Улей А (правка B)" }
            await syncB.sync(state: stateB)
            check("правка B применена", syncB.serverVersion(for: hiveB.id) >= 3,
                  "\(syncB.serverVersion(for: hiveB.id))")
        }

        TokenStore.accessToken = tokensA.0
        TokenStore.refreshToken = tokensA.1

        appState.updateHive(id: hive.id) { $0.name = "Улей А (правка A)" }
        await sync.sync(state: appState)
        check("A увидел конфликт, а не молча перезаписал", !sync.conflicts.isEmpty,
              "конфликтов: \(sync.conflicts.count)")
        check("конфликт содержит серверное состояние",
              sync.conflicts.first?.server?.name == "Улей А (правка B)",
              sync.conflicts.first?.server?.name ?? "nil")

        // ── Разрешение конфликта человеком
        if let conflict = sync.conflicts.first {
            sync.resolveTakingServer(conflict, appState: appState)
            check("после «взять серверный» имя совпало с сервером",
                  appState.hive(id: hive.id)?.name == "Улей А (правка B)",
                  appState.hive(id: hive.id)?.name ?? "nil")
            check("конфликт снят", sync.conflicts.isEmpty)
        }

        // ── Удаление доезжает до сервера
        appState.deleteHive(id: hive.id)
        await sync.sync(state: appState)
        await syncB.sync(state: stateB)
        check("удаление улья дошло до устройства B", stateB.hives.isEmpty,
              "осталось: \(stateB.hives.count)")

        // ── Офлайн не считается ошибкой приложения
        TokenStore.clear()
        await sync.sync(state: appState)
        check("без сессии синхронизация молчит, а не падает", true)

        report()
    }

    // MARK: - Служебное

    private static func isDone(_ status: SyncService.Status) -> Bool {
        if case .done = status { return true }
        return false
    }

    /// Ждём асинхронного результата, не блокируя главный поток.
    /// Замыкание помечено @Sendable: иначе оно пересекало бы границу актора,
    /// что в Swift 6 уже ошибка, а не предупреждение.
    @MainActor
    private static func settle(until condition: @Sendable @MainActor () -> Bool,
                               seconds: Double) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private static func report() {
        print("[SyncChecks] пройдено: \(passed)   провалено: \(failed)")
        if !failures.isEmpty {
            print("[SyncChecks] провалы:")
            failures.forEach { print("  ✗ \($0)") }
        }
    }
}
#endif
