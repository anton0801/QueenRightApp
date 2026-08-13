//
//  AppState.swift
//  QueenRight
//
//  The one store the whole app reads. Owns the apiary record, runs the Swarm Clock on
//  demand, and writes through to disk on every mutation so nothing is ever lost at the
//  hive. Projections are memoised per hive so the board can be dragged without
//  re-simulating 120 days on every frame of the gesture.
//

import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {

    @Published private(set) var apiary: Apiary?
    @Published var preferences: Preferences
    @Published private(set) var weather: WeatherSeries = WeatherSeries()

    /// Set when a hive crosses imminent → calm, so the board can fire the single
    /// celebration in the app (§3).
    @Published var celebrateHiveId: String?

    let weatherService: WeatherService

    /// Служба синхронизации. Хранится сильной ссылкой, и цикла это не создаёт:
    /// SyncService не держит AppState, он получает его параметром вызова.
    private weak var syncService: SyncService?
    /// Меняется при каждой правке записи — по нему экраны запускают отложенную
    /// синхронизацию, не зная её подробностей.
    @Published private(set) var changeToken = UUID()

    private var projectionCache: [String: SwarmProjection] = [:]
    private var cancellables = Set<AnyCancellable>()

    /// The default is built inside the initialiser rather than in the parameter list,
    /// because a default argument is evaluated in a nonisolated context and
    /// `WeatherService` is main-actor bound.
    init(weatherService: WeatherService? = nil) {
        let weatherService = weatherService ?? WeatherService()
        self.weatherService = weatherService
        self.preferences = LocalStore.shared.load(Preferences.self, from: .preferences) ?? Preferences()
        self.apiary = LocalStore.shared.load(Apiary.self, from: .apiary)

        weatherService.$series
            .receive(on: RunLoop.main)
            .sink { [weak self] series in
                guard let self else { return }
                self.weather = series
                self.projectionCache.removeAll()
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Persistence

    func attach(sync: SyncService) {
        syncService = sync
    }

    private func persistApiary() {
        if let apiary {
            LocalStore.shared.save(apiary, to: .apiary)
        } else {
            LocalStore.shared.delete(.apiary)
        }
        // Сигнал экранам: есть что отправить. Сам запрос уйдёт с задержкой.
        changeToken = UUID()
    }

    func persistPreferences() {
        LocalStore.shared.save(preferences, to: .preferences)
    }

    // MARK: - Apiary

    func setApiary(_ apiary: Apiary) {
        self.apiary = apiary
        projectionCache.removeAll()
        persistApiary()
        weatherService.refreshIfNeeded(for: apiary)
    }

    func updateApiary(_ mutate: (inout Apiary) -> Void) {
        guard var a = apiary else { return }
        mutate(&a)
        apiary = a
        projectionCache.removeAll()
        persistApiary()
    }

    func refreshWeather(force: Bool = false) {
        guard let apiary else { return }
        weatherService.refreshIfNeeded(for: apiary, force: force)
    }

    // MARK: - Hives

    var hives: [Hive] { apiary?.hives ?? [] }

    func hive(id: String) -> Hive? {
        apiary?.hives.first { $0.id == id }
    }

    func addHive(_ hive: Hive) {
        updateApiary { $0.hives.append(hive) }
    }

    func deleteHive(id: String) {
        // Отметить удаление НАДО до того, как улей исчезнет локально: иначе
        // сервер о нём не узнает, и при следующем pull улей вернётся обратно.
        syncService?.noteLocalDeletion(hiveId: id)
        updateApiary { $0.hives.removeAll { $0.id == id } }
        projectionCache[id] = nil
    }

    /// Mutate a hive and re-run its clock. Fires the celebration when — and only when —
    /// the colony moves from imminent back to calm (§3).
    func updateHive(id: String, _ mutate: (inout Hive) -> Void) {
        guard let apiary, let index = apiary.hives.firstIndex(where: { $0.id == id }) else { return }

        let before = projection(for: apiary.hives[index]).riskState

        updateApiary { a in
            guard a.hives.indices.contains(index) else { return }
            mutate(&a.hives[index])
        }
        projectionCache[id] = nil

        guard let updated = hive(id: id) else { return }
        let after = projection(for: updated).riskState

        if before == .imminent && after == .calm {
            celebrateHiveId = id
            Haptics.swarmAverted()
        } else if before != .imminent && after == .imminent {
            Haptics.warning()
        }

        // Any change to a colony can change what is worth interrupting someone about.
        Task { await rescheduleAlerts() }
    }

    // MARK: - The clock

    func snapshot(for hive: Hive) -> ColonySnapshot {
        ColonySnapshot(hive: hive,
                       system: apiary?.system ?? .national,
                       latitude: apiary?.latitude ?? 51.5,
                       weather: weather)
    }

    func projection(for hive: Hive) -> SwarmProjection {
        if let cached = projectionCache[hive.id] { return cached }
        let p = SwarmClock.run(snapshot(for: hive))
        projectionCache[hive.id] = p
        return p
    }

    /// Run the clock on a hypothetical colony — used by the Actions sheet to draw the
    /// second path without touching the record.
    func projection(forHypothetical snapshot: ColonySnapshot) -> SwarmProjection {
        SwarmClock.run(snapshot)
    }

    func invalidateProjections() {
        projectionCache.removeAll()
    }

    // MARK: - Apiary-level readings

    /// Worst state across the yard, for the hub summary.
    var yardState: RiskState {
        hives.map { projection(for: $0).riskState }
            .min(by: { $0.urgency < $1.urgency }) ?? .calm
    }

    var isOutOfSeason: Bool {
        guard let apiary, !hives.isEmpty else { return false }
        return !SeasonWindow.isInSwarmSeason(latitude: apiary.latitude, date: Date())
    }

    /// Hives ordered for the inspection queue: worst first, then longest unlooked-at.
    var inspectionQueue: [Hive] {
        hives.sorted { a, b in
            let pa = projection(for: a), pb = projection(for: b)
            if pa.riskState.urgency != pb.riskState.urgency {
                return pa.riskState.urgency < pb.riskState.urgency
            }
            return a.daysSinceInspection() > b.daysSinceInspection()
        }
    }

    /// The next hive due a look, for the all-calm line.
    var nextDue: Hive? { inspectionQueue.first }

    // MARK: - Alerts

    /// Rebuild every scheduled alert from the current projections, so an alert never
    /// outlives the reason it was scheduled for.
    func rescheduleAlerts() async {
        let entries = hives.map { (hive: $0, projection: projection(for: $0)) }
        await SwarmAlerts.reschedule(hives: entries)
    }

    // MARK: - Reset (account deletion, §14)

    func wipeLocalData() {
        apiary = nil
        projectionCache.removeAll()
        preferences = Preferences()
        weatherService.clear()
        LocalStore.shared.wipeEverything()
    }
}
