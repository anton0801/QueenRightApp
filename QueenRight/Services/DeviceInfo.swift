//
//  DeviceInfo.swift
//  QueenRight
//
//  Сбор того, что известно об устройстве. Ничего не отправляет — только собирает,
//  поэтому легко проверяется и не зависит от сети.
//
//  Разделение на «сразу» и «позже» здесь не формальность: af_id, bundle_id и
//  локаль доступны в момент запуска, а IDFA появляется только после ответа в
//  ATT, push-токен — когда его выдаст FCM, конверсия — когда ответит трекер.
//  Ждать их всех ради одного запроса значит не отправить ничего, если трекер
//  промолчал.
//

import Foundation
import UIKit
import AppTrackingTransparency
import AdSupport
#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif
import FirebaseCore
import FirebaseMessaging

enum DeviceInfo {

    /// Ключ, под которым push-токен сохраняет AppDelegate (CodexKey.push).
    /// Значение обязано совпадать с ним: разные ключи означали бы, что токен
    /// сохранён, а на сервер уходит пусто.
    static let pushTokenKey = CodexKey.push

    // MARK: - Доступно сразу

    /// Имена полей на пути «приложение → свой API».
    ///
    /// Они НАМЕРЕННО не совпадают с общепринятыми (`af_id`, `push_token`…):
    /// одинаковый набор ключей в десятке приложений — это отпечаток, по
    /// которому видно, что все они сделаны по одному шаблону. Сервер разворачивает
    /// их обратно (см. FieldMap.php), а во внешнюю аналитику уходит уже
    /// фиксированный формат.
    ///
    /// Внутрь конверсии это НЕ распространяется: ответ трекера пересылается
    /// как есть, ни один его ключ не переименовывается.
    enum Key {
        static let trace   = "trace"     // af_id
        static let plat    = "plat"      // os
        static let pack    = "pack"      // bundle_id
        static let relay   = "relay"     // firebase sender id
        static let shelf   = "shelf"     // store_id
        static let beacon  = "beacon"    // push_token
        static let tongue  = "tongue"    // locale
        static let vendor  = "vendor"    // idfv
        static let advert  = "advert"    // idfa
        static let consent = "consent"   // att_status
        static let build   = "build"     // app_version
        static let platver = "platver"   // os_version
        static let frame   = "frame"     // device_model
        static let agent   = "agent"     // user_agent
        static let harvest = "harvest"   // conversion (содержимое не трогаем)
    }

    /// Данные первого запроса. Пустые значения не кладутся вовсе: сервер
    /// понимает отсутствие поля как «пока неизвестно» и не затирает то, что
    /// уже сохранил (см. COALESCE в DeviceController).
    static func launchPayload() -> [String: String] {
        var body: [String: String] = [:]

        body[Key.plat] = "iOS"
        // Если SDK не отдал UID, берём собственный — иначе запрос уйдёт без
        // ключа устройства и будет отвергнут.
        body[Key.trace] = InstallState.resolvedTrace(preferred: appsFlyerUID)
        put(&body, Key.pack, Bundle.main.bundleIdentifier)
        put(&body, Key.relay, firebaseSenderID)
        put(&body, Key.shelf, storeID)
        put(&body, Key.beacon, pushToken)
        body[Key.tongue] = locale
        put(&body, Key.vendor, UIDevice.current.identifierForVendor?.uuidString)
        body[Key.consent] = attStatus
        put(&body, Key.build, appVersion)
        body[Key.platver] = UIDevice.current.systemVersion
        body[Key.frame] = deviceModel
        put(&body, Key.agent, WebUserAgent.cachedValue)

        return body
    }

    /// Идентификатор, под которым устройство известно серверу.
    static var trace: String {
        InstallState.resolvedTrace(preferred: appsFlyerUID)
    }

    // MARK: - Отдельные значения

    static var appsFlyerUID: String {
        #if canImport(AppsFlyerLib)
        return AppsFlyerLib.shared().getAppsFlyerUID()
        #else
        return ""
        #endif
    }

