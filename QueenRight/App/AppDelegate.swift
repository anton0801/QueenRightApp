//
//  AppDelegate.swift
//  QueenRight
//
//  Push registration only. Notification permission is never requested here — it is
//  asked for in context, from Settings, the same way camera and location are (§11.13).
//

//import UIKit
//import UserNotifications
//import FirebaseCore
//import FirebaseMessaging
//import AppsFlyerLib
//
//final class AppDelegate: NSObject, UIApplicationDelegate {
//
//    func application(_ application: UIApplication,
//                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
//        UNUserNotificationCenter.current().delegate = self
//        if FirebaseService.isConfigured {
//            Messaging.messaging().delegate = self
//        }
//        configureAppsFlyer()
//        return true
//    }
//
//    /// Настройка трекера. `start()` здесь НЕ вызывается: сначала должен быть
//    /// получен ответ в ATT, иначе аттрибуция уйдёт без IDFA. Стартует его
//    /// AttributionService, когда окно ATT закрыто.
//    private func configureAppsFlyer() {
//        let devKey = (Bundle.main.object(forInfoDictionaryKey: "AppsFlyerDevKey") as? String) ?? ""
//        let appID = (Bundle.main.object(forInfoDictionaryKey: "AppsFlyerAppID") as? String) ?? ""
//
//        guard !devKey.isEmpty, !devKey.hasPrefix("REPLACE"),
//              !appID.isEmpty, !appID.hasPrefix("REPLACE") else {
//            // Ключи ещё не прописаны. UID устройства библиотека всё равно выдаёт,
//            // поэтому аналитика на своём сервере продолжает работать.
//            return
//        }
//
//        AppsFlyerLib.shared().appsFlyerDevKey = devKey
//        AppsFlyerLib.shared().appleAppID = appID
//        // Даёт SDK дождаться ответа в ATT, прежде чем слать первое событие.
//        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
////        #if DEBUG
////        AppsFlyerLib.shared().isDebug = true
////        #endif
//    }
//
//    func application(_ application: UIApplication,
//                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
//        guard FirebaseService.isConfigured else { return }
//        Messaging.messaging().apnsToken = deviceToken
//    }
//
//    func application(_ application: UIApplication,
//                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
//        // A hive that can't be pushed to still shows its state when the app is opened.
//    }
//}
//
//extension AppDelegate: UNUserNotificationCenterDelegate {
//    func userNotificationCenter(_ center: UNUserNotificationCenter,
//                                willPresent notification: UNNotification,
//                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
//        completionHandler([.banner, .sound, .list])
//    }
//
//    func userNotificationCenter(_ center: UNUserNotificationCenter,
//                                didReceive response: UNNotificationResponse,
//                                withCompletionHandler completionHandler: @escaping () -> Void) {
//        completionHandler()
//    }
//}
//
//extension AppDelegate: MessagingDelegate {
//    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
//        // Токен приходит асинхронно и при первом запуске обычно позже, чем
//        // уходит первый запрос об устройстве. Сохраняем — следующий запуск
//        // (или запрос конверсии) отправит его на сервер.
//        DeviceInfo.storePushToken(fcmToken)
//    }
//}

import UIKit
import FirebaseCore
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications
import AppsFlyerLib

final class AppDelegate: UIResponder, UIApplicationDelegate {

    private let parley = Parley()
    private let courier = Courier()
    private var trackerStarted = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseService.configureIfPossible()

        let devKey = (Bundle.main.object(forInfoDictionaryKey: "AppsFlyerDevKey") as? String) ?? ""
        let appID = (Bundle.main.object(forInfoDictionaryKey: "AppsFlyerAppID") as? String) ?? ""

        guard !devKey.isEmpty, !devKey.hasPrefix("REPLACE"),
              !appID.isEmpty, !appID.hasPrefix("REPLACE") else {
            return true
        }

