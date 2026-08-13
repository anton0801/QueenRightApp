//
//  LayRateLearner.swift
//  QueenRight
//
//  The colony learns (§2.7). Each capture session yields a measured brood area, and
//  a measured brood area IS a laying rate: capped brood stands for 12 days, so
//  `layRate ≈ sealedCells / 12`. By the third session the projection runs on THIS
//  colony's queen rather than a textbook average — which is what makes the account
//  worth having (§14).
//
//  IMPORTANT: the divisor applies to the WHOLE hive's sealed brood in one session,
//  never a single frame. One frame of a seven-frame brood nest would under-read the
//  queen by roughly seven times. Sessions that did not cover enough of the brood box
//  are still recorded and shown, but flagged and excluded from the learned figure.
//

import Foundation

enum LayRateLearner {

    /// A session must have measured at least this share of the brood box's frames
    /// before its estimate is treated as representative of the whole nest.
    static let representativeFrameCoverage = 0.6

    /// Turn one session's measured brood into an eggs-per-day estimate.
    static func estimate(sealedCells: Double,
                         openCells: Double,
                         framesCaptured: Int,
                         framesInBroodBoxes: Int,
                         date: Date) -> LayRateEstimate {
        // Two independent readings of the same rate; the sealed figure is the steadier
        // of the two because 12 days of laying stand in it at once.
        let fromSealed = sealedCells / Double(BroodCycle.cappedBroodStandingDays)
        let fromOpen = openCells / Double(BroodCycle.openBroodStandingDays)

        let rate: Double
        if sealedCells > 0 && openCells > 0 {
            rate = fromSealed * 0.75 + fromOpen * 0.25
        } else if sealedCells > 0 {
            rate = fromSealed
        } else {
            rate = fromOpen
        }

        let coverage = framesInBroodBoxes > 0
            ? Double(framesCaptured) / Double(framesInBroodBoxes)
            : 0
        return LayRateEstimate(date: date,
                               eggsPerDay: max(0, rate),
                               isRepresentative: coverage >= representativeFrameCoverage)
    }

    /// Weighted mean of the last four representative estimates, most recent heaviest
    /// (weights 4/3/2/1). Returns nil until there is something worth trusting.
    static func learnedRate(from history: [LayRateEstimate]) -> Double? {
        let usable = history
            .filter { $0.isRepresentative && $0.eggsPerDay > 0 }
            .sorted { $0.date < $1.date }
            .suffix(4)

        guard !usable.isEmpty else { return nil }

        var weightedSum = 0.0
        var weightTotal = 0.0
        // Most recent gets the largest weight.
        for (offset, estimate) in usable.enumerated() {
            let weight = Double(offset + 1)
            weightedSum += estimate.eggsPerDay * weight
            weightTotal += weight
        }
        guard weightTotal > 0 else { return nil }

        // A queen laying outside these bounds is a measurement error, not a queen.
        return (weightedSum / weightTotal).clamped(to: 200...3500)
    }

    /// How the learned rate compares to the book figure, for Settings → QUEENS.
    /// e.g. "laying about 1,940 a day — above the book".
    static func comparison(learned: Double, book: Double) -> String {
        let delta = learned - book
        let margin = book * 0.05
        if abs(delta) <= margin { return "about the book figure" }
        return delta > 0 ? "above the book" : "below the book"
    }
}