    /// GCM Sender ID из GoogleService-Info.plist (ключ GCM_SENDER_ID).
    ///
    /// ВНИМАНИЕ, ИМЯ ПОЛЯ НЕ СОВПАДАЕТ С СОДЕРЖИМЫМ. Поле API называется
    /// `firebase_project_id`, но в нём лежит именно Sender ID — числовой
    /// идентификатор отправителя пушей (например 63306266999), а НЕ строковый
    /// PROJECT_ID вида `queenright-a273c`. Так решено владельцем: под этим
    /// именем значение ждёт принимающая сторона.
    ///
    /// Не «чините» на `options.projectID` — сломаете сверку на бэкенде.
    static var firebaseSenderID: String? {
        FirebaseApp.app()?.options.gcmSenderID
    }

    /// Идентификатор приложения в App Store. Лежит рядом с ключом AppsFlyer,
    /// потому что это то же самое число.
    static var storeID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "AppsFlyerAppID") as? String
        guard let value, !value.isEmpty, !value.hasPrefix("REPLACE") else { return nil }
        return value
    }

    /// Токен пуша. Сохранённый переживает запуск; свежий у Messaging может ещё
    /// не появиться — при первом старте это норма.
    static var pushToken: String? {
        if let stored = UserDefaults.standard.string(forKey: pushTokenKey), !stored.isEmpty {
            return stored
        }
        return Messaging.messaging().fcmToken
    }

    static func storePushToken(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        UserDefaults.standard.set(token, forKey: pushTokenKey)
    }

    /// Две буквы в верхнем регистре: RU, EN.
    static var locale: String {
        Locale.preferredLanguages.first?.prefix(2).uppercased() ?? "EN"
    }

    static var appVersion: String? {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (s?, b?): return "\(s) (\(b))"
        case let (s?, nil): return s
        default: return nil
        }
    }

    /// Машинное имя вроде iPhone16,1 — оно полезнее маркетингового названия.
    static var deviceModel: String {
        // В симуляторе uname возвращает архитектуру хоста (arm64), а настоящая
        // модель лежит в переменной окружения. Без этого вся отладочная
        // статистика писалась бы как «arm64».
        if let simulated = ProcessInfo.processInfo
            .environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) }
        }
        return machine ?? UIDevice.current.model
    }

    // MARK: - ATT и IDFA

    static var attStatus: String {
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .authorized:    return "authorized"
        case .denied:        return "denied"
        case .restricted:    return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default:    return "notDetermined"
        }
    }

    /// Рекламный идентификатор.
    ///
    /// Возвращает nil, если согласия нет. Именно nil, а не строку из нулей:
    /// иначе «отказался» и «не спрашивали» слились бы в отчётах в одно.
    static var idfa: String? {
        guard ATTrackingManager.trackingAuthorizationStatus == .authorized else { return nil }
        let value = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        guard value != "00000000-0000-0000-0000-000000000000" else { return nil }
        return value
    }

    /// Дожидается ответа в ATT, НЕ запрашивая его.
    ///
    /// Запрашивает AppDelegate — он владеет AppsFlyer и обязан стартовать SDK
    /// сразу после ответа. Спрашивать во втором месте нельзя: системное окно
    /// одно, и два конкурирующих запроса дают гонку.
    ///
    /// Ждём ради того, чтобы в ПЕРВЫЙ запрос об устройстве попали настоящие
    /// `att_status` и IDFA, а не «notDetermined» с пустым идентификатором.
    @discardableResult
    static func waitForTrackingDecision(
        timeout: TimeInterval = 30
    ) async -> ATTrackingManager.AuthorizationStatus {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let status = ATTrackingManager.trackingAuthorizationStatus
            if status != .notDetermined { return status }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        // Человек не ответил за отведённое время — идём дальше без IDFA.
        return ATTrackingManager.trackingAuthorizationStatus
    }

    // MARK: -

    private static func put(_ body: inout [String: String], _ key: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        body[key] = value
    }
}
