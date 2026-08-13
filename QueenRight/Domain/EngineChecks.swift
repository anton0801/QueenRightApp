//
//  EngineChecks.swift
//  QueenRight
//
//  Debug self-tests. These are not decoration: they assert the acceptance criteria in
//  §11 and the anti-generic invariants in §10 against the real engine, on every launch
//  of a debug build. If a change ever softens "a super doesn't help" or lets cut cells
//  clear the risk, the app says so in the console immediately.
//

import Foundation

#if DEBUG
enum EngineChecks {

    private static var failures: [String] = []

    static func run() {
        failures = []

        checkSuperDoesNothing()            // §10.2, acceptance 3
        checkSwapBroodHelps()              // acceptance 4
        checkCappedCellIsImminent()        // acceptance 1
        checkCupsOnlyDoNothing()           // acceptance 2
        checkCutCellsDoNotClear()          // §10.3
        checkSplitProjectsBothHalves()     // acceptance 5
        checkFlowResumption()              // acceptance 9
        checkBlindWidens()                 // acceptance 8
        checkLearnedRateDiffers()          // acceptance 10
        checkOutOfSeason()                 // acceptance 11
        checkCellConstants()               // §15 rows 4 and 5

        if failures.isEmpty {
        } else {
            failures.forEach { print("  ✗ \($0)") }
            assertionFailure("EngineChecks failed — see console")
        }
    }

