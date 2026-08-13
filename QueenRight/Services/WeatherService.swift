//
//  WeatherService.swift
//  QueenRight
//
//  Caching layer over Open-Meteo (§13). One fetch per apiary per day, coalesced across
//  every hive on the site. Archive days are kept permanently; the forecast tail has a
//  6-hour TTL. Offline with a cache says nothing at all; offline without one says so
//  plainly and the clock carries on running on brood and space.
//

import Foundation

struct WeatherCache: Codable {
    var apiaryId: String
    var latitude: Double
    var longitude: Double
    var days: [WeatherDay]
    var fetchedAt: Date
}

@MainActor
final class WeatherService: ObservableObject {

    @Published private(set) var series = WeatherSeries()
    @Published private(set) var lastError: WeatherError?
    @Published private(set) var isLoading = false

    /// Forecast tail TTL.
    private let ttlHours: Double = 6
    private var inFlight: Task<Void, Never>?
    private var cache: WeatherCache?

    init() {
        cache = LocalStore.shared.load(WeatherCache.self, from: .weather)
        if let cache {
            series = WeatherSeries(days: cache.days, fetchedAt: cache.fetchedAt)
        }
    }

    /// Refresh if the cache is missing, stale, or for a different site.
    /// Safe to call from every screen — repeat calls coalesce onto one request.
    func refreshIfNeeded(for apiary: Apiary, force: Bool = false) {
        guard apiary.latitude != 0 || apiary.longitude != 0 else {
            lastError = .noCoordinates
            return
        }

        if !force, let cache,
           cache.apiaryId == apiary.id,
           abs(cache.latitude - apiary.latitude) < 0.01,
           abs(cache.longitude - apiary.longitude) < 0.01,
           Date().timeIntervalSince(cache.fetchedAt) / 3600 < ttlHours {
            return
        }

        // Coalesce: one request per apiary per refresh cycle, across all hives.
        guard inFlight == nil else { return }

        inFlight = Task { [weak self] in
            guard let self else { return }
            await self.fetch(apiary: apiary)
            self.inFlight = nil
        }
    }

    private func fetch(apiary: Apiary) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let days = try await OpenMeteoClient.shared.recentDaily(
                latitude: apiary.latitude, longitude: apiary.longitude)
            guard !days.isEmpty else {
                lastError = .decode
                return
            }
            let now = Date()
            let fresh = WeatherCache(apiaryId: apiary.id,
                                     latitude: apiary.latitude,
                                     longitude: apiary.longitude,
                                     days: days,
                                     fetchedAt: now)
            cache = fresh
            series = WeatherSeries(days: days, fetchedAt: now)
            lastError = nil
            LocalStore.shared.save(fresh, to: .weather)
        } catch let error as WeatherError {
            // Offline WITH a usable cache says nothing — the reading simply carries
            // its age on the flow line (§13).
            if case .offline = error, !series.isEmpty {
                lastError = nil
            } else {
                lastError = error
            }
        } catch {
            lastError = .other(error.localizedDescription)
        }
    }

    func clear() {
        cache = nil
        series = WeatherSeries()
        lastError = nil
        LocalStore.shared.delete(.weather)
    }

    // MARK: - The apiary-wide forage line (§5.1)

    /// "Flow on, 5 of the last 7 days" — or its honest absence.
    func flowLineText(now: Date = Date()) -> String {
        guard !series.isEmpty else {
            return "No forage reading yet. The clock runs on brood and space."
        }
        let recent = series.recentFlowDays(endingAt: now)
        guard recent.total > 0 else {
            return "No forage reading yet. The clock runs on brood and space."
        }
        let on = recent.flow >= 4
        let head = on ? "Flow on" : "Flow off"
        return "\(head), \(recent.flow) of the last \(recent.total) days"
    }

    /// Past 48 hours the line states its own age and the flowResumption term is
    /// suspended rather than guessed (§13).
    func stalenessText(now: Date = Date()) -> String? {
        guard series.isStale(now: now), let age = series.ageInDays(now: now) else { return nil }
        if age == 0 { return "flow reading is a few hours old" }
        return "flow reading is \(Fmt.days(age)) old"
    }
}
