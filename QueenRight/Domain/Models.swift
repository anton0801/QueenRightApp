//
//  Models.swift
//  QueenRight
//
//  The record (§7). Frame content is stored as COVERAGE FRACTIONS rather than raw cell
//  counts, because coverage is literally what the beekeeper paints in Frame Capture and
//  it stays correct if the apiary's frame type is ever corrected. Cells — the unit the
//  whole model and interface speak in — are derived through `HiveSystem`.
//

import Foundation
import CoreGraphics

enum IDs {
    static func new() -> String {
        UUID().uuidString.lowercased()
    }
}

// MARK: - Small shared helpers

extension String {
    /// Имена ульев и пасек люди набирают с лишними пробелами по краям — а
    /// «Улей 1 » и «Улей 1» не должны быть двумя разными записями.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Frame

enum BoxKind: String, Codable, CaseIterable {
    case brood
    case superBox

    var displayName: String { self == .brood ? "Brood box" : "Super" }
    var shortName: String { self == .brood ? "Brood" : "Super" }
}

struct Frame: Identifiable, Codable, Equatable, Hashable {
    var id: String = IDs.new()
    /// 0 = bare foundation, 1 = fully drawn comb. Undrawn comb holds nothing.
    var drawnFraction: Double = 1
    /// Fraction of the frame's comb carrying capped worker brood.
    var sealedBroodFraction: Double = 0
    /// Fraction carrying eggs and open larvae.
    var openBroodFraction: Double = 0
    /// Fraction carrying honey and pollen. Stores block laying.
    var storesFraction: Double = 0
    var lastCapturedAt: Date?

    /// A frame the beekeeper has never measured — drawn comb, contents unknown.
    static func drawn() -> Frame { Frame() }
    /// Bare foundation: no comb yet, so no cells at all.
    static func foundation() -> Frame { Frame(drawnFraction: 0) }

    // MARK: Derived cell counts

    func capacity(system: HiveSystem, kind: BoxKind) -> Double {
        Double(system.cellsPerFrame(for: kind)) * drawnFraction.clamped(to: 0...1)
    }

    func sealedBroodCells(system: HiveSystem, kind: BoxKind) -> Double {
        capacity(system: system, kind: kind) * sealedBroodFraction.clamped(to: 0...1)
    }

    func openBroodCells(system: HiveSystem, kind: BoxKind) -> Double {
        capacity(system: system, kind: kind) * openBroodFraction.clamped(to: 0...1)
    }

    func broodCells(system: HiveSystem, kind: BoxKind) -> Double {
        sealedBroodCells(system: system, kind: kind) + openBroodCells(system: system, kind: kind)
    }

    /// Cells the queen could lay in: drawn comb, minus what stores already occupy.
    /// Brood already present is subtracted later, at colony level.
    func layingCapacity(system: HiveSystem, kind: BoxKind) -> Double {
        capacity(system: system, kind: kind) * (1 - storesFraction.clamped(to: 0...1))
    }

    /// How this frame draws on the board.
    var appearance: FrameAppearance {
        if drawnFraction < 0.15 { return .foundation }
        if sealedBroodFraction + openBroodFraction > 0.08 { return .brood }
        if storesFraction > 0.35 { return .stores }
        return .drawn
    }
}

enum FrameAppearance {
    case foundation, drawn, stores, brood

    var label: String {
        switch self {
        case .foundation: return "Foundation"
        case .drawn: return "Drawn comb"
        case .stores: return "Stores"
        case .brood: return "Brood"
        }
    }
}

// MARK: - Box

struct Box: Identifiable, Codable, Equatable, Hashable {
    var id: String = IDs.new()
    var kind: BoxKind
    var frames: [Frame]

    static func brood(system: HiveSystem, drawn: Int, foundation: Int = 0) -> Box {
        var f = (0..<drawn).map { _ in Frame.drawn() }
        f.append(contentsOf: (0..<foundation).map { _ in Frame.foundation() })
        return Box(kind: .brood, frames: f)
    }