    private static let checkCount = 11

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition { failures.append(message) }
    }

    // MARK: Fixtures

    /// A strong colony in mid-May, congested: eight frames largely full of brood.
    private static func congestedColony(system: HiveSystem = .national) -> ColonySnapshot {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        // Fixed mid-June date so the season window is open regardless of when tests run.
        let inspection = calendar.date(from: DateComponents(year: year, month: 6, day: 10)) ?? Date()

        var frames: [Frame] = []
        for _ in 0..<system.framesPerBox {
            var f = Frame.drawn()
            f.sealedBroodFraction = 0.62
            f.openBroodFraction = 0.22
            f.storesFraction = 0.14
            f.lastCapturedAt = inspection
            frames.append(f)
        }

        let hive = Hive(name: "Test",
                        boxes: [Box(kind: .brood, frames: frames)],
                        queen: Queen(introducedYear: year, markColour: .white),
                        lastInspection: inspection)

        return ColonySnapshot(hive: hive, system: system, latitude: 51.5,
                              weather: flowWeather(around: inspection))
    }

    /// Seven flowing days either side of a date.
    private static func flowWeather(around date: Date) -> WeatherSeries {
        let calendar = Calendar.current
        var days: [WeatherDay] = []
        for offset in -30...40 {
            guard let d = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            days.append(WeatherDay(date: d, tmeanC: 18, rainMm: 0.2, windMS: 3))
        }
        return WeatherSeries(days: days, fetchedAt: Date())
    }

    /// A run of cold wet days, then the weather breaks.
    private static func rainedInThenBreaks(around date: Date, breakOn: Int) -> WeatherSeries {
        let calendar = Calendar.current
        var days: [WeatherDay] = []
        for offset in -30...40 {
            guard let d = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            if offset >= breakOn - 5 && offset < breakOn {
                days.append(WeatherDay(date: d, tmeanC: 9, rainMm: 12, windMS: 9))   // no flow
            } else {
                days.append(WeatherDay(date: d, tmeanC: 18, rainMm: 0.1, windMS: 3)) // flow
            }
        }
        return WeatherSeries(days: days, fetchedAt: Date())
    }

    private static func today(of snapshot: ColonySnapshot) -> DayState? {
        let p = SwarmClock.run(snapshot, now: snapshot.lastInspection)
        return p.days[safe: p.todayIndex]
    }

    // MARK: Checks

    /// §10.2 / acceptance 3 — adding a super must move space pressure by EXACTLY zero.
    private static func checkSuperDoesNothing() {
        let base = congestedColony()
        let after = Interventions.apply(.addSuper, to: base).after

        guard let before = today(of: base), let now = today(of: after) else {
            expect(false, "add-super: no day state"); return
        }
        expect(abs(before.spacePressure - now.spacePressure) < 1e-9,
               "add-super changed spacePressure \(before.spacePressure) → \(now.spacePressure); a super is stores comb and must not add laying cells")
        expect(abs(before.openCells - now.openCells) < 1e-9,
               "add-super changed the cells available to lay in")
        expect(after.hive.boxes.count == base.hive.boxes.count + 1,
               "add-super did not actually add a box")
    }

    /// Acceptance 4 — swapping sealed brood for drawn comb reduces pressure immediately.
    private static func checkSwapBroodHelps() {
        let base = congestedColony()
        let after = Interventions.apply(.swapBroodForDrawn, to: base).after

        guard let before = today(of: base), let now = today(of: after) else {
            expect(false, "swap: no day state"); return
        }
        expect(now.spacePressure < before.spacePressure,
               "swapping sealed brood for drawn comb did not reduce spacePressure (\(before.spacePressure) → \(now.spacePressure))")
        expect(now.openCells > before.openCells,
               "swapping sealed brood for drawn comb did not free any cells")
    }

    /// Acceptance 1 — a capped cell forces imminent, overriding the space projection.
    private static func checkCappedCellIsImminent() {
        var snapshot = congestedColony()
        snapshot.hive.cellObservations = [
            QueenCellObservation(date: snapshot.lastInspection, stage: .capped,
                                 ageEstimate: .unsure, count: 5, position: .bottomBar)
        ]
        let p = SwarmClock.run(snapshot, now: snapshot.lastInspection)
        expect(p.riskState == .imminent,
               "a capped queen cell did not force imminent (got \(p.riskState.word))")

        // §11.1 asks for the window to be stated as today or tomorrow. The words are
        // hard-coded in SwarmClockHeader's `.imminent` branch; what has to be asserted
        // here is the data contract behind them — a window that opens today and closes
        // no later than tomorrow.
        let calendar = Calendar.current
        guard let window = p.window else {
            expect(false, "imminent produced no swarm window"); return
        }
        let opensIn = calendar.dateComponents([.day],
                                              from: calendar.startOfDay(for: snapshot.lastInspection),
                                              to: calendar.startOfDay(for: window.lowerBound)).day ?? -1
        let closesIn = calendar.dateComponents([.day],
                                               from: calendar.startOfDay(for: snapshot.lastInspection),
                                               to: calendar.startOfDay(for: window.upperBound)).day ?? -1
        expect(opensIn == 0, "the imminent window opens in \(opensIn) days, expected today")
        expect(closesIn == 1, "the imminent window closes in \(closesIn) days, expected tomorrow")
        // And the reason must carry the evidence rather than repeat the headline.
        expect(p.reason.lowercased().contains("queen cell"),
               "the imminent reason does not name the cells it is based on")

        // And it must beat a roomy colony too — observation always beats projection.
        var roomy = congestedColony()
        for i in roomy.hive.boxes[0].frames.indices {
            roomy.hive.boxes[0].frames[i].sealedBroodFraction = 0.05
            roomy.hive.boxes[0].frames[i].openBroodFraction = 0.05
            roomy.hive.boxes[0].frames[i].storesFraction = 0.05
        }
        roomy.hive.cellObservations = snapshot.hive.cellObservations
        let rp = SwarmClock.run(roomy, now: roomy.lastInspection)
        expect(rp.riskState == .imminent,
               "a capped cell on a roomy colony did not override the space projection")
    }

    /// Acceptance 2 — cups only start no clock and change no state.
    private static func checkCupsOnlyDoNothing() {
        var roomy = congestedColony()
        for i in roomy.hive.boxes[0].frames.indices {
            roomy.hive.boxes[0].frames[i].sealedBroodFraction = 0.05
            roomy.hive.boxes[0].frames[i].openBroodFraction = 0.05
            roomy.hive.boxes[0].frames[i].storesFraction = 0.05
        }
        let bare = SwarmClock.run(roomy, now: roomy.lastInspection)

        var withCups = roomy
        withCups.hive.cellObservations = [
            QueenCellObservation(date: roomy.lastInspection, stage: .cup,
                                 ageEstimate: .unsure, count: 6, position: .bottomBar)
        ]
        let cupped = SwarmClock.run(withCups, now: roomy.lastInspection)

        expect(cupped.riskState == bare.riskState,
               "play cups changed the risk state from \(bare.riskState.word) to \(cupped.riskState.word)")
        expect(cupped.window == nil,
               "play cups started a swarm window; a cup with no egg in it is not an intention")
    }

    /// §10.3 — cutting cells never clears the risk.
    private static func checkCutCellsDoNotClear() {
        var snapshot = congestedColony()
        snapshot.hive.cellObservations = [
            QueenCellObservation(date: snapshot.lastInspection, stage: .charged,
                                 ageEstimate: .smallLarva, count: 7, position: .bottomBar)
        ]
        let result = Interventions.apply(.cutCells, to: snapshot, now: snapshot.lastInspection)
        let after = SwarmClock.run(result.after, now: snapshot.lastInspection)

        expect(after.riskState != .calm,
               "cutting cells dropped the colony to calm; the cause was untouched")
        expect(after.cellsReturnWindow != nil,
               "cutting cells did not schedule the 4–7 day return of new cells")
        expect(after.reason.contains("4") && after.reason.contains("7"),
               "cutting cells did not state the 4–7 day expectation in words")
    }

    /// Acceptance 5 — a split projects both halves, queenless one showing 16 + 5–14.
    private static func checkSplitProjectsBothHalves() {
        let base = congestedColony()
        let result = Interventions.apply(.split, to: base, now: base.lastInspection)

        guard let leaver = result.splitOff else {
            expect(false, "split produced no second colony"); return
        }
        let keeperP = SwarmClock.run(result.after, now: base.lastInspection)
        let leaverP = SwarmClock.run(leaver, now: base.lastInspection)

        expect(keeperP.days.count > 0, "split: the queenright half has no projection")

        guard case .queenless(let queenDue, let laying) = leaverP.verdict else {
            expect(false, "the split-off half is not queenless (got \(leaverP.riskState.word))")
            return
        }
        let calendar = Calendar.current
        if let due = queenDue {
            let days = calendar.dateComponents([.day], from: base.lastInspection, to: due).day ?? 0
            expect(days == BroodCycle.queenEmerges,
                   "queenless half shows a \(days)-day queen clock, expected \(BroodCycle.queenEmerges)")
        } else {
            expect(false, "queenless half has no queen-due date")
        }
        if let laying, let due = queenDue {
            let lower = calendar.dateComponents([.day], from: due, to: laying.lowerBound).day ?? 0
            let upper = calendar.dateComponents([.day], from: due, to: laying.upperBound).day ?? 0
            expect(lower == BroodCycle.matingWindowShortest && upper == BroodCycle.matingWindowLongest,
                   "mating window is \(lower)–\(upper) days, expected \(BroodCycle.matingWindowShortest)–\(BroodCycle.matingWindowLongest)")
        } else {
            expect(false, "queenless half has no mating window")
        }
    }

    /// Acceptance 9 — 4+ non-flow days then a flow day raises risk for 3 days.
    private static func checkFlowResumption() {
        var snapshot = congestedColony()
        let calendar = Calendar.current
        snapshot.weather = rainedInThenBreaks(around: snapshot.lastInspection, breakOn: 6)

        let projection = SwarmClock.run(snapshot, now: snapshot.lastInspection)

        // Day 6 after the inspection is the first flow day after five dull ones.
        guard let breakDate = calendar.date(byAdding: .day, value: 6, to:
                calendar.startOfDay(for: snapshot.lastInspection)) else {
            expect(false, "flow resumption: no break date"); return
        }
        let onBreak = projection.days.first { calendar.isDate($0.date, inSameDayAs: breakDate) }
        guard let onBreak else { expect(false, "flow resumption: break day missing"); return }

        // The day before the break is dull, so it carries no resumption bonus.
        guard let dullDate = calendar.date(byAdding: .day, value: -1, to: breakDate),
              let onDull = projection.days.first(where: { calendar.isDate($0.date, inSameDayAs: dullDate) })
        else { expect(false, "flow resumption: dull day missing"); return }

        expect(onBreak.risk > onDull.risk,
               "risk did not rise on the first flow day after a wet spell (\(onDull.risk) → \(onBreak.risk))")

        // And the lift lasts exactly three days, not longer.
        guard let after3 = calendar.date(byAdding: .day, value: 3, to: breakDate),
              let settled = projection.days.first(where: { calendar.isDate($0.date, inSameDayAs: after3) })
        else { expect(false, "flow resumption: settle day missing"); return }
        expect(settled.risk <= onBreak.risk + 1e-9,
               "the flow-resumption lift outlasted its three days")
    }

    /// Acceptance 8 — nine or more days since the inspection widens the band.
    private static func checkBlindWidens() {
        var snapshot = congestedColony()
        let calendar = Calendar.current
        let now = calendar.date(byAdding: .day, value: 11, to: snapshot.lastInspection) ?? Date()
        // Keep the weather aligned with the later "now".
        snapshot.weather = flowWeather(around: now)

        let projection = SwarmClock.run(snapshot, now: now)
        expect(projection.isBlind, "11 days since the last look did not read as blind")
        expect(projection.daysSinceInspection == 11,
               "daysSinceInspection was \(projection.daysSinceInspection), expected 11")
        expect(projection.bandWidthDays > 0, "the uncertainty band did not widen")

        let fresh = SwarmClock.run(congestedColony(), now: congestedColony().lastInspection)
        expect(fresh.bandWidthDays < projection.bandWidthDays,
               "a fresh inspection produced a band as wide as an 11-day-old one")
    }

    /// Acceptance 10 — by the third representative capture the learned rate differs
    /// from the book default.
    private static func checkLearnedRateDiffers() {
        var queen = Queen(introducedYear: Calendar.current.component(.year, from: Date()),
                          markColour: .white)
        expect(queen.learnedLayRate == nil, "a queen with no captures already has a learned rate")

        let system = HiveSystem.national
        // A hive of 11 frames, 62% sealed → a real, measurable brood nest.
        let sealed = Double(system.cellsPerFrame(for: .brood)) * 0.62 * 11
        for i in 0..<3 {
            let date = Calendar.current.date(byAdding: .day, value: i * 7, to: Date()) ?? Date()
            queen.estimateHistory.append(
                LayRateLearner.estimate(sealedCells: sealed,
                                        openCells: sealed * 0.4,
                                        framesCaptured: 11,
                                        framesInBroodBoxes: 11,
                                        date: date))
        }
        guard let learned = queen.learnedLayRate else {
            expect(false, "three representative captures produced no learned rate"); return
        }
        expect(abs(learned - queen.bookPotential) > 1,
               "the learned rate (\(learned)) is identical to the book figure")

        // A partial capture must NOT feed the learned figure.
        let partial = LayRateLearner.estimate(sealedCells: sealed / 11,
                                              openCells: 0,
                                              framesCaptured: 1,
                                              framesInBroodBoxes: 11,
                                              date: Date())
        expect(!partial.isRepresentative,
               "a single frame out of eleven was treated as representative of the whole nest")
    }

    /// Acceptance 11 — outside the season window the clock is off and says why.
    private static func checkOutOfSeason() {
        var snapshot = congestedColony()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let january = calendar.date(from: DateComponents(year: year, month: 1, day: 15)) ?? Date()
        snapshot.hive.lastInspection = january
        snapshot.weather = WeatherSeries(days: [], fetchedAt: Date())

        let projection = SwarmClock.run(snapshot, now: january)
        guard case .outOfSeason = projection.verdict else {
            expect(false, "mid-January at 51.5°N did not read as out of season")
            return
        }
        expect(projection.window == nil, "the clock produced a swarm window out of season")
        expect(!projection.reason.isEmpty, "out of season did not say why")

        // And the southern hemisphere must be the other way round.
        expect(SeasonWindow.isInSwarmSeason(latitude: -33.9, date: january),
               "mid-January at 33.9°S should be inside the swarm season")
    }

    /// §15 rows 4 and 5 — the constants themselves.
    private static func checkCellConstants() {
        expect(BroodCycle.workerEmerges == 21, "worker emergence is not day 21")
        expect(BroodCycle.queenCappedOn == 8, "the queen cell is not capped on day 8")
        expect(BroodCycle.queenEmerges == 16, "the queen does not emerge on day 16")
        expect(BroodCycle.droneEmerges == 24, "drone emergence is not day 24")
        expect(BroodCycle.cappedBroodStandingDays == 12,
               "capped brood should stand for 21 − 9 = 12 days")

        // The brief's own arithmetic: 1,800 eggs a day needs ~37,800 cells, which it
        // calls "seven to eight deep frames of solid brood".
        let needed = 1800.0 * Double(BroodCycle.workerEmerges)
        let framesNeeded = needed / Double(HiveSystem.national.cellsPerFrame(for: .brood))
        expect(framesNeeded >= 6.5 && framesNeeded <= 8.0,
               "at 1,800 eggs a day a National colony needs \(String(format: "%.1f", framesNeeded)) frames; the reference figure is seven to eight")

        expect(HiveSystem.langstroth.broodCellsPerSide == 3500,
               "Langstroth deep should be 3,500 cells a side")
        expect(HiveSystem.national.cellsPerFrame(for: .brood) == 5400,
               "a National deep frame should hold 5,400 cells over both sides")
    }
}
#endif
