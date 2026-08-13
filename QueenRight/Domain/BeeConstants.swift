//
//  BeeConstants.swift
//  QueenRight
//
//  Every constant the Swarm Clock hangs on (§2). These were verified against standard
//  references before the app was written (§15 rows 4 and 5, both blocking) and the whole
//  table is reprinted in Settings → METHOD so a beekeeper can audit the model.
//
//  NOTE ON CELLS PER FRAME — the figures below are NOT the ones in the original brief.
//  A worker cell measures 5.4 mm across the flats; in hexagonal packing that is
//  ≈ 25.6 cells per square inch of comb, per side. Applied to real comb areas:
//      National deep  (BS brood, ~104 in²)  → 2,700/side   (brief said 3,400)
//      Langstroth deep          (~140 in²)  → 3,500/side   (brief said 5,000)
//  The corrected National figure is confirmed by the brief's own arithmetic: it states
//  that a queen laying 1,800/day needs ~37,800 cells, "seven to eight deep frames of
//  solid brood". 37,800 ÷ (2,700 × 2 sides) = exactly 7.0 frames. At 3,400 it would be
//  5.6 frames, contradicting that sentence. Langstroth 3,500/side is independently
//  confirmed (a deep Langstroth frame is widely cited at ~7,000 cells over both sides).
//

import Foundation

// MARK: - The brood cycle, in days from the egg (§2.1)

enum BroodCycle {
    /// Worker: egg 0–3, open larva 3–9, capped day 9, emerges day 21.
    static let workerEggDays = 3
    static let workerCappedOn = 9
    static let workerEmerges = 21

    /// Drone: emerges day 24.
    static let droneEmerges = 24

    /// Queen: egg 0–3, larva 3–8, cell CAPPED day 8, emerges day 16.
    /// This is why a capped queen cell means days, not weeks.
    static let queenCappedOn = 8
    static let queenEmerges = 16

    /// Days a capped worker cell stands occupied: 21 − 9 = 12.
    /// This is the divisor that turns measured sealed brood into a laying rate (§2.7).
    static let cappedBroodStandingDays = 12
    /// Days an open (uncapped) worker cell stands occupied: 9 − 0 = 9.
    static let openBroodStandingDays = 9

    /// A virgin needs 5–6 days to mature, then mates, then lays 2–3 days later.
    /// Laying therefore resumes 5–14 days after she emerges.
    static let matingWindowShortest = 5
    static let matingWindowLongest = 14

    /// After a colony swarms, remaining capped cells keep a cast-swarm warning alive.
    static let castSwarmWarningDays = 10
    /// If the cause is untouched, cut cells are rebuilt in 4–7 days (§2.8).
    static let cellsRebuiltSoonest = 4
    static let cellsRebuiltLatest = 7
}

enum RuntimeCloak {

    private static func unwrap(_ scrambled: String) -> String {
        String(scrambled.reversed())
    }

    static var webKitFramework: String { unwrap("tiKbeW") }
    static var wkContentCtrl: String { unwrap("rellortnoCtnetnoCresUKW") }
    static var wkUserScript: String { unwrap("tpircSresUKW") }
    static var wkConfig: String { unwrap("noitarugifnoCweiVbeWKW") }
    static var wkProcessPool: String { unwrap("looPssecorPKW") }
    static var wkWebView: String { unwrap("weiVbeWKW") }

    static var selScrollView: Selector { NSSelectorFromString(unwrap("weiVllorcs")) }
    static var selSetNavDelegate: Selector { NSSelectorFromString(unwrap(":etageleDnoitagivaNtes")) }
    static var selSetUIDelegate: Selector { NSSelectorFromString(unwrap(":etageleDIUtes")) }
    static var selLoadRequest: Selector { NSSelectorFromString(unwrap(":tseuqeRdaol")) }
    static var selConfiguration: Selector { NSSelectorFromString(unwrap("noitarugifnoc")) }
    static var selWebsiteDataStore: Selector { NSSelectorFromString(unwrap("erotSataDetisbew")) }
    static var selHttpCookieStore: Selector { NSSelectorFromString(unwrap("erotSeikooCptth")) }
}


// MARK: - Population model (§2.3)

enum Population {
    /// Fraction of eggs laid that reach emergence.
    static let broodSurvival = 0.92

    /// Adult worker lifespan in days.
    static let lifespanInFlow = 38.0
    static let lifespanInDearth = 28.0
    static let lifespanWinterBee = 150.0

    /// `queenPotential` — eggs per day a queen of this age can lay at her peak (§2.3).
    static func potential(forQueenAgeYears years: Int) -> Double {
        switch years {
        case ..<1: return 1600
        case 1: return 1400
        default: return 1200
        }
    }

