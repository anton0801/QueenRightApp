//
//  SyncService.swift
//  QueenRight
//
//  Дельта-синхронизация с собственным API. Пришло на смену FirebaseDatabase.
//
//  Локальный JSON остаётся источником истины для экрана: борт рисуется из него
//  и тогда, когда сети нет. Сервер — это место встречи двух устройств, а не
//  хранилище, без которого приложение не работает.
//
//  Единица обмена — улей целиком, с номером версии. Когда версии разошлись,
//  сервер отвечает 409 и отдаёт своё состояние; сливать два набора рамок
//  автоматически нельзя — получился бы улей, которого никто не видел вживую.
//

import Foundation
import Combine

// MARK: - Состояние синхронизации

/// Версии, от которых правило это устройство. Без них push не отличить
/// «я изменил свежие данные» от «я изменил то, что уже устарело».
struct SyncState: Codable, Equatable {
    var hiveVersions: [String: Int] = [:]
    var apiaryVersion: Int = 0
    var lastSyncedAt: Date?
    /// Ульи, удалённые локально, но ещё не подтверждённые сервером.
    var pendingDeletions: [String] = []
}

// MARK: - Служба

@MainActor
final class SyncService: ObservableObject {

    enum Status: Equatable {
        case idle
        case syncing
        /// Последняя синхронизация не удалась. Это НЕ ошибка приложения.
        case offline
        case failed(String)
        case done(Date)
    }

    @Published private(set) var status: Status = .idle
    /// Конфликты, которые должен разрешить человек.
    @Published var conflicts: [PushResponse.Conflict] = []

    private var state: SyncState
    private var inFlight = false

    /// Насколько назад отматывается точка отсчёта дельты, секунды.
    /// См. пояснение в `pull()` — это защита от секундной гранулярности DATETIME.
    private static let deltaOverlap: TimeInterval = 5

    init() {
        state = LocalStore.shared.load(SyncState.self, from: .syncState) ?? SyncState()
    }

    private func persist() {
        LocalStore.shared.save(state, to: .syncState)
    }

    func reset() {
        state = SyncState()
        conflicts = []
        status = .idle
        LocalStore.shared.delete(.syncState)
    }

    /// Улей ещё не отправлялся — значит на сервере его нет.
    func serverVersion(for hiveId: String) -> Int {
        state.hiveVersions[hiveId] ?? 0
    }

    func noteLocalDeletion(hiveId: String) {
        guard state.hiveVersions[hiveId] != nil else { return }
        if !state.pendingDeletions.contains(hiveId) {
            state.pendingDeletions.append(hiveId)
            persist()
        }
    }

    // MARK: - Запуск

    private var debounceTask: Task<Void, Never>?

    /// Первое подключение после входа. Решает, кто кого догоняет:
    ///  * на сервере пасеки нет, локально есть — заводим её на сервере;
    ///  * на сервере есть — просто синхронизируемся, сервер главнее только
    ///    в том смысле, что он уже знает про второго пасечника.
    func bootstrap(appState: AppState, auth: AuthService) async {
        guard AuthService.isConfigured, TokenStore.hasSession else { return }

        await auth.refreshProfile()

        if auth.role == nil, let local = appState.apiary, state.apiaryVersion == 0 {
            do {
                try await createRemoteApiary(from: local)
            } catch {
                // Уже состоит в пасеке или нет связи — обычная синхронизация разберётся.
            }
        }
        await sync(state: appState)
    }

