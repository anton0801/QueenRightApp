//
//  FirebaseService.swift
//  QueenRight
//
//  Firebase остался в проекте ТОЛЬКО ради push-уведомлений (FirebaseMessaging).
//  Аккаунты и данные переехали на собственный API: см. AuthService и SyncService.
//
//  FirebaseApp.configure() нужен, потому что Messaging без него не поднимется.
//  Отсутствие GoogleService-Info.plist не должно ронять приложение: пуши —
//  приятное дополнение, а часы роения работают и без них.
//

import Foundation
import FirebaseCore

enum FirebaseConfigStatus: Equatable {
    case ready
    /// Нет plist в бандле или он ещё с заглушками.
    case notConfigured
}

enum FirebaseService {
    private(set) static var status: FirebaseConfigStatus = .notConfigured
    static var isConfigured: Bool { status == .ready }

    /// Настройка Firebase. Идемпотентна.
    ///
    /// Защита от повторного вызова здесь не перестраховка: в SwiftUI `App.init()`
    /// выполняется РАНЬШЕ `didFinishLaunchingWithOptions`, поэтому вызов из обоих
    /// мест — обычное дело. Второй `FirebaseApp.configure()` бросает
    /// «Default app has already been configured» и роняет приложение ещё до
    /// первого экрана.
    static func configureIfPossible() {
        // Уже настроен — кем угодно, хоть напрямую FirebaseApp.configure().
        if FirebaseApp.app() != nil {
            status = .ready
            return
        }

        guard let dict = plistDict() else {
            status = .notConfigured
            return
        }
        let projectId = (dict["PROJECT_ID"] as? String) ?? ""
        let apiKey = (dict["API_KEY"] as? String) ?? ""

        guard !projectId.isEmpty,
              !projectId.uppercased().hasPrefix("REPLACE"),
              !apiKey.isEmpty,
              !apiKey.uppercased().hasPrefix("REPLACE") else {
            status = .notConfigured
            return
        }

        FirebaseApp.configure()
        status = .ready
    }

    private static func plistDict() -> NSDictionary? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else {
            return nil
        }
        return NSDictionary(contentsOfFile: path)
    }
}