    static func superBox(system: HiveSystem, drawn: Int, foundation: Int = 0) -> Box {
        var f = (0..<drawn).map { _ in Frame.drawn() }
        f.append(contentsOf: (0..<foundation).map { _ in Frame.foundation() })
        return Box(kind: .superBox, frames: f)
    }
}

// MARK: - Queen

enum QueenMark: String, Codable, CaseIterable, Identifiable {
    case white, yellow, red, green, blue, unmarked
    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    /// The international marking colour for a year (years ending 1/6 white, 2/7 yellow,
    /// 3/8 red, 4/9 green, 5/0 blue).
    static func forYear(_ year: Int) -> QueenMark {
        switch year % 10 {
        case 1, 6: return .white
        case 2, 7: return .yellow
        case 3, 8: return .red
        case 4, 9: return .green
        default: return .blue
        }
    }
}

/// One measurement of this colony's laying rate, taken from a capture session (§2.7).
struct LayRateEstimate: Codable, Equatable, Hashable {
    var date: Date
    var eggsPerDay: Double
    /// False when the session did not cover enough of the brood box to be representative.
    /// Low-confidence estimates are recorded and shown, but never feed `queenPotential`.
    var isRepresentative: Bool
}

struct Queen: Codable, Equatable, Hashable {
    var introducedYear: Int
    var markColour: QueenMark
    var estimateHistory: [LayRateEstimate] = []

    var ageYears: Int {
        max(0, Calendar.current.component(.year, from: Date()) - introducedYear)
    }

    /// Book figure for a queen of this age, used until the colony has been measured.
    var bookPotential: Double { Population.potential(forQueenAgeYears: ageYears) }

    /// What the app has actually learned about THIS queen, or nil if not enough
    /// representative captures yet.
    var learnedLayRate: Double? {
        LayRateLearner.learnedRate(from: estimateHistory)
    }

    /// The figure the simulation runs on.
    var effectivePotential: Double { learnedLayRate ?? bookPotential }
}

// MARK: - Queen cells (§2.4 — these override everything)

enum QueenCellStage: String, Codable, CaseIterable, Identifiable {
    /// A play cup is not an intention. Starts no clock.
    case cup
    /// An egg or a small larva in the cup.
    case charged
    /// Sealed. The prime swarm issues at or just before this.
    case capped

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cup: return "Cup"
        case .charged: return "Charged"
        case .capped: return "Capped"
        }
    }

    var detail: String {
        switch self {
        case .cup: return "Empty play cup — no egg in it"
        case .charged: return "An egg or a larva in royal jelly"
        case .capped: return "Sealed over"
        }
    }
}

/// Cell age read off the contents, used to place a charged cell on the 8-day clock.
enum CellAgeEstimate: String, Codable, CaseIterable, Identifiable {
    case egg          // day 0–3
    case smallLarva   // day 3–5
    case largeLarva   // day 5–8
    case unsure       // take the earliest and say the window is wide

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .egg: return "An egg"
        case .smallLarva: return "Small larva in jelly"
        case .largeLarva: return "Large larva"
        case .unsure: return "Couldn't tell"
        }
    }

    /// Days of development already elapsed. `unsure` takes the earliest (§2.4).
    var daysElapsed: Double {
        switch self {
        case .egg: return 1.5
        case .smallLarva: return 4
        case .largeLarva: return 6.5
        case .unsure: return 0
        }
    }

    /// How much slop to put either side of the resulting window.
    var uncertaintyDays: Double {
        switch self {
        case .egg, .smallLarva, .largeLarva: return 2
        case .unsure: return 4
        }
    }
}

enum CellPosition: String, Codable, CaseIterable, Identifiable {
    /// Hanging off the bottom bars — the classic swarm position.
    case bottomBar
    /// On the face of the comb — usually supersedure.
    case face

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bottomBar: return "Along the bottom bars"
        case .face: return "On the face of the comb"
        }
    }
}

struct QueenCellObservation: Identifiable, Codable, Equatable, Hashable {
    var id: String = IDs.new()
    var date: Date
    var stage: QueenCellStage
    var ageEstimate: CellAgeEstimate = .unsure
    var count: Int = 1
    var position: CellPosition = .bottomBar

    /// Swarm cells versus supersedure cells are told apart by count and position (§2 edge
    /// cases). A few cells on the comb face with a laying queen present is supersedure,
    /// and supersedure starts no swarm clock.
    var looksLikeSupersedure: Bool {
        position == .face && count <= 3
    }
}

// MARK: - Swarm history (§10.7 — a model you cannot audit is one you should not trust)

/// What the model said BEFORE a colony swarmed, kept so the projection can be audited.
struct ArchivedProjection: Identifiable, Codable, Equatable, Hashable {
    var id: String = IDs.new()
    var recordedAt: Date
    var stateWord: String
    var windowStart: Date?
    var windowEnd: Date?
    var note: String
}