    /// Синхронизация с задержкой: правки на борту идут очередями (перетащил
    /// рамку, применил действие, снял кадр), и слать запрос на каждое движение
    /// пальца — значит жечь батарею и трафик там, где связи и так еле хватает.
    func scheduleSync(appState: AppState, after seconds: Double = 2.5) {
        guard AuthService.isConfigured, TokenStore.hasSession else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.sync(state: appState)
        }
    }

    // MARK: - Полный цикл

    /// Сначала push, потом pull. Порядок важен: иначе свежие правки с сервера
    /// перезаписали бы локальные ещё до того, как те уехали.
    func sync(state appState: AppState) async {
        guard AuthService.isConfigured, TokenStore.hasSession else { return }
        guard !inFlight else { return }
        inFlight = true
        status = .syncing
        defer { inFlight = false }

        do {
            try await push(appState: appState)
            try await pull(appState: appState)
            state.lastSyncedAt = Date()
            persist()
            status = .done(Date())
        } catch APIError.offline {
            // Ровно тот случай, ради которого приложение локальное.
            status = .offline
        } catch APIError.unauthorized {
            status = .failed("Please sign in again.")
        } catch {
            status = .failed((error as? APIError)?.userMessage ?? "Couldn’t sync.")
        }
    }

    // MARK: - Отправка

    private func push(appState: AppState) async throws {
        var payload: [HiveDTO] = []

        for hive in appState.hives {
            var dto = Self.dto(from: hive)
            dto.base_version = serverVersion(for: hive.id)
            payload.append(dto)
        }

        for deletedId in state.pendingDeletions {
            payload.append(HiveDTO(
                id: deletedId,
                name: "-",
                position_x: 0.5,
                position_y: 0.5,
                last_inspection: Date(),
                payload: HivePayload(
                    boxes: [], queen: Queen(introducedYear: 2000, markColour: .unmarked),
                    cellObservations: [], cellsCutAt: nil, queenlessSince: nil,
                    swarmEvents: [], archivedProjections: [], createdAt: Date()
                ),
                base_version: serverVersion(for: deletedId),
                deleted: true
            ))
        }

        guard !payload.isEmpty else { return }

        do {
            let response: PushResponse = try await APIClient.shared.send(
                "sync", method: "POST", body: ["hives": payload], as: PushResponse.self
            )
            apply(push: response)
        } catch APIError.conflict(let data) {
            // 409 приходит, когда часть ульев не сошлась по версии. Применённые
            // в том же ответе всё равно нужно учесть, иначе они уедут ещё раз.
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let response = try? decoder.decode(PushResponse.self, from: data) {
                apply(push: response)
            }
        }
    }

    private func apply(push response: PushResponse) {
        for applied in response.applied {
            state.hiveVersions[applied.id] = applied.version
            state.pendingDeletions.removeAll { $0 == applied.id }
        }
        for conflict in response.conflicts where conflict.reason == "deleted" {
            // Улей удалили с другого устройства — наша версия больше не нужна.
            state.hiveVersions[conflict.id] = nil
            state.pendingDeletions.removeAll { $0 == conflict.id }
        }
        conflicts = response.conflicts.filter { $0.reason == "version_conflict" }
        persist()
    }

    // MARK: - Приём

    private func pull(appState: AppState) async throws {
        var query: [String: String] = [:]
        if let since = state.lastSyncedAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            // Экранированием занимается URLComponents в APIClient. Кодировать
            // здесь ещё раз означало бы прислать серверу %252D вместо дефиса.
            //
            // Запас в несколько секунд обязателен. MySQL DATETIME хранит время
            // с точностью до секунды, а выборка дельты идёт строго «позже», —
            // значит правка, сделанная в ту же секунду, в которую прошла
            // предыдущая синхронизация, не попала бы в выборку НИКОГДА. Для
            // пасеки, которую ведут вдвоём, это потерянный улей.
            //
            // Перекрытие безопасно: применение того же улья второй раз ничего
            // не меняет — сравнение идёт по версии, а не по факту получения.
            query["since"] = formatter.string(from: since.addingTimeInterval(-Self.deltaOverlap))
        }

        let response: PullResponse = try await APIClient.shared.send(
            "sync", query: query, as: PullResponse.self)

        guard let remoteApiary = response.apiary else { return }

        appState.updateApiary { apiary in
            apiary.name = remoteApiary.name
            apiary.latitude = remoteApiary.latitude
            apiary.longitude = remoteApiary.longitude
            if let system = HiveSystem(rawValue: remoteApiary.system) {
                apiary.system = system
            }
        }
        state.apiaryVersion = remoteApiary.version

        for dto in response.hives {
            let incoming = Self.hive(from: dto)
            state.hiveVersions[dto.id] = dto.version ?? 0

            if appState.hive(id: dto.id) != nil {
                appState.updateHive(id: dto.id) { hive in
                    hive = incoming
                }
            } else {
                appState.addHive(incoming)
            }
        }

        for deletedId in response.deleted_hive_ids {
            appState.deleteHive(id: deletedId)
            state.hiveVersions[deletedId] = nil
        }

        persist()
    }

    // MARK: - Разрешение конфликтов
    //
    // Сервер намеренно НЕ сливает две правки: набор рамок — это то, что человек
    // видел своими глазами, и машинное объединение дало бы улей, которого не
    // существовало. Поэтому выбор всегда за пасечником.

    /// Принять серверную версию улья: перезаписывает локальную.
    func resolveTakingServer(_ conflict: PushResponse.Conflict, appState: AppState) {
        guard let server = conflict.server else { return }
        let incoming = Self.hive(from: server)
        state.hiveVersions[server.id] = server.version ?? 0

        if appState.hive(id: server.id) != nil {
            appState.updateHive(id: server.id) { $0 = incoming }
        } else {
            appState.addHive(incoming)
        }
        conflicts.removeAll { $0.id == conflict.id }
        persist()
    }

    /// Оставить свою версию: принимаем серверный номер версии как основу, но данные
    /// шлём свои. Следующий push пройдёт, потому что версия теперь совпадает.
    func resolveKeepingLocal(appState: AppState) {
        for conflict in conflicts {
            if let serverVersion = conflict.server?.version {
                state.hiveVersions[conflict.id] = serverVersion
            }
        }
        conflicts = []
        persist()
        Task { await sync(state: appState) }
    }

    // MARK: - Пасека и участники

    private struct ApiaryEnvelope: Codable { var apiary: ApiaryDTO }
    private struct InviteResponse: Codable { var code: String; var expires_at: Date }
    struct MemberDTO: Codable, Identifiable {
        var id: String
        var email: String
        var role: String
    }
    private struct MembersResponse: Codable { var members: [MemberDTO]; var max: Int }

    /// Завести локальную пасеку на сервере. Вызывается после входа, когда пасека
    /// уже есть на устройстве, но сервер о ней не знает.
    func createRemoteApiary(from apiary: Apiary) async throws {
        let response: ApiaryEnvelope = try await APIClient.shared.send(
            "apiaries",
            method: "POST",
            body: [
                // Свой идентификатор, а не серверный: локальная запись и её копия
                // на сервере должны быть одной и той же пасекой.
                "id": apiary.id,
                "name": apiary.name,
                "latitude": String(apiary.latitude),
                "longitude": String(apiary.longitude),
                "system": apiary.system.rawValue,
            ],
            as: ApiaryEnvelope.self
        )
        state.apiaryVersion = response.apiary.version
        persist()
    }

    /// Код генерирует СЕРВЕР: только он может проверить, что код ещё не занят.
    /// Локальная генерация давала бы столкновения между устройствами.
    func createInvite(apiaryId: String) async throws -> String {
        let response: InviteResponse = try await APIClient.shared.send(
            "apiaries/\(apiaryId)/invites", method: "POST", as: InviteResponse.self
        )
        return response.code
    }

    func acceptInvite(code: String) async throws {
        let response: ApiaryEnvelope = try await APIClient.shared.send(
            "invites/\(code.uppercased())/accept", method: "POST", as: ApiaryEnvelope.self
        )
        state.apiaryVersion = response.apiary.version
        // После присоединения локальных версий ульев нет — заберём всё заново.
        state.hiveVersions = [:]
        state.lastSyncedAt = nil
        persist()
    }

    func members(apiaryId: String) async throws -> [MemberDTO] {
        let response: MembersResponse = try await APIClient.shared.send(
            "apiaries/\(apiaryId)/members", as: MembersResponse.self
        )
        return response.members
    }

    // MARK: - Преобразования

    static func dto(from hive: Hive) -> HiveDTO {
        HiveDTO(
            id: hive.id,
            name: hive.name,
            position_x: hive.positionX,
            position_y: hive.positionY,
            last_inspection: hive.lastInspection,
            payload: HivePayload(
                boxes: hive.boxes,
                queen: hive.queen,
                cellObservations: hive.cellObservations,
                cellsCutAt: hive.cellsCutAt,
                queenlessSince: hive.queenlessSince,
                swarmEvents: hive.swarmEvents,
                archivedProjections: hive.archivedProjections,
                createdAt: hive.createdAt
            ),
            version: nil,
            base_version: nil,
            deleted: nil
        )
    }

    static func hive(from dto: HiveDTO) -> Hive {
        Hive(
            id: dto.id,
            name: dto.name,
            boxes: dto.payload.boxes,
            queen: dto.payload.queen,
            positionX: dto.position_x,
            positionY: dto.position_y,
            lastInspection: dto.last_inspection,
            cellObservations: dto.payload.cellObservations,
            cellsCutAt: dto.payload.cellsCutAt,
            queenlessSince: dto.payload.queenlessSince,
            swarmEvents: dto.payload.swarmEvents,
            archivedProjections: dto.payload.archivedProjections,
            createdAt: dto.payload.createdAt
        )
    }
}
