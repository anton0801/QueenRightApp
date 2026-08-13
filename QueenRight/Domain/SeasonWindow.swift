//
//  SeasonWindow.swift
//  QueenRight
//
//  `fSeason` from daylight hours at the apiary's latitude (§2.3), plus the hard season
//  window that switches the clock off in winter (§2 edge cases, acceptance 11).
//  Daylight comes from the standard solar-declination formula — no dependency, and it
//  handles the southern hemisphere by the sign of the latitude for free.
//

import Foundation

enum SeasonWindow {

    /// Hours of daylight at `latitude` on the given date.
    static func daylightHours(latitude: Double, date: Date, calendar: Calendar = .current) -> Double {
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 172)

        // Solar declination, radians (Cooper's equation).
        let declination = 0.409105 * sin(2 * .pi * (284 + day) / 365)
        let phi = latitude * .pi / 180

        // Hour angle at sunrise. Clamps handle polar day and polar night.
        let cosH = -tan(phi) * tan(declination)
        if cosH <= -1 { return 24 }   // sun never sets
        if cosH >= 1 { return 0 }     // sun never rises
        let h = acos(cosH)
        return 24 * h / .pi
    }

    /// Seasonal multiplier on the queen's laying rate, 0…1.
    /// Maps 9 hours of daylight (deep winter) to nothing and 16 hours to full rate,
    /// with a smooth ramp so build-up and shutdown are gradual rather than stepped.
    static func fSeason(latitude: Double, date: Date, calendar: Calendar = .current) -> Double {
        let hours = daylightHours(latitude: latitude, date: date, calendar: calendar)
        let t = ((hours - 9.0) / (16.0 - 9.0)).clamped(to: 0...1)
        // Smoothstep — no hard corners at either end of the season.
        return t * t * (3 - 2 * t)
    }

    /// Is this date inside the part of the year colonies actually swarm in?
    /// Swarming needs both drones and a build-up, which in practice means long days.
    /// Below this threshold the clock is off and the apiary says why (acceptance 11).
    static let swarmSeasonDaylightHours = 13.0

    static func isInSwarmSeason(latitude: Double, date: Date, calendar: Calendar = .current) -> Bool {
        daylightHours(latitude: latitude, date: date, calendar: calendar) >= swarmSeasonDaylightHours
    }

    /// Are we past the point in the year where bees raised now are winter bees?
    /// Week 34 in the northern hemisphere, and the mirrored date in the southern.
    static func isRaisingWinterBees(latitude: Double, date: Date, calendar: Calendar = .current) -> Bool {
        // Winter bees are raised as daylight falls away after the peak, so express it
        // as "daylight is short AND shortening" rather than a fixed calendar week.
        let today = daylightHours(latitude: latitude, date: date, calendar: calendar)
        guard let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: date) else { return false }
        let before = daylightHours(latitude: latitude, date: twoWeeksAgo, calendar: calendar)
        return today < before && today < 14.0
    }

    /// The next date the swarm season opens, so the out-of-season copy can name a month.
    static func nextSeasonOpens(latitude: Double, from date: Date, calendar: Calendar = .current) -> Date? {
        var probe = date
        for _ in 0..<400 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: probe) else { return nil }
            probe = next
            if isInSwarmSeason(latitude: latitude, date: probe, calendar: calendar) {
                return probe
            }
        }
        return nil
    }

    /// "Back in April" — the month the clock restarts.
    static func nextSeasonMonthName(latitude: Double, from date: Date, calendar: Calendar = .current) -> String? {
        guard let opens = nextSeasonOpens(latitude: latitude, from: date, calendar: calendar) else { return nil }
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMMM")
        return f.string(from: opens)
    }
}
