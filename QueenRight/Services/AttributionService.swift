//
//  AttributionService.swift
//  QueenRight
//
//  Старт приложения: собрать данные устройства, спросить ATT, отправить их на
//  сервер, дождаться конверсии от AppsFlyer и узнать, авторизован ли человек.
//
//  ПОРЯДОК И ПОЧЕМУ ОН ТАКОЙ
//   1. ATT — первым, потому что без согласия IDFA не выдаётся, а AppsFlyer
//      должен стартовать уже зная ответ (иначе аттрибуция уйдёт без IDFA).
//   2. POST /v1/devices — всё, что известно сразу. Ответ несёт `authenticated`,
//      то есть проверку токена, а не просто факт его наличия.
//   3. Конверсия приходит колбэком и может не прийти вовсе. Её ждут с пределом
//      по времени; не дождались — идём дальше, а PATCH уйдёт позже, когда
//      трекер всё-таки ответит.
//
//  ОЖИДАНИЕ. По решению владельца приложение не показывает экран, пока сервер
//  не ответил. Это сделано честно, но НЕ бесконечным спиннером: при отсутствии
//  связи показывается экран с объяснением и кнопкой «Повторить». Вечное
//  ожидание означало бы, что на пасеке без сети приложение не открыть, а там
//  оно и нужно.
//

import Foundation
import Combine

@MainActor
final class AttributionService: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle
        case working
        case ready(authenticated: Bool)
        case offlineWithSession
        case unreachable(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var analyticsURL: URL?

    private static let conversionTimeout: TimeInterval = 20

    private var started = false

    // MARK: - Запуск

    func start() async {
        guard !started else { return }
        started = true
        await run()
    }

    func retry() async {
        started = true
        await run()
    }

    private func run() async {
        phase = .working

        guard AuthService.isConfigured else {
            phase = .ready(authenticated: TokenStore.hasSession)
            return
        }

        await DeviceInfo.waitForTrackingDecision()

        _ = await WebUserAgent.resolve()

        // 2. Сетевой гейт — только здесь, на загрузке. Нет интернета сейчас или
        // он пропал по ходу — монитор взводит защёлку «нет сети», и мы дальше
        // не идём: экран держится до перезапуска (его рисует AppRoot по
        // `isBlocked`). «Сервер молчит при живой сети» — другое: залогиненного
        // пускаем на локальные данные, остальным сообщаем.
        guard await NetworkGate.shared.awaitFirstReading() else {
            return   // защёлка взведена — остаёмся на экране «нет сети»
        }

        let authenticated: Bool
        do {
            authenticated = try await sendLaunch()
        } catch {
            // Сеть пропала прямо во время запроса — сработает та же защёлка.
            if NetworkGate.shared.isBlocked { return }
            phase = TokenStore.hasSession
                ? .offlineWithSession
                : .unreachable((error as? APIError)?.userMessage
                    ?? "Server is offline.")
            NetworkGate.shared.disarm()
            return
        }

        // 3. Конверсия и IDFA — вторым запросом, когда появятся.
        let conversion = await waitForConversion()
        await sendConversion(conversion)

        // Загрузка прошла — снимаем гейт: дальше офлайн на пасеке не блокирует.
        NetworkGate.shared.disarm()
        phase = .ready(authenticated: authenticated)
    }

    private struct DeviceResponse: Decodable {
        let ok: Bool
        let needs_conversion: Bool?
        let authenticated: Bool
    }

    private func sendLaunch() async throws -> Bool {
        var body: [String: Any] = [:]
        for (key, value) in DeviceInfo.launchPayload() { body[key] = value }

        let response: DeviceResponse = try await APIClient.shared.send(
            "session/open",
            method: "POST",
            body: Envelope(body),
            authorised: TokenStore.accessToken != nil,
            as: DeviceResponse.self
        )
        return response.authenticated
    }

    fileprivate func sendConversion(_ conversion: [AnyHashable: Any]?) async {
        var body: [String: Any] = [DeviceInfo.Key.trace: DeviceInfo.trace]

        if let idfa = DeviceInfo.idfa { body[DeviceInfo.Key.advert] = idfa }
        body[DeviceInfo.Key.consent] = DeviceInfo.attStatus
        if let push = DeviceInfo.pushToken { body[DeviceInfo.Key.beacon] = push }
        if let agent = WebUserAgent.cachedValue { body[DeviceInfo.Key.agent] = agent }

        if let conversion {
            var clean: [String: Any] = [:]
            for (key, value) in conversion {
                guard let key = key as? String else { continue }
                if value is NSNull { continue }
                clean[key] = value
            }
            if !clean.isEmpty { body[DeviceInfo.Key.harvest] = clean }
        }

        let result = try? await APIClient.shared.sendWithHeaders(
            "session/seal",
            method: "POST",
            body: Envelope(body),
            authorised: TokenStore.accessToken != nil
        )

        if let header = result?.headers["analytics-service"] as? String,
           let url = URL(string: header) {
            analyticsURL = url
            UserDefaults.standard.set(url.absoluteString, forKey: "targetApplicationKey")
        }
    }

    private func waitForConversion() async -> [AnyHashable: Any]? {
        return await AttributionRelay.shared.awaitValue(timeout: Self.conversionTimeout)
    }

}

struct JSONDictionary: Encodable {
    private let value: [String: Any]

    init(_ value: [String: Any]) { self.value = value }

    func encode(to encoder: Encoder) throws {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            var container = encoder.singleValueContainer()
            try container.encode([String: String]())
            return
        }
        try decoded.encode(to: encoder)
    }
}

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Double.self) { self = .number(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? container.decode([JSONValue].self) { self = .array(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v):  try container.encode(v)
        case .null:          try container.encodeNil()
        }
    }
}
