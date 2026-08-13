//
//  SwarmClock.swift
//  QueenRight
//
//  THE SIGNATURE FEATURE (§2). A day-stepped projection of one colony — population,
//  laying space, queen cells — resolving into a dated swarm window, re-run the moment
//  anything on the board changes.
//
//  This type is PURE and deterministic: no I/O, no `Date()` read inside the walk, no
//  side effects. That is what lets the Actions sheet run it twice — once on the colony
//  as it stands and once on the colony with an action applied — and draw both on one
//  axis (§5.4), and it is what makes the debug self-tests in EngineChecks meaningful.
//

import Foundation

// MARK: - Input

struct ColonySnapshot: Equatable {
    var hive: Hive
    var system: HiveSystem
    var latitude: Double
    var weather: WeatherSeries

    var lastInspection: Date { hive.lastInspection }
}

// MARK: - Output

struct DayState: Equatable, Identifiable {
    var id: Date { date }
    var date: Date
    var adults: Double
    var eggsLaid: Double
    var openBroodCells: Double
    var sealedBroodCells: Double
    /// Cells the queen has left to lay in.
    var openCells: Double
    var layingCapacity: Double
    var spacePressure: Double
    var risk: Double
    var isFlowDay: Bool
    /// Weather was known for this day rather than carried forward.
    var weatherKnown: Bool
}

/// Why the clock says what it says. Every state carries its words (§10.5).
enum ClockVerdict: Equatable {
    /// Nothing to do.
    case calm
    /// Cells charged, or the projection says congestion is coming.
    case watch(cellBuildingDate: Date?)
    /// Cells capped, or a charged cell's 8-day clock has nearly run.
    case imminent
    /// Queenless — a split or a swarm. Its own clock, not a swarm clock.
    case queenless(queenDue: Date?, layingResumes: ClosedRange<Date>?)
    /// Outside the season window the clock is off.
    case outOfSeason(returnsIn: String?)

    var riskState: RiskState {
        switch self {
        case .calm, .outOfSeason: return .calm
        case .watch: return .watch
        case .imminent: return .imminent
        case .queenless: return .calm
        }
    }

    /// True when the verdict rests on something the beekeeper actually saw rather than
    /// on the simulation. An observation stays trustworthy however long ago it was made,
    /// so it is never overwritten by the "running blind" copy.
    var isObservationBacked: Bool {
        switch self {
        case .imminent, .queenless, .outOfSeason: return true
        case .calm, .watch: return false
        }
    }
}

struct SwarmProjection: Equatable {
    var days: [DayState]
    /// Index into `days` for today.
    var todayIndex: Int
    var verdict: ClockVerdict
    /// The dated window the swarm is expected in, if there is one.
    var window: ClosedRange<Date>?
    /// Half-width of the uncertainty band in days — widens as the last look recedes.
    var bandWidthDays: Double
    /// Days since the beekeeper last had the hive open.
    var daysSinceInspection: Int
    /// The sentence shown under the header.
    var reason: String
    /// True when the projection is a guess with the confidence of a guess (§5.2).
    var isBlind: Bool
    /// Set when cells were cut and the cause was left untouched (§10.3).
    var cellsReturnWindow: ClosedRange<Date>?
    /// A cast-swarm warning after a recorded swarm left capped cells behind.
    var castWarningUntil: Date?
    /// The flow reading's age, when it is too old to use (§13).
    var suspendedFlowTermAgeDays: Int?

    var today: DayState? {
        days.indices.contains(todayIndex) ? days[todayIndex] : days.last
    }

    var riskState: RiskState { verdict.riskState }

    /// The word on the chip. A queenless colony is not "calm" in any sense a beekeeper
    /// would recognise — it has no swarm clock because it has no queen, which is a
    /// different statement and has to read as one.
    var chipLabel: String {
        switch verdict {
        case .queenless: return "QUEENLESS"
        case .outOfSeason: return "CLOCK OFF"
        case .calm, .watch, .imminent: return riskState.word
        }
    }