struct SwarmEvent: Identifiable, Codable, Equatable, Hashable {
    var id: String = IDs.new()
    var date: Date
    /// The projection that was on screen before it happened.
    var priorProjection: ArchivedProjection?
    /// Capped cells left behind keep a cast-swarm warning alive.
    var cappedCellsRemaining: Int = 0
}

// MARK: - Hive

struct Hive: Identifiable, Codable, Equatable, Hashable {
    var id: String = IDs.new()
    var name: String
    var boxes: [Box]
    var queen: Queen
    /// Where the hive stands in the yard plan, normalised 0…1.
    var positionX: Double = 0.5
    var positionY: Double = 0.5
    var lastInspection: Date
    var cellObservations: [QueenCellObservation] = []
    /// Set when cells were cut. Cutting NEVER clears risk (§10.3).
    var cellsCutAt: Date?
    /// Set by a split or a swarm — the colony has no laying queen from this date.
    var queenlessSince: Date?
    var swarmEvents: [SwarmEvent] = []
    var archivedProjections: [ArchivedProjection] = []
    var createdAt: Date = Date()

    var broodBoxes: [Box] { boxes.filter { $0.kind == .brood } }
    var supers: [Box] { boxes.filter { $0.kind == .superBox } }

    func daysSinceInspection(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: lastInspection)
        let b = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: a, to: b).day ?? 0)
    }

    /// Cell observations still worth trusting — anything older than a full queen cycle
    /// has either swarmed or emerged, so it no longer describes the colony.
    func liveCellObservations(now: Date = Date()) -> [QueenCellObservation] {
        cellObservations.filter { obs in
            let age = now.timeIntervalSince(obs.date) / 86_400
            return age >= -1 && age <= Double(BroodCycle.queenEmerges)
        }
    }
}

// MARK: - Apiary

struct Apiary: Identifiable, Codable, Equatable {
    var id: String = IDs.new()
    var name: String
    var latitude: Double
    var longitude: Double
    var system: HiveSystem
    var hives: [Hive] = []
    var memberUIDs: [String] = []
    var inviteCode: String?
    var createdAt: Date = Date()

    /// The southern hemisphere runs the season half a year out of phase.
    var isSouthernHemisphere: Bool { latitude < 0 }
}

// MARK: - Weather (§13)

struct WeatherDay: Codable, Equatable, Hashable {
    var date: Date
    var tmeanC: Double
    var rainMm: Double
    var windMS: Double

    /// A flying day for foragers (§2.5).
    var isFlowDay: Bool {
        tmeanC >= Forage.minMeanTempC
            && rainMm < Forage.maxRainMm
            && windMS < Forage.maxWindMS
    }
}

/// A day's weather keyed for fast lookup during the simulation.
struct WeatherSeries: Equatable {
    var byDay: [Date: WeatherDay]
    /// When this series was fetched — drives the "flow reading is n days old" line.
    var fetchedAt: Date?

    init(days: [WeatherDay] = [], fetchedAt: Date? = nil, calendar: Calendar = .current) {
        var map: [Date: WeatherDay] = [:]
        for d in days { map[calendar.startOfDay(for: d.date)] = d }
        self.byDay = map
        self.fetchedAt = fetchedAt
    }

    func day(_ date: Date, calendar: Calendar = .current) -> WeatherDay? {
        byDay[calendar.startOfDay(for: date)]
    }

    var isEmpty: Bool { byDay.isEmpty }

    /// Past 48 hours the reading is stated as stale and the flowResumption term is
    /// suspended rather than guessed (§13).
    func isStale(now: Date = Date()) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) / 3600 > Forage.readingStaleAfterHours
    }

    func ageInDays(now: Date = Date()) -> Int? {
        guard let fetchedAt else { return nil }
        return max(0, Int(now.timeIntervalSince(fetchedAt) / 86_400))
    }

    /// Flow days out of the last seven, for the apiary-wide FlowLine.
    func recentFlowDays(endingAt end: Date, calendar: Calendar = .current) -> (flow: Int, total: Int) {
        var flow = 0, total = 0
        for back in 0..<Forage.flowWindowDays {
            guard let d = calendar.date(byAdding: .day, value: -back, to: end),
                  let w = day(d, calendar: calendar) else { continue }
            total += 1
            if w.isFlowDay { flow += 1 }
        }
        return (flow, total)
    }
}
