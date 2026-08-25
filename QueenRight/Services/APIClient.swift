//
//  APIClient.swift
//  QueenRight
//
//  Клиент собственного API. Заменяет FirebaseAuth и FirebaseDatabase.
//
//  Три вещи, ради которых этот файл выглядит именно так:
//
//  1. Токены лежат в Keychain, а не в UserDefaults. UserDefaults — обычный plist
//     в контейнере приложения: он попадает в резервную копию и читается с
//     разблокированного устройства. Refresh-токен живёт 60 дней, и его утечка
//     равна утечке аккаунта.
//  2. Access-токен обновляется автоматически при 401, причём ровно один раз на
//     запрос: без этого истёкший токен вызвал бы бесконечную рекурсию.
//  3. Ошибка сети НЕ является ошибкой приложения. Пасека — это поле без связи;
//     борт, прогноз и захват рамки обязаны работать, когда API недоступен.
//

import Foundation

// MARK: - Настройка

enum APIConfig {
    /// Адрес сервера берётся из Info.plist (ключ QueenrightAPIBaseURL), а не из
    /// кода: сменить адрес при переезде или собрать отладочную версию против
    /// localhost можно, не трогая ни строчки Swift.
    ///
    /// На проде обязателен https — ATS в iOS блокирует http, и правильно делает.
    static let baseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "QueenrightAPIBaseURL") as? String,
           let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.host != nil {
            return url
        }
        return URL(string: "https://appqueenrights.space/v1")!
    }()

    static let requestTimeout: TimeInterval = 20
}

// MARK: - Ошибки

enum APIError: Error, Equatable {
    /// Нет сети. Это не сбой: приложение продолжает работать локально.
    case offline
    case unauthorized
    /// Расхождение версий — вызывающая сторона разбирается сама.
    case conflict(Data)
    case server(status: Int, code: String, message: String)
    case decoding
    case notConfigured

    var userMessage: String {
        switch self {
        case .offline:
            return "No connection. All works without connection."
        case .unauthorized:
            return "You need to log in."
        case .conflict:
            return "Data changed from other device."
        case .server(_, _, let message):
            return message
        case .decoding:
            return "Server response incorrect."
        case .notConfigured:
            return "Sync is not set on device."
        }
    }
}

private struct APIErrorBody: Decodable {
    let error: String
    let message: String
}

// MARK: - Хранилище токенов (Keychain)

/// Токены переживают переустановку не должны, но обязаны переживать перезапуск.
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — компромисс: фоновая
/// синхронизация после перезагрузки работает, а в резервную копию на другое
/// устройство токен не уедет.
enum TokenStore {
    private static let service = "com.rights.QueenRight.tokens"
    private static let accessKey = "access_token"
    private static let refreshKey = "refresh_token"

    static var accessToken: String? {
        get { read(accessKey) }
        set { write(accessKey, newValue) }
    }

    static var refreshToken: String? {
        get { read(refreshKey) }
        set { write(refreshKey, newValue) }
    }

    static var hasSession: Bool { refreshToken != nil }

    static func clear() {
        accessToken = nil
        refreshToken = nil
    }

    // MARK: Keychain