    /// Days from today until the window opens, or nil when there is no window.
    func daysUntilWindow(calendar: Calendar = .current) -> Int? {
        guard let window, let today = today else { return nil }
        let a = calendar.startOfDay(for: today.date)
        let b = calendar.startOfDay(for: window.lowerBound)
        return max(0, calendar.dateComponents([.day], from: a, to: b).day ?? 0)
    }
}

// MARK: - The engine

enum SwarmClock {

    /// How far past today the board can be scrubbed.
    static let projectionDays = 30

    static func run(_ snapshot: ColonySnapshot,
                    now: Date = Date(),
                    calendar: Calendar = .current) -> SwarmProjection {

        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: min(snapshot.lastInspection, today))
        let daysBack = max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
        let totalDays = daysBack + projectionDays + 1

        let system = snapshot.system
        let hive = snapshot.hive

        // ── Laying capacity: BROOD BOXES ONLY. A super is stores comb, never laying
        // cells — this single line is what makes "add a super" visibly fail to fix
        // congestion (§10.2, acceptance 3).
        let layingCapacity = hive.broodBoxes.reduce(0.0) { total, box in
            total + box.frames.reduce(0.0) { $0 + $1.layingCapacity(system: system, kind: box.kind) }
        }

        // Total brood-box comb, for the congestion term.
        let broodComb = hive.broodBoxes.reduce(0.0) { total, box in
            total + box.frames.reduce(0.0) { $0 + $1.capacity(system: system, kind: box.kind) }
        }

        // ── Measured starting brood.
        var measuredSealed = 0.0
        var measuredOpen = 0.0
        for box in hive.broodBoxes {
            for f in box.frames {
                measuredSealed += f.sealedBroodCells(system: system, kind: box.kind)
                measuredOpen += f.openBroodCells(system: system, kind: box.kind)
            }
        }

        let potential = hive.queen.effectivePotential

        // ── Seed 21 days of egg history so the walk opens consistent with what was
        // counted. Without this the first three weeks would show a phantom brood gap.
        var eggHistory = [Double](repeating: 0, count: BroodCycle.workerEmerges + 2)
        // Clamped to a physical ceiling: painted coverage is an estimate, and a generous
        // one across a whole brood box can imply a laying rate no queen achieves.
        let sealedRate = (measuredSealed / Double(BroodCycle.cappedBroodStandingDays))
            .clamped(to: 0...Population.maxLayRate)
        let openRate = (measuredOpen / Double(BroodCycle.openBroodStandingDays))
            .clamped(to: 0...Population.maxLayRate)
        for age in 0..<eggHistory.count {
            // age 0…9 is open brood, 9…21 is capped brood.
            eggHistory[age] = age < BroodCycle.workerCappedOn ? openRate : sealedRate
        }
        // With no measurement at all, fall back to the queen's potential so a brand-new
        // hive still projects something honest rather than an empty colony.
        if measuredSealed == 0 && measuredOpen == 0 {
            for age in 0..<eggHistory.count { eggHistory[age] = potential * 0.5 }
        }

        // Steady-state adult population implied by those cohorts.
        var adults = (eggHistory[BroodCycle.workerEmerges] * Population.broodSurvival)
            * Population.lifespanInFlow
        adults = adults.clamped(to: 3_000...Population.maxAdults)

        // ── Queenless colonies lay nothing until the new queen is mated (§2.8 split).
        let queenlessSince = hive.queenlessSince

        var days: [DayState] = []
        days.reserveCapacity(totalDays)

        var flowRunNonFlow = 0
        var resumptionHoldRemaining = 0
        let weatherStale = snapshot.weather.isStale(now: now)

        for offset in 0..<totalDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { break }

            // Forage.
            let known = snapshot.weather.day(date, calendar: calendar)
            let flowDays = flowDayCount(ending: date, weather: snapshot.weather, calendar: calendar)
            let fFlow = Forage.flowFloor + Forage.flowSpan * flowDays.fraction
            let isFlow = known?.isFlowDay ?? (flowDays.fraction > 0.5)

