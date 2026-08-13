//
//  OpenMeteoClient.swift
//  QueenRight
//
//  Open-Meteo, zero dependencies (§13). Three things matter here and were verified
//  against the live API before this file was written:
//
//   1. `wind_speed_unit=ms` is MANDATORY. The API defaults to km/h and the flow rule
//      thresholds at 7 m/s — without this every day would read as a non-flow day and
//      the forage term would silently die.
//   2. `past_days=92` on the FORECAST endpoint covers the 60 days of history the model
//      needs in a single call, avoiding the archive's ~5-day publication lag entirely.
//      The archive is only used to backfill gaps older than 92 days.
//   3. `temperature_2m_mean`, `precipitation_sum` and `wind_speed_10m_mean` are all
//      available on both endpoints.
//
//  Paid tier: set `apiKey` and every host gains the `customer-` prefix plus `&apikey=`.
//  Attribution is shown in Settings → METHOD either way.
//

import Foundation

enum WeatherError: Error, Equatable {
    case offline
    case http(Int)
    case decode
    case noCoordinates
    case other(String)

    /// What the user is told. Offline with a cache says nothing at all (§13).
    var message: String {
        switch self {
        case .offline:
            return "No forage data yet for this site. The clock still runs on brood and space."
        case .noCoordinates:
            return "This apiary has no location yet."
        case .http, .decode, .other:
            return "Couldn't reach the forage service. The clock still runs on brood and space."
        }
    }
}

struct GeoResult: Identifiable, Equatable, Hashable {
    var id: Int
    var name: String
    var country: String?
    var admin1: String?
    var latitude: Double
    var longitude: Double

    var subtitle: String {
        [admin1, country].compactMap { $0 }.joined(separator: ", ")
    }
}

actor OpenMeteoClient {
    static let shared = OpenMeteoClient()

    /// Set to switch to the paid commercial tier. Nil uses the free hosts.
    /// Do not hard-code a real key here — read it from a gitignored source.
    private let apiKey: String? = nil

    static let attributionName = "Open-Meteo"
    static let attributionURL = "https://open-meteo.com"
    static let licenceNote = "Weather by Open-Meteo. The free tier is for non-commercial use; a commercial key can be set in the client."

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    private func host(_ base: String) -> String {
        apiKey == nil ? base : "customer-\(base)"
    }

    private func withKey(_ items: [URLQueryItem]) -> [URLQueryItem] {
        guard let apiKey else { return items }
        return items + [URLQueryItem(name: "apikey", value: apiKey)]
    }

    // MARK: - Daily weather

    /// The single call that feeds the model: 92 days back and 7 forward.
    func recentDaily(latitude: Double, longitude: Double) async throws -> [WeatherDay] {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host("api.open-meteo.com")
        comps.path = "/v1/forecast"
        comps.queryItems = withKey([
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "daily", value: "temperature_2m_mean,precipitation_sum,wind_speed_10m_mean"),
            .init(name: "past_days", value: "92"),
            .init(name: "forecast_days", value: "7"),
            // Without this the API answers in km/h and the flow rule breaks.
            .init(name: "wind_speed_unit", value: "ms"),
            .init(name: "timezone", value: "auto")
        ])
        return try await fetchDaily(comps)
    }

    /// Backfill for a season older than the forecast endpoint's 92-day reach.
    func archiveDaily(latitude: Double, longitude: Double,
                      start: Date, end: Date) async throws -> [WeatherDay] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host("archive-api.open-meteo.com")
        comps.path = "/v1/archive"
        comps.queryItems = withKey([
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "start_date", value: f.string(from: start)),
            .init(name: "end_date", value: f.string(from: end)),
            .init(name: "daily", value: "temperature_2m_mean,precipitation_sum,wind_speed_10m_mean"),
            .init(name: "wind_speed_unit", value: "ms"),
            .init(name: "timezone", value: "auto")
        ])
        return try await fetchDaily(comps)
    }

    private func fetchDaily(_ comps: URLComponents) async throws -> [WeatherDay] {
        guard let url = comps.url else { throw WeatherError.other("bad url") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let err as URLError where err.code == .notConnectedToInternet
                    || err.code == .networkConnectionLost
                    || err.code == .dataNotAllowed
                    || err.code == .timedOut {
            throw WeatherError.offline
        } catch {
            throw WeatherError.other(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherError.http(http.statusCode)
        }

        guard let dto = try? JSONDecoder().decode(DailyResponse.self, from: data) else {
            throw WeatherError.decode
        }
        return dto.weatherDays()
    }

    // MARK: - Place search (§5.5 — search by name is always available)

    func search(name: String) async throws -> [GeoResult] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host("geocoding-api.open-meteo.com")
        comps.path = "/v1/search"
        comps.queryItems = withKey([
            .init(name: "name", value: trimmed),
            .init(name: "count", value: "8"),
            .init(name: "language", value: "en"),
            .init(name: "format", value: "json")
        ])

        guard let url = comps.url else { return [] }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw WeatherError.http(http.statusCode)
            }
            let dto = try JSONDecoder().decode(GeoResponse.self, from: data)
            return (dto.results ?? []).map {
                GeoResult(id: $0.id, name: $0.name, country: $0.country,
                          admin1: $0.admin1, latitude: $0.latitude, longitude: $0.longitude)
            }
        } catch let err as URLError where err.code == .notConnectedToInternet {
            throw WeatherError.offline
        }
    }
}

// MARK: - DTOs

private struct DailyResponse: Decodable {
    struct Daily: Decodable {
        let time: [String]
        let temperature_2m_mean: [Double?]?
        let precipitation_sum: [Double?]?
        let wind_speed_10m_mean: [Double?]?
    }
    let utc_offset_seconds: Int?
    let daily: Daily?

    /// Open-Meteo returns naive local dates; anchor them to the location's own offset
    /// so a day boundary at the apiary is the same day boundary the model steps on.
    func weatherDays() -> [WeatherDay] {
        guard let daily else { return [] }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: utc_offset_seconds ?? 0)

        var out: [WeatherDay] = []
        out.reserveCapacity(daily.time.count)
        for (i, stamp) in daily.time.enumerated() {
            guard let date = f.date(from: stamp) else { continue }
            let t = daily.temperature_2m_mean?[safe: i].flatMap { $0 }
            let r = daily.precipitation_sum?[safe: i].flatMap { $0 }
            let w = daily.wind_speed_10m_mean?[safe: i].flatMap { $0 }
            // A day missing its temperature cannot be judged, so it is skipped rather
            // than defaulted — the model treats unknown days as unknown.
            guard let t else { continue }
            out.append(WeatherDay(date: date, tmeanC: t, rainMm: r ?? 0, windMS: w ?? 0))
        }
        return out
    }
}

private struct GeoResponse: Decodable {
    struct Result: Decodable {
        let id: Int
        let name: String
        let country: String?
        let admin1: String?
        let latitude: Double
        let longitude: Double
    }
    let results: [Result]?
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