        let sdk = AppsFlyerLib.shared()
        sdk.appsFlyerDevKey = devKey
        sdk.appleAppID = appID
        sdk.delegate = self
        sdk.deepLinkDelegate = self
        sdk.isDebug = false

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        if let cold = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            courier.bear(cold)
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(active), name: UIApplication.didBecomeActiveNotification, object: nil)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    @objc private func active() {
        guard #available(iOS 14, *) else {
            startTrackerOnce()
            return
        }
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            // Ответ уже есть — просто поднимаем сессию трекера.
            UserDefaults.standard.set(
                ATTrackingManager.trackingAuthorizationStatus.rawValue,
                forKey: CodexKey.attStatus)
            startTrackerOnce()
            return
        }

        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async { [weak self] in
                UserDefaults.standard.set(status.rawValue, forKey: CodexKey.attStatus)
                self?.startTrackerOnce()
            }
        }
    }

    private func startTrackerOnce() {
        guard !trackerStarted else { return }
        trackerStarted = true
        AppsFlyerLib.shared().start()
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { token, error in
            guard error == nil, let token = token else { return }
            UserDefaults.standard.set(token, forKey: CodexKey.fcm)
            UserDefaults.standard.set(token, forKey: CodexKey.push)
            // Тот же ключ читает DeviceInfo.pushToken — иначе токен сохранён,
            // но на сервер уходит пусто.
            UserDefaults(suiteName: Codex.suiteBoard)?.set(token, forKey: CodexKey.sharedFcm)

            // FCM отдаёт токен асинхронно и на первом запуске обычно ПОЗЖЕ
            // стартовых запросов — иначе он бы просто уехал вместе с ними.
            // Досылаем отдельно; тот же токен второй раз не отправляется.
            Task { @MainActor in await PushTokenReporter.report(token) }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        courier.bear(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        courier.bear(response.notification.request.content.userInfo)
        completionHandler()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        courier.bear(userInfo)
        completionHandler(.newData)
    }
}

extension AppDelegate: AppsFlyerLibDelegate, DeepLinkDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        Task { @MainActor in parley.take(conversionInfo) }
    }

    func onConversionDataFail(_ error: Error) {
        // Органика без данных или нет сети. Ждать больше нечего — отпускаем
        // сплеш, иначе приложение зависнет на старте из-за молчания трекера.
        Task { @MainActor in parley.giveUp() }
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status, let deepLink = result.deepLink else { return }
        Task { @MainActor in parley.mark(deepLink.clickEvent) }
    }
}

/// Сбор атрибуции: конверсия AppsFlyer + диплинки, с уточнением органики.
///
/// Порядок такой:
///  1. Пришла конверсия. Если `af_status` = Organic — это может быть неправдой:
///     AppsFlyer иногда не успевает связать установку с кликом и отдаёт органику,
///     которая через несколько секунд превращается в платную. Поэтому ждём 5
///     секунд и перезапрашиваем install_data напрямую.
///  2. Параллельно ждём диплинк — но не дольше 2,5 секунд.
///  3. Всё сливается в один результат и уходит ОДНИМ событием. Промежуточную
///     органику наружу не отдаём: на сервере не должно появиться значение,
///     которое через пять секунд окажется враньём.
///
/// Класс живёт на главном потоке целиком — отсюда @MainActor. Без него захват
/// self в Task был предупреждением, которое в Swift 6 становится ошибкой.
@MainActor
final class Parley {

    private var marks: [AnyHashable: Any] = [:]
    private var links: [AnyHashable: Any] = [:]
    private var glide: Task<Void, Never>?
    private var finished = false

    private let arena: Arena

    /// Сколько ждать перед уточнением органики.
    private static let organicRecheck: TimeInterval = 5
    /// Сколько ждать диплинк, когда конверсия уже пришла.
    private static let deepLinkGrace: TimeInterval = 2.5

    init(arena: Arena = Match()) {
        self.arena = arena
    }

    // MARK: - Вход

    func take(_ data: [AnyHashable: Any]) {
        marks = data

        if Self.looksOrganic(data) {
            // Не публикуем — сначала перепроверяем.
            recheckOrganic()
        } else if links.isEmpty {
            arm()
        } else {
            join()
        }
    }

    /// Конверсия не пришла (органика без данных, нет сети). Ждать больше нечего.
    func giveUp() {
        guard !finished else { return }
        join()
    }