            // Flow resumption: a flow day after ≥4 non-flow days raises risk for 3 days.
            // Suspended rather than guessed when the reading is too old (§13).
            if !weatherStale {
                if isFlow {
                    if flowRunNonFlow >= Forage.resumptionAfterNonFlowDays {
                        resumptionHoldRemaining = Forage.resumptionHoldsDays
                    }
                    flowRunNonFlow = 0
                } else {
                    flowRunNonFlow += 1
                }
            }
            let flowResumptionTerm = (!weatherStale && resumptionHoldRemaining > 0) ? 1.0 : 0.0
            if resumptionHoldRemaining > 0 { resumptionHoldRemaining -= 1 }

            // Season.
            let fSeason = SeasonWindow.fSeason(latitude: snapshot.latitude, date: date, calendar: calendar)
            let inSeason = SeasonWindow.isInSwarmSeason(latitude: snapshot.latitude, date: date, calendar: calendar)

            // Brood standing right now, from the egg history.
            let openBrood = (0..<BroodCycle.workerCappedOn).reduce(0.0) { $0 + eggHistory[$1] }
            let sealedBrood = (BroodCycle.workerCappedOn..<BroodCycle.workerEmerges)
                .reduce(0.0) { $0 + eggHistory[$1] }

            let occupied = openBrood + sealedBrood
            let openCells = max(0, layingCapacity - occupied)

            // Laying.
            let isQueenless = queenlessSince.map { date >= calendar.startOfDay(for: $0) } ?? false
            let layRate = isQueenless ? 0 : potential * fSeason * fFlow
            let eggsLaid = min(layRate, openCells)

            // Space pressure — every cell laid stays occupied 21 days.
            let cellsNeeded = max(1, layRate * Double(BroodCycle.workerEmerges))
            let spacePressure = (1 - openCells / cellsNeeded).clamped(to: 0...1)

            // Risk.
            let congestion = broodComb > 0 ? (sealedBrood / broodComb).clamped(to: 0...1) : 0
            let strength = (adults / Population.fullStrengthAdults).clamped(to: 0...1)
            let seasonTerm = inSeason ? 1.0 : 0.0
            let risk = RiskWeights.spacePressure * spacePressure
                + RiskWeights.broodCongestion * congestion
                + RiskWeights.colonyStrength * strength
                + RiskWeights.seasonWindow * seasonTerm
                + RiskWeights.flowResumption * flowResumptionTerm

            days.append(DayState(date: date,
                                 adults: adults,
                                 eggsLaid: eggsLaid,
                                 openBroodCells: openBrood,
                                 sealedBroodCells: sealedBrood,
                                 openCells: openCells,
                                 layingCapacity: layingCapacity,
                                 spacePressure: spacePressure,
                                 risk: risk,
                                 isFlowDay: isFlow,
                                 weatherKnown: known != nil))

            // ── Step the colony one day.
            let emerging = eggHistory[BroodCycle.workerEmerges] * Population.broodSurvival
            let lifespan = lifespanFor(date: date,
                                       latitude: snapshot.latitude,
                                       isFlow: isFlow,
                                       calendar: calendar)
            adults = (adults + emerging - adults / lifespan)
                .clamped(to: 0...Population.maxAdults)

