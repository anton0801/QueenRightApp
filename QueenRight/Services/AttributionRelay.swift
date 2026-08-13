//
//  AttributionRelay.swift
//  QueenRight
//
//  Прямой канал «сборщик конверсии → отправка на свой API».
//
//  ЗАЧЕМ ОН ВМЕСТО NotificationCenter. Уведомления — широковещательные и
//  безадресные: подписчика может не быть в момент отправки, и тогда результат
//  просто исчезает. Конверсия приходит РОВНО ОДИН РАЗ за установку, и потерять
//  её из-за гонки подписки недопустимо.
//
//  Здесь наоборот: значение сохраняется, и ожидающий получает его, даже если
//  подписался ПОСЛЕ публикации. Ждать можно из любого места и в любой момент.
//
//  Всё живёт на главном потоке: словарь от AppsFlyer имеет тип
//  `[AnyHashable: Any]`, который не Sendable, и таскать его между акторами
//  в Swift 6 запрещено.
//

import Foundation

@MainActor
final class AttributionRelay {

    static let shared = AttributionRelay()

    private var value: [AnyHashable: Any]?
    private var published = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init() {}

    /// Опубликовать итог сбора. Первый вызов побеждает: уточнение органики уже
    /// учтено сборщиком, и второй публикации быть не должно.
    func publish(_ data: [AnyHashable: Any]?) {
        guard !published else { return }
        published = true
        value = data

        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    /// Дождаться итога. Если он уже опубликован — возвращает немедленно.
    ///
    /// По истечении срока отдаёт то, что есть (обычно nil): сплеш не должен
    /// висеть вечно из-за молчания трекера.
    func awaitValue(timeout: TimeInterval) async -> [AnyHashable: Any]? {
        if published { return value }

        let deadline = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.releaseWaiters()
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if published {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }

        deadline.cancel()
        return value
    }

    /// Срок вышел — отпускаем ожидающих, но НЕ помечаем как опубликованное:
    /// конверсия может прийти позже, и тогда её ещё можно будет отправить.
    private func releaseWaiters() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    #if DEBUG
    /// Только для самопроверок.
    func resetForTesting() {
        value = nil
        published = false
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
    #endif
}
