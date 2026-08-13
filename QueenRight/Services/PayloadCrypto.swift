//
//  PayloadCrypto.swift
//  QueenRight
//
//  Шифрование тела запросов к своему API: AES-256-GCM.
//
//  ФОРМАТ. `AES.GCM.SealedBox.combined` из CryptoKit склеивает
//  `nonce[12] || ciphertext || tag[16]` — ровно то, что разбирает Crypto.php на
//  сервере. Своего конверта поэтому не понадобилось: обе стороны читают одно и
//  то же без договорённостей сверх этой.
//
//  ПОЧЕМУ GCM, А НЕ CBC. GCM даёт не только шифрование, но и аутентификацию:
//  подменённый по дороге байт не расшифруется вовсе, вместо того чтобы стать
//  мусором, который парсер попробует разобрать.
//
//  Шифрование поверх TLS не избыточно: оно закрывает тело от перехвата на
//  устройстве с установленным корневым сертификатом — то есть от самого
//  распространённого способа посмотреть, что шлёт чужое приложение.
//

import Foundation
import CryptoKit

enum PayloadCrypto {

    /// Ключ задан — значит шифруем. Пустой ключ означает открытую отправку,
    /// и это допустимо только на локальной отладке.
    static var isEnabled: Bool { key != nil }

    /// Запечатать словарь. Возвращает base64 или nil, если ключа нет.
    static func seal(_ object: [String: Any]) -> String? {
        guard let key else { return nil }
        guard JSONSerialization.isValidJSONObject(object),
              let plain = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        guard let sealed = try? AES.GCM.seal(plain, using: key),
              let combined = sealed.combined else {
            return nil
        }
        return combined.base64EncodedString()
    }

    // MARK: - Ключ

    /// Ключ из Info.plist (`QueenrightPayloadKey`), 64 hex-символа.
    ///
    /// Ключ неверной длины считается отсутствующим, а не обрезается: работать
    /// с укороченным ключом хуже, чем не шифровать, потому что создаёт
    /// видимость защиты. О таком пишем в лог сборки.
    private static let key: SymmetricKey? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "QueenrightPayloadKey") as? String
        else { return nil }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("REPLACE") else { return nil }

        if let data = Data(hexString: trimmed), data.count == 32 {
            return SymmetricKey(data: data)
        }
        if let data = Data(base64Encoded: trimmed), data.count == 32 {
            return SymmetricKey(data: data)
        }

        NSLog("[PayloadCrypto] ключ задан, но не даёт 32 байта — шифрование выключено")
        return nil
    }()
}

extension Data {
    /// Разбор строки из шестнадцатеричных пар. Возвращает nil на любой мусор,
    /// а не молча пропускает плохие символы.
    init?(hexString: String) {
        let chars = Array(hexString.utf8)
        guard chars.count % 2 == 0 else { return nil }

        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)

        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 0x30...0x39: return c - 0x30            // 0-9
            case 0x61...0x66: return c - 0x61 + 10       // a-f
            case 0x41...0x46: return c - 0x41 + 10       // A-F
            default: return nil
            }
        }

        var index = 0
        while index < chars.count {
            guard let hi = nibble(chars[index]), let lo = nibble(chars[index + 1]) else {
                return nil
            }
            bytes.append(hi << 4 | lo)
            index += 2
        }
        self.init(bytes)
    }
}