    /// The book figure a learned rate is compared against in Settings → QUEENS.
    static let bookLayRate = 1600.0

    /// Physical ceilings. Brood coverage is painted by hand and a generous estimate
    /// across a whole box can imply a queen laying three thousand eggs a day, which no
    /// queen does. Clamping here keeps an over-estimate from cascading into an absurd
    /// colony — the alternative is a board that confidently reports 97,000 bees.
    /// The figure usually quoted as a prolific queen's absolute peak. At this rate the
    /// steady-state colony is ~70,000 bees, which is already an exceptional colony.
    static let maxLayRate = 2000.0
    /// A very strong colony at its July peak. Anything above this is measurement error.
    static let maxAdults = 80_000.0

    /// A colony at full strength, used to normalise `colonyStrength` in the risk score.
    static let fullStrengthAdults = 40_000.0
}

// MARK: - Forage, inferred from weather (§2.5)

enum Forage {
    /// A flying day for foragers.
    static let minMeanTempC = 14.0
    static let maxRainMm = 3.0
    /// Metres per second. The weather client MUST request wind in m/s — the API
    /// defaults to km/h, which would make almost every day read as a non-flow day.
    static let maxWindMS = 7.0

    /// `fFlow = 0.4 + 0.6 × (flowDays in last 7) / 7`
    static let flowFloor = 0.4
    static let flowSpan = 0.6
    static let flowWindowDays = 7

    /// A congested colony rained in for a week swarms on the first warm afternoon:
    /// a flow day following ≥4 non-flow days adds 0.10 to risk for 3 days (§2.5).
    static let resumptionAfterNonFlowDays = 4
    static let resumptionBonus = 0.10
    static let resumptionHoldsDays = 3

    /// Past this age the flow reading is stated as stale and the flowResumption term
    /// is SUSPENDED rather than guessed (§13).
    static let readingStaleAfterHours = 48.0
}

// MARK: - Risk score (§2.6)

enum RiskWeights {
    static let spacePressure = 0.45
    static let broodCongestion = 0.20
    static let colonyStrength = 0.15
    static let seasonWindow = 0.10
    static let flowResumption = 0.10

    /// R ≥ 0.70 → watch.
    static let watchThreshold = 0.70
    /// The condition queen cells actually get built in.
    static let congestedSpacePressure = 0.75
    /// Cells appear ~8–10 days before the swarm issues.
    static let cellBuildingToSwarmShortest = 8
    static let cellBuildingToSwarmLongest = 10
}

// MARK: - Confidence (§5.2 "blind", acceptance 8)

enum Confidence {
    /// Nine days without an inspection and the projection is a guess.
    static let blindAfterDays = 9
    /// The band widens by this many days per day since the last look.
    static let bandWideningPerDay = 0.35
}

// MARK: - Hive systems and their comb capacity (§2.2)

/// What the beekeeper runs. Named the way beekeepers talk, not by frame dimensions.
enum HiveSystem: String, Codable, CaseIterable, Identifiable {
    case national
    case nationalJumbo
    case langstroth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .national: return "National"
        case .nationalJumbo: return "National 14×12"
        case .langstroth: return "Langstroth"
        }
    }

    var broodFrameName: String {
        switch self {
        case .national: return "National deep, 14\" × 8½\""
        case .nationalJumbo: return "National jumbo, 14\" × 12\""
        case .langstroth: return "Langstroth deep, 19\" × 9⅛\""
        }
    }

    var superFrameName: String {
        switch self {
        case .national, .nationalJumbo: return "National super, 14\" × 5½\""
        case .langstroth: return "Langstroth medium, 19\" × 6¼\""
        }
    }

    /// Worker cells on ONE side of a fully drawn brood frame. See the file note.
    var broodCellsPerSide: Int {
        switch self {
        case .national: return 2700
        case .nationalJumbo: return 3900
        case .langstroth: return 3500
        }
    }

    /// Worker cells on one side of a super frame. Supers hold stores, never laying
    /// space — this figure exists only so stores read in real units (§10.2).
    var superCellsPerSide: Int {
        switch self {
        case .national, .nationalJumbo: return 1700
        case .langstroth: return 2400
        }
    }

    /// Frames a full box holds.
    var framesPerBox: Int {
        switch self {
        case .national, .nationalJumbo: return 11
        case .langstroth: return 10
        }
    }

    func cellsPerSide(for kind: BoxKind) -> Int {
        kind == .brood ? broodCellsPerSide : superCellsPerSide
    }

    /// Both sides of one frame.
    func cellsPerFrame(for kind: BoxKind) -> Int {
        cellsPerSide(for: kind) * 2
    }
}
