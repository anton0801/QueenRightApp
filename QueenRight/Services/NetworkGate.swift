//
//  NetworkGate.swift
//  QueenRight
//
//  Сетевой гейт-защёлка — работает ТОЛЬКО на время загрузки (сплеш).
//
//  Поведение (по решению владельца, как в процессе-эталоне):
//   • Пока идёт старт, `NWPathMonitor` следит за путём.
//   • Нет сети при открытии или она пропала во время загрузки — фиксируем «нет
//     сети» (`isBlocked`) и БОЛЬШЕ НЕ снимаем: экран «нет сети» держится до
//     перезапуска приложения, даже если интернет вернулся. Так и задумано —
//     это защёлка, а не индикатор, который то появляется, то гаснет.
//   • Убрать экран можно только перезапуском: при новом старте, если сеть есть,
//     загрузка проходит; если нет — защёлка срабатывает снова.
//
//  Почему только на загрузке: QueenRight обязан работать на пасеке, где сети нет
//  вовсе — борт улья, прогноз и захват рамки живут локально. Поэтому, как только
//  загрузка прошла, гейт «разоружается» (`disarm`), и падение сети внутри
//  приложения уже ничего не блокирует. Иначе им нельзя было бы пользоваться
//  там, где он нужнее всего, и ревью почти наверняка завернуло бы приложение.
//

import Foundation
import Network

@MainActor
final class NetworkGate: ObservableObject {

    static let shared = NetworkGate()

    /// Защёлка «нет сети». Взводится один раз и до перезапуска не снимается.
    /// За ней следит AppRoot: `true` — показать полноэкранный экран «нет сети».
    @Published private(set) var isBlocked = false

    /// Текущая оценка пути (для отладки/полноты). Решения принимаются по
    /// `isBlocked`, а не по этому полю.
    @Published private(set) var isOnline = true

    /// Монитор уже хоть раз оценил путь. До этого судить о связи нельзя.
    private var hasFirstReading = false

    /// Латч активен только на загрузке. После входа в приложение — выключен,
    /// чтобы офлайн на пасеке не блокировал экран.
    private var armed = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.rights.QueenRight.network")
    private var started = false

    /// Ждут первой оценки пути — им важен сам факт оценки, а не «стало хорошо».
    private var firstReadingWaiters: [CheckedContinuation<Void, Never>] = []

    private init() {}

    /// Запустить монитор. Повторные вызовы безвредны.
    func start() {
        guard !started else { return }
        started = true

        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.handle(satisfied: satisfied) }
        }
        monitor.start(queue: queue)
    }

    private func handle(satisfied: Bool) {
        hasFirstReading = true
        isOnline = satisfied

        // Взводим защёлку ДО пробуждения ожидающих, чтобы они увидели уже
        // готовое решение. Только на загрузке (armed) и только один раз.
        if armed && !isBlocked && !satisfied {
            isBlocked = true
        }

        guard !firstReadingWaiters.isEmpty else { return }
        let waiters = firstReadingWaiters
        firstReadingWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    /// Дождаться первой оценки пути и вернуть, есть ли связь. Если связи нет —
    /// защёлка `isBlocked` к моменту возврата уже взведена.
    @discardableResult
    func awaitFirstReading() async -> Bool {
        start()
        if hasFirstReading { return isOnline }
        await withCheckedContinuation { continuation in
            firstReadingWaiters.append(continuation)
        }
        return isOnline
    }

    /// Загрузка прошла — снять гейт. Дальше падение сети экран не блокирует.
    func disarm() {
        armed = false
    }
}