            // Age every cohort by one day and lay today's eggs into age 0.
            eggHistory.removeLast()
            eggHistory.insert(eggsLaid, at: 0)
        }

        let todayIndex = min(daysBack, max(0, days.count - 1))
        let daysSince = hive.daysSinceInspection(now: now, calendar: calendar)
        let isBlind = daysSince >= Confidence.blindAfterDays
        let band = Double(daysSince) * Confidence.bandWideningPerDay

        // ── Resolve the verdict. Observation always beats projection (§2.4).
        let resolved = resolveVerdict(snapshot: snapshot,
                                      days: days,
                                      todayIndex: todayIndex,
                                      now: today,
                                      calendar: calendar)

        // A projection nobody has checked in over a week is a guess, and it has to say
        // so in the same breath as its conclusion — otherwise "nothing pressing" reads
        // as reassurance the model has not earned (§5.2, acceptance 8).
        var reason = resolved.reason
        if isBlind, !resolved.verdict.isObservationBacked {
            reason = "\(daysSince) days since you looked — this is a guess with the confidence of a guess."
        }

        return SwarmProjection(
            days: days,
            todayIndex: todayIndex,
            verdict: resolved.verdict,
            window: resolved.window,
            bandWidthDays: band,
            daysSinceInspection: daysSince,
            reason: reason,
            isBlind: isBlind,
            cellsReturnWindow: resolved.cellsReturn,
            castWarningUntil: resolved.castWarning,
            suspendedFlowTermAgeDays: weatherStale ? snapshot.weather.ageInDays(now: now) : nil
        )
    }

    // MARK: - Verdict

    private struct Resolved {
        var verdict: ClockVerdict
        var window: ClosedRange<Date>?
        var reason: String
        var cellsReturn: ClosedRange<Date>?
        var castWarning: Date?
    }

    private static func resolveVerdict(snapshot: ColonySnapshot,
                                       days: [DayState],
                                       todayIndex: Int,
                                       now: Date,
                                       calendar: Calendar) -> Resolved {
        let hive = snapshot.hive

        // Cast-swarm warning: capped cells left after a recorded swarm (§2 edge cases).
        var castWarning: Date?
        if let last = hive.swarmEvents.sorted(by: { $0.date > $1.date }).first,
           last.cappedCellsRemaining > 0,
           let until = calendar.date(byAdding: .day,
                                     value: BroodCycle.castSwarmWarningDays,
                                     to: calendar.startOfDay(for: last.date)),
           until >= now {
            castWarning = until
        }

        // Cut cells return in 4–7 days if the cause is untouched — cutting NEVER
        // clears the risk state (§10.3, acceptance 2).
        var cellsReturn: ClosedRange<Date>?
        if let cut = hive.cellsCutAt,
           let soonest = calendar.date(byAdding: .day, value: BroodCycle.cellsRebuiltSoonest,
                                       to: calendar.startOfDay(for: cut)),
           let latest = calendar.date(byAdding: .day, value: BroodCycle.cellsRebuiltLatest,
                                      to: calendar.startOfDay(for: cut)),
           latest >= now {
            cellsReturn = soonest...latest
        }

        // ── Queenless: its own clock (§2.8, acceptance 5).
        if let since = hive.queenlessSince {
            let base = calendar.startOfDay(for: since)
            let queenDue = calendar.date(byAdding: .day, value: BroodCycle.queenEmerges, to: base)
            var layingResumes: ClosedRange<Date>?
            if let due = queenDue,
               let earliest = calendar.date(byAdding: .day, value: BroodCycle.matingWindowShortest, to: due),
               let latest = calendar.date(byAdding: .day, value: BroodCycle.matingWindowLongest, to: due) {
                layingResumes = earliest...latest
            }
            let reason: String
            if let due = queenDue, due >= now {
                let n = calendar.dateComponents([.day], from: now, to: due).day ?? 0
                reason = "Queenless. A new queen should emerge in \(Fmt.days(max(0, n)))."
            } else if let r = layingResumes {
                reason = "Queenless. A virgin has emerged — laying should resume \(Fmt.window(r))."
            } else {
                reason = "Queenless."
            }
            return Resolved(verdict: .queenless(queenDue: queenDue, layingResumes: layingResumes),
                            window: nil, reason: reason,
                            cellsReturn: cellsReturn, castWarning: castWarning)
        }

        // ── Out of season: the clock is off and the app says why (acceptance 11).
        if !SeasonWindow.isInSwarmSeason(latitude: snapshot.latitude, date: now, calendar: calendar) {
            let month = SeasonWindow.nextSeasonMonthName(latitude: snapshot.latitude,
                                                         from: now, calendar: calendar)
            let reason = month.map { "Swarm season is over here. Back in \($0)." }
                ?? "Swarm season is over here."
            return Resolved(verdict: .outOfSeason(returnsIn: month), window: nil, reason: reason,
                            cellsReturn: cellsReturn, castWarning: castWarning)
        }

        // ── Observed queen cells override the projection entirely (§2.4).
        let live = hive.liveCellObservations(now: now)
        let swarmCells = live.filter { !$0.looksLikeSupersedure && $0.stage != .cup }

        if let capped = swarmCells.filter({ $0.stage == .capped })
            .sorted(by: { $0.date < $1.date }).first {
            // A prime swarm leaves at or just before the first cell is sealed.
            let seen = calendar.startOfDay(for: capped.date)
            let end = calendar.date(byAdding: .day, value: 1, to: max(seen, now)) ?? now
            let window = max(seen, now)...end
            // The headline already says "today or tomorrow"; this line carries the
            // evidence behind it rather than repeating the conclusion.
            let daysAgo = calendar.dateComponents([.day], from: seen, to: now).day ?? 0
            let when = daysAgo == 0 ? "today" : (daysAgo == 1 ? "yesterday" : "\(daysAgo) days ago")
            let count = capped.count
            let where_ = capped.position == .bottomBar ? "along the bottom bars" : "on the comb face"
            return Resolved(verdict: .imminent, window: window,
                            reason: "\(count) sealed queen cell\(count == 1 ? "" : "s") \(where_), seen \(when). Space will not fix this now.",
                            cellsReturn: cellsReturn, castWarning: castWarning)
        }

        if let charged = swarmCells.filter({ $0.stage == .charged })
            .sorted(by: { $0.date < $1.date }).first {
            // window = seen + (8 − ageEstimate) ± uncertainty
            let seen = calendar.startOfDay(for: charged.date)
            let daysToCapping = Double(BroodCycle.queenCappedOn) - charged.ageEstimate.daysElapsed
            let slop = charged.ageEstimate.uncertaintyDays
            let lowerOffset = Int((daysToCapping - slop).rounded())
            let upperOffset = Int((daysToCapping + slop).rounded())
            guard let rawLower = calendar.date(byAdding: .day, value: lowerOffset, to: seen),
                  let rawUpper = calendar.date(byAdding: .day, value: upperOffset, to: seen) else {
                return Resolved(verdict: .watch(cellBuildingDate: nil), window: nil,
                                reason: "Charged queen cells seen.",
                                cellsReturn: cellsReturn, castWarning: castWarning)
            }
            let lower = max(rawLower, now)
            let upper = max(rawUpper, lower)

            // Once the capping date is upon us, this is imminent, not watch.
            if lower <= now {
                return Resolved(verdict: .imminent, window: lower...upper,
                                reason: "Charged queen cells are due to be sealed. Treat this as today or tomorrow.",
                                cellsReturn: cellsReturn, castWarning: castWarning)
            }
            let wide = charged.ageEstimate == .unsure
            let reason = wide
                ? "Charged queen cells, age uncertain — so the window is wide."
                : "Charged queen cells. Sealing is what starts the swarm."
            return Resolved(verdict: .watch(cellBuildingDate: nil), window: lower...upper,
                            reason: reason, cellsReturn: cellsReturn, castWarning: castWarning)
        }

        // Cups only start no clock and change no state (§2.4, acceptance 2).
        let cupsOnly = !live.isEmpty && live.allSatisfy { $0.stage == .cup }
        let supersedureOnly = !live.isEmpty && live.allSatisfy { $0.looksLikeSupersedure }

        // ── No cells: fall back to the projection.
        // The projected cell-building date is the first simulated day where
        // spacePressure ≥ 0.75 inside the season window; the swarm window is that
        // date + 8 to 10 days (§2.6).
        var cellBuilding: Date?
        for day in days where day.date >= now {
            if day.spacePressure >= RiskWeights.congestedSpacePressure,
               SeasonWindow.isInSwarmSeason(latitude: snapshot.latitude,
                                            date: day.date, calendar: calendar) {
                cellBuilding = day.date
                break
            }
        }

        let todayRisk = days.indices.contains(todayIndex) ? days[todayIndex].risk : 0

        if let building = cellBuilding, todayRisk >= RiskWeights.watchThreshold {
            let lower = calendar.date(byAdding: .day,
                                      value: RiskWeights.cellBuildingToSwarmShortest, to: building)
            let upper = calendar.date(byAdding: .day,
                                      value: RiskWeights.cellBuildingToSwarmLongest, to: building)
            let window: ClosedRange<Date>? = (lower != nil && upper != nil) ? lower!...upper! : nil
            var reason = "Running out of laying room around \(Fmt.day(building)). Cells usually follow."
            if cellsReturn != nil {
                reason = "Cells were cut, and the cause is untouched. Expect new cells within 4–7 days."
            }
            return Resolved(verdict: .watch(cellBuildingDate: building), window: window,
                            reason: reason, cellsReturn: cellsReturn, castWarning: castWarning)
        }

        // Cut cells hold the colony at watch even when the numbers have eased (§10.3).
        if cellsReturn != nil {
            return Resolved(verdict: .watch(cellBuildingDate: cellBuilding), window: nil,
                            reason: "Cells were cut. Nothing else changed. Expect new cells within 4–7 days.",
                            cellsReturn: cellsReturn, castWarning: castWarning)
        }

        if castWarning != nil {
            return Resolved(verdict: .watch(cellBuildingDate: nil), window: nil,
                            reason: "This colony swarmed, and capped cells were left behind. Casts can follow.",
                            cellsReturn: cellsReturn, castWarning: castWarning)
        }

        if cupsOnly {
            return Resolved(verdict: .calm, window: nil,
                            reason: "Play cups only. A cup with no egg in it is not an intention.",
                            cellsReturn: nil, castWarning: castWarning)
        }
        if supersedureOnly {
            return Resolved(verdict: .calm, window: nil,
                            reason: "These look like supersedure cells — few, on the face of the comb. No swarm clock.",
                            cellsReturn: nil, castWarning: castWarning)
        }

        let today = days.indices.contains(todayIndex) ? days[todayIndex] : nil
        let room = today.map { Int($0.openCells) } ?? 0
        return Resolved(verdict: .calm, window: nil,
                        reason: "Room to lay: \(Fmt.cells(room)) cells. Nothing pressing.",
                        cellsReturn: nil, castWarning: castWarning)
    }

    // MARK: - Helpers

    /// Flow days in the seven days ending on `date`. When the weather series does not
    /// cover a day, that day is left out of the denominator rather than guessed.
    private static func flowDayCount(ending date: Date,
                                     weather: WeatherSeries,
                                     calendar: Calendar) -> (flow: Int, known: Int, fraction: Double) {
        var flow = 0, known = 0
        for back in 0..<Forage.flowWindowDays {
            guard let d = calendar.date(byAdding: .day, value: -back, to: date) else { continue }
            guard let w = weather.day(d, calendar: calendar) else { continue }
            known += 1
            if w.isFlowDay { flow += 1 }
        }
        // With no forage data at all the term sits at a neutral mid-season value —
        // the clock still runs on brood and space (§13).
        guard known > 0 else { return (0, 0, 0.5) }
        return (flow, known, Double(flow) / Double(known))
    }

    private static func lifespanFor(date: Date,
                                    latitude: Double,
                                    isFlow: Bool,
                                    calendar: Calendar) -> Double {
        if SeasonWindow.isRaisingWinterBees(latitude: latitude, date: date, calendar: calendar) {
            return Population.lifespanWinterBee
        }
        return isFlow ? Population.lifespanInFlow : Population.lifespanInDearth
    }
}