    func mark(_ data: [AnyHashable: Any]) {
        guard UserDefaults.standard.bool(forKey: CodexKey.primed) == false else { return }
        links = data
        NotificationCenter.default.post(name: .boardLinks, object: nil,
                                        userInfo: ["deeplinksData": data])
        // Диплинк пришёл — ждать его больше не нужно, но уточнение органики,
        // если оно запущено, прерывать нельзя: оно про другое.
        if !marks.isEmpty, !Self.looksOrganic(marks) {
            glide?.cancel()
            glide = nil
            join()
        }
    }

    // MARK: - Уточнение органики

    private func recheckOrganic() {
        glide?.cancel()
        glide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.organicRecheck * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }

            let fresh = await self.arena.peek()
            // Заменяем только если перезапрос ДЕЙСТВИТЕЛЬНО дал больше: пустой
            // ответ или та же органика не должны затирать то, что уже есть.
            if !fresh.isEmpty, !Self.looksOrganic(fresh) {
                var replaced: [AnyHashable: Any] = [:]
                for (key, value) in fresh { replaced[key] = value }
                self.marks = replaced
            }
            self.join()
        }
    }

    private func arm() {
        glide?.cancel()
        glide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.deepLinkGrace * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.join()
        }
    }

    // MARK: - Публикация

    private func join() {
        guard !finished else { return }
        finished = true

        glide?.cancel()
        glide = nil

        var merged = marks
        for (key, value) in links {
            let tag = "deep_\(key)"
            if merged[tag] == nil { merged[tag] = value }
        }

        // Прямой канал вместо NotificationCenter: конверсия приходит один раз
        // за установку, и подписчика может не быть в момент рассылки. Relay
        // сохраняет значение и отдаёт его даже опоздавшему.
        AttributionRelay.shared.publish(merged)
    }

    /// Органика по версии AppsFlyer. Ключ приходит и строкой, и в разном регистре.
    private static func looksOrganic(_ data: [AnyHashable: Any]) -> Bool {
        guard let status = data["af_status"] else { return false }
        return "\(status)".caseInsensitiveCompare("Organic") == .orderedSame
    }
}

final class Courier {

    func bear(_ payload: [AnyHashable: Any]) {
        let trails: [[String]] = [["url"], ["data", "url"], ["aps", "data", "url"], ["custom", "url"]]
        var found: String?
        for trail in trails where found == nil {
            var node: Any? = payload
            for key in trail { node = (node as? [AnyHashable: Any])?[key] }
            if let leaf = node as? String, leaf.isEmpty == false { found = leaf }
        }
        guard let link = found else { return }

        UserDefaults.standard.set(link, forKey: CodexKey.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(name: .boardWake, object: nil, userInfo: ["temp_url": link])
        }
    }
}

protocol Arena {
    func peek() async -> [String: String]
}

final class Match: Arena {

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    func peek() async -> [String: String] {
        let uid = AppsFlyerLib.shared().getAppsFlyerUID()
        let raw = "https://gcdsdk.appsflyer.com/install_data/v4.0/\((Bundle.main.object(forInfoDictionaryKey: "AppsFlyerAppID") as? String) ?? "")?devkey=\((Bundle.main.object(forInfoDictionaryKey: "AppsFlyerDevKey") as? String) ?? "")&device_id=\(uid)"
        guard let url = URL(string: raw) else { return [:] }
        do {
            let (temp, response) = try await session.download(from: url)
            guard let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return [:] }
            let data = try Data(contentsOf: temp)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return dict.mapValues { "\($0)" }
        } catch {
            return [:]
        }
    }

}


enum Codex {
    static let suiteBoard = "group.queenright.board"
    static let cookieJar = "qr_board_cookies"
    static let ledgerFile = "qr_board_position.dat"
    static let boardFolder = "QueenRightBoard"
}

enum CodexKey {
    static let pushURL = "temp_url"
    static let fcm = "fcm_token"
    static let push = "push_token"
    static let sharedFcm = "shared_fcm"
    static let attStatus = "qr_att_status"
    static let primed = "qr_primed"
    static let routeMode = "qr_route_mode"
    static let consentGrant = "qr_consent_locked"
    static let consentDeny = "qr_consent_drifted"
    static let consentAt = "qr_consent_mapped_at"
}

extension Notification.Name {
    static let boardMarks = Notification.Name("ConversionDataReceived")
    static let boardLinks = Notification.Name("deeplink_values")
    static let boardWake = Notification.Name("LoadTempURL")
}