    private static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    private static func write(_ key: String, _ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        // Удаляем и записываем заново: SecItemUpdate не создаёт запись, если её
        // ещё нет, и первый вход тихо остался бы без токена.
        SecItemDelete(base as CFDictionary)

        guard let value, let data = value.data(using: .utf8) else { return }
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

// MARK: - Клиент

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.requestTimeout
        config.waitsForConnectivity = false
        // Токены и личные данные не должны оседать в кэше URL.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Чтобы два параллельных 401 не запустили две ротации: второй refresh
    /// предъявил бы уже использованный токен, сервер счёл бы это кражей и
    /// разлогинил бы пользователя (см. reuse detection на сервере).
    private var refreshTask: Task<Bool, Never>?

    // MARK: Публичные вызовы

    func send<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        authorised: Bool = true,
        as type: Response.Type
    ) async throws -> Response {
        let data = try await raw(path, method: method, query: query,
                                 body: body, authorised: authorised)
        if data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    /// Ответ вместе с заголовками — нужен там, где сервер отвечает не только
    /// телом (например адресом в `analytics-service`).
    func sendWithHeaders(
        _ path: String,
        method: String = "POST",
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        authorised: Bool = true
    ) async throws -> (data: Data, headers: [AnyHashable: Any]) {
        try await rawWithHeaders(path, method: method, query: query,
                                 body: body, authorised: authorised)
    }

    @discardableResult
    func sendNoContent(
        _ path: String,
        method: String = "POST",
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        authorised: Bool = true
    ) async throws -> Data {
        try await raw(path, method: method, query: query, body: body, authorised: authorised)
    }

    // MARK: Внутреннее

    private func raw(
        _ path: String,
        method: String,
        query: [String: String] = [:],
        body: (any Encodable)?,
        authorised: Bool,
        isRetry: Bool = false
    ) async throws -> Data {
        try await rawWithHeaders(path, method: method, query: query, body: body,
                                 authorised: authorised, isRetry: isRetry).data
    }

    private func rawWithHeaders(
        _ path: String,
        method: String,
        query: [String: String] = [:],
        body: (any Encodable)?,
        authorised: Bool,
        isRetry: Bool = false
    ) async throws -> (data: Data, headers: [AnyHashable: Any]) {
        guard let url = Self.url(path: path, query: query) else {
            throw APIError.decoding
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? encoder.encode(AnyEncodable(body))
        }
        if authorised, let token = TokenStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where
            error.code == .notConnectedToInternet ||
            error.code == .networkConnectionLost ||
            error.code == .timedOut ||
            error.code == .cannotFindHost ||
            error.code == .cannotConnectToHost ||
            error.code == .dataNotAllowed {
            throw APIError.offline
        } catch {
            throw APIError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.decoding }

        switch http.statusCode {
        case 200..<300:
            return (data, http.allHeaderFields)

        case 401:
            // Один раз пробуем обновить токен и повторить. Повторная неудача
            // означает, что сессия действительно кончилась.
            guard authorised, !isRetry, TokenStore.refreshToken != nil else {
                TokenStore.clear()
                throw APIError.unauthorized
            }
            guard await refreshIfPossible() else {
                TokenStore.clear()
                throw APIError.unauthorized
            }
            return try await rawWithHeaders(path, method: method, query: query, body: body,
                                            authorised: authorised, isRetry: true)

        case 409:
            throw APIError.conflict(data)

        default:
            let parsed = try? decoder.decode(APIErrorBody.self, from: data)
            throw APIError.server(
                status: http.statusCode,
                code: parsed?.error ?? "unknown",
                message: parsed?.message ?? "Something went wrong."
            )
        }
    }

    /// Сборка адреса.
    ///
    /// `appendingPathComponent` НЕЛЬЗЯ использовать для пути с параметрами: он
    /// считает "?" обычным символом имени файла и экранирует его в %3F, после
    /// чего сервер видит путь "/v1/sync%3Fsince=..." и честно отвечает 404.
    /// Параметры собираются через URLComponents, который кодирует их правильно
    /// и ровно один раз.
    static func url(path: String, query: [String: String]) -> URL? {
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components?.url
    }

    /// Обмен refresh-токена. Единственная точка, где он используется.
    func refreshIfPossible() async -> Bool {
        if let existing = refreshTask {
            return await existing.value
        }
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            defer { Task { await self.clearRefreshTask() } }
            return await self.performRefresh()
        }
        refreshTask = task
        return await task.value
    }

    private func clearRefreshTask() {
        refreshTask = nil
    }

    private func performRefresh() async -> Bool {
        guard let refresh = TokenStore.refreshToken else { return false }

        var request = URLRequest(url: APIConfig.baseURL.appendingPathComponent("auth/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? encoder.encode(["refresh_token": refresh])

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let tokens = try? decoder.decode(TokenPair.self, from: data) else {
            return false
        }

        TokenStore.accessToken = tokens.access_token
        TokenStore.refreshToken = tokens.refresh_token
        return true
    }
}

// MARK: - Типы ответов

struct TokenPair: Decodable {
    let token_type: String
    let access_token: String
    let refresh_token: String
    let expires_in: Int
}

struct AuthResponse: Decodable {
    struct User: Decodable {
        let id: String
        let email: String
    }
    let user: User
    let access_token: String
    let refresh_token: String
    let expires_in: Int
}

struct MeResponse: Decodable {
    struct User: Decodable {
        let id: String
        let email: String
    }
    struct Membership: Decodable {
        let id: String
        let name: String
        let role: String
    }
    let user: User
    let apiary: Membership?
}

struct EmptyResponse: Decodable {}

/// Тело, которое уходит зашифрованным, если ключ задан.
///
/// Когда шифрование включено, наружу видно только `{"payload":"<base64>"}` —
/// ни имён полей, ни значений. Без ключа отправляется открытым текстом: так
/// работает локальная отладка, и сервер про это предупреждает в логе.
struct Envelope: Encodable {
    private let object: [String: Any]

    init(_ object: [String: Any]) { self.object = object }

    private enum CodingKeys: String, CodingKey { case payload }

    func encode(to encoder: Encoder) throws {
        if let sealed = PayloadCrypto.seal(object) {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(sealed, forKey: .payload)
        } else {
            try JSONDictionary(object).encode(to: encoder)
        }
    }
}

/// Стирает конкретный тип, чтобы `body:` принимал любое Encodable.
private struct AnyEncodable: Encodable {
    private let encodeTo: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        encodeTo = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeTo(encoder)
    }
}
