//
//  InstallState.swift
//  QueenRight
//
//  Запасной идентификатор установки и отметки о том, что уже отправлено.
//
//  ЗАЧЕМ ЗАПАСНОЙ ID. Ключ устройства на сервере — af_id от AppsFlyer. Но SDK
//  может быть не сконфигурирован (нет ключей в сборке) или не прилинкован
//  вовсе — тогда `getAppsFlyerUID()` вернёт пустую строку, и запрос уйдёт без
//  ключа, то есть будет отвергнут. Запасной идентификатор закрывает эту дыру:
//  аналитика продолжает собираться, просто под собственным номером.
//
//  Он лежит в Keychain, а не в UserDefaults, чтобы пережить переустановку —
//  ровно там, где af_id её не переживает.
//

import Foundation

enum InstallState {

    private static let service = "com.rights.QueenRight.install"
    private static let traceKey = "fallback_trace"

    /// Отметка о последнем отправленном push-токене: повторно тот же не шлём.
    private static let sentTokenKey = "qr_sent_push_token"

    // MARK: - Идентификатор

    /// Идентификатор для сервера: af_id, если он есть, иначе собственный.
    static func resolvedTrace(preferred: String) -> String {
        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return fallbackTrace
    }

    /// Собственный идентификатор установки. Создаётся один раз.
    static var fallbackTrace: String {
        if let existing = readKeychain(traceKey), !existing.isEmpty {
            return existing
        }
        // Префикс отличает его от настоящего af_id в отчётах.
        let generated = "qr-" + UUID().uuidString.lowercased()
        writeKeychain(traceKey, generated)
        return generated
    }

    // MARK: - Push-токен

    /// Нужно ли досылать этот токен. Тот же самый второй раз не отправляем.
    static func shouldReport(pushToken: String) -> Bool {
        guard !pushToken.isEmpty else { return false }
        return UserDefaults.standard.string(forKey: sentTokenKey) != pushToken
    }

    static func markReported(pushToken: String) {
        UserDefaults.standard.set(pushToken, forKey: sentTokenKey)
    }

    // MARK: - Keychain

    private static func readKeychain(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ key: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)

        guard let data = value.data(using: .utf8) else { return }
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
