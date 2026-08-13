//
//  PushTokenReporter.swift
//  QueenRight
//
//  Досылка push-токена.
//
//  ЗАЧЕМ ОТДЕЛЬНО. FCM выдаёт токен асинхронно, и на первом запуске он почти
//  всегда появляется ПОЗЖЕ стартовых запросов. Без досылки он попал бы на
//  сервер только со следующим открытием приложения — то есть у части установок
//  не оказалось бы токена вовсе.
//
//  Повторно тот же токен не отправляется: отметка о последнем отправленном
//  лежит в InstallState.
//

import Foundation

enum PushTokenReporter {

    @MainActor
    static func report(_ token: String) async {
        guard AuthService.isConfigured else { return }
        guard InstallState.shouldReport(pushToken: token) else { return }

        var body: [String: Any] = [
            DeviceInfo.Key.trace: DeviceInfo.trace,
            DeviceInfo.Key.beacon: token,
        ]
        body[DeviceInfo.Key.plat] = "iOS"

        do {
            _ = try await APIClient.shared.sendNoContent(
                "session/open",
                method: "POST",
                body: Envelope(body),
                authorised: TokenStore.accessToken != nil
            )
            // Помечаем только после подтверждённой отправки: иначе токен,
            // потерянный из-за обрыва связи, больше никогда бы не ушёл.
            InstallState.markReported(pushToken: token)
        } catch {
            // Нет сети — попробуем при следующем появлении токена или запуске.
        }
    }
}
