//
//  Interventions.swift
//  QueenRight
//
//  The five things a beekeeper can actually do (§2.8), applied from today forward and
//  never retroactively. Each returns a new snapshot, so the Actions sheet runs the
//  engine twice and draws both futures on one axis (§5.4).
//
//  The central honesty of this app lives here:
//   • Adding a super adds STORES comb, not laying cells, so `spacePressure` does not
//     move by a single point (§10.2, acceptance 3). This is the misconception the app
//     exists to correct and it must not be softened.
//   • Cutting cells does NOT clear risk (§10.3, acceptance 2).
//

import Foundation

enum Intervention: String, CaseIterable, Identifiable {
    case addSuper
    case addBroodBox
    case swapBroodForDrawn
    case split
    case cutCells

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addSuper: return "Add a super"
        case .addBroodBox: return "Add a brood box"
        case .swapBroodForDrawn: return "Swap sealed brood for drawn comb"
        case .split: return "Split the colony"
        case .cutCells: return "Cut the cells"
        }
    }

    var subtitle: String {
        switch self {
        case .addSuper:
            return "Somewhere to put honey"
        case .addBroodBox:
            return "A whole box of new laying cells"
        case .swapBroodForDrawn:
            return "The fastest legitimate relief"
        case .split:
            return "Take the swarm before it takes itself"
        case .cutCells:
            return "Buys days, not a solution"
        }
    }

    /// The sentence shown in the sheet once the action is previewed.
    var explanation: String {
        switch self {
        case .addSuper:
            return """
                A super is stores comb. It gives the colony somewhere to put honey and \
                does almost nothing about where the queen lays, so the swarm clock \
                barely moves. This is the most common mistake in swarm control.
                """
        case .addBroodBox:
            return """
                A second brood box is real laying space. Drawn frames work immediately; \
                foundation has to be built out first, which takes a strong colony and a flow.
                """
        case .swapBroodForDrawn:
            return """
                Sealed brood comes out, drawn comb goes in. The queen gets empty cells \
                today, and the bees in the frames you removed still emerge. This is the \
                fastest honest relief there is.
                """
        case .split:
            return """
                The colony reproduces on your terms instead of its own. Both halves are \
                projected below: the queenright half carries on, and the queenless half \
                runs a 16-day queen clock plus a 5–14 day mating window before laying resumes.
                """
        case .cutCells:
            return """
                Cells cut. Nothing else changed. Expect new cells within 4–7 days.
                """
        }
    }

    /// Ordering in the tray. When a colony is imminent the split comes first (§5.2).
    static func trayOrder(for state: RiskState) -> [Intervention] {
        switch state {
        case .imminent:
            return [.split, .swapBroodForDrawn, .addBroodBox, .cutCells, .addSuper]
        case .watch:
            return [.swapBroodForDrawn, .addBroodBox, .split, .addSuper, .cutCells]
        case .calm:
            return [.addSuper, .addBroodBox, .swapBroodForDrawn, .split, .cutCells]
        }
    }
}

// MARK: - Applying an action

struct InterventionResult {
    /// The colony as it would stand after the action.
    var after: ColonySnapshot
    /// For a split, the new colony that leaves with the other half.
    var splitOff: ColonySnapshot?
    /// Empty when the action can be performed.
    var blockedReason: String?

    var isApplicable: Bool { blockedReason == nil }
}

enum Interventions {

    /// How many frames of sealed brood a swap moves out.
    static let swapFrameCount = 2

    static func apply(_ action: Intervention,
                      to snapshot: ColonySnapshot,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> InterventionResult {
        switch action {
        case .addSuper:       return addSuper(snapshot)
        case .addBroodBox:    return addBroodBox(snapshot)
        case .swapBroodForDrawn: return swapBroodForDrawn(snapshot)
        case .split:          return split(snapshot, now: now, calendar: calendar)
        case .cutCells:       return cutCells(snapshot, now: now, calendar: calendar)
        }
    }

    // MARK: Add a super — must move spacePressure by exactly zero

    private static func addSuper(_ s: ColonySnapshot) -> InterventionResult {
        var after = s
        // Drawn comb, but it is a SUPER, and supers are excluded from laying capacity.
        let box = Box(kind: .superBox,
                      frames: (0..<s.system.framesPerBox).map { _ in Frame.drawn() })
        after.hive.boxes.append(box)
        return InterventionResult(after: after, splitOff: nil, blockedReason: nil)
    }

    // MARK: Add a brood box — real laying cells

    private static func addBroodBox(_ s: ColonySnapshot) -> InterventionResult {
        var after = s
        let box = Box(kind: .brood,
                      frames: (0..<s.system.framesPerBox).map { _ in Frame.drawn() })
        // A brood box goes on top of the existing brood nest, under any supers.
        let insertAt = after.hive.boxes.lastIndex(where: { $0.kind == .brood }).map { $0 + 1 }
            ?? after.hive.boxes.count
        after.hive.boxes.insert(box, at: insertAt)
        return InterventionResult(after: after, splitOff: nil, blockedReason: nil)
    }

    // MARK: Swap sealed brood out for drawn comb

    private static func swapBroodForDrawn(_ s: ColonySnapshot) -> InterventionResult {
        var after = s

        // Find the fullest sealed-brood frames in the brood boxes.
        var candidates: [(box: Int, frame: Int, sealed: Double)] = []
        for (bi, box) in after.hive.boxes.enumerated() where box.kind == .brood {
            for (fi, f) in box.frames.enumerated() where f.sealedBroodFraction > 0.2 {
                candidates.append((bi, fi, f.sealedBroodFraction))
            }
        }
        guard candidates.count >= 1 else {
            return InterventionResult(
                after: s, splitOff: nil,
                blockedReason: "There is no frame of sealed brood to take out yet.")
        }

        candidates.sort { $0.sealed > $1.sealed }
        for target in candidates.prefix(swapFrameCount) {
            // Drawn comb in its place: empty cells, available today.
            after.hive.boxes[target.box].frames[target.frame] = Frame.drawn()
        }
        return InterventionResult(after: after, splitOff: nil, blockedReason: nil)
    }

    // MARK: Split — both halves run forward

    private static func split(_ s: ColonySnapshot,
                              now: Date,
                              calendar: Calendar) -> InterventionResult {
        let broodBoxes = s.hive.broodBoxes
        let totalBroodFrames = broodBoxes.reduce(0) { $0 + $1.frames.count }
        guard totalBroodFrames >= 6 else {
            return InterventionResult(
                after: s, splitOff: nil,
                blockedReason: "This colony is too small to divide — you'd weaken both halves.")
        }

        var keeper = s
        var leaver = s

        // Halve the brood frames between the two colonies.
        for (bi, box) in s.hive.boxes.enumerated() where box.kind == .brood {
            let half = box.frames.count / 2
            keeper.hive.boxes[bi].frames = Array(box.frames.prefix(half))
                + (0..<(box.frames.count - half)).map { _ in Frame.drawn() }
            leaver.hive.boxes[bi].frames = Array(box.frames.suffix(box.frames.count - half))
                + (0..<half).map { _ in Frame.drawn() }
        }

        // The half that keeps the laying queen carries on; supers stay with it.
        keeper.hive.cellObservations = []
        keeper.hive.cellsCutAt = nil

        // The queenless half starts its 16-day queen clock today.
        leaver.hive.id = IDs.new()
        leaver.hive.name = "\(s.hive.name) split"
        leaver.hive.boxes.removeAll { $0.kind == .superBox }
        leaver.hive.queenlessSince = calendar.startOfDay(for: now)
        leaver.hive.cellObservations = s.hive.cellObservations
        leaver.hive.cellsCutAt = nil
        leaver.hive.swarmEvents = []
        leaver.hive.archivedProjections = []
        leaver.hive.queen = Queen(
            introducedYear: calendar.component(.year, from: now),
            markColour: QueenMark.forYear(calendar.component(.year, from: now)))

        return InterventionResult(after: keeper, splitOff: leaver, blockedReason: nil)
    }

    // MARK: Cut cells — does NOT clear the risk state

    private static func cutCells(_ s: ColonySnapshot,
                                 now: Date,
                                 calendar: Calendar) -> InterventionResult {
        guard !s.hive.liveCellObservations(now: now).isEmpty else {
            return InterventionResult(
                after: s, splitOff: nil,
                blockedReason: "There are no cells recorded on this colony to cut.")
        }
        var after = s
        after.hive.cellObservations = []
        // The mark that keeps this colony honest: cells were cut, the cause was not
        // touched, and the projection must keep saying so (§10.3).
        after.hive.cellsCutAt = calendar.startOfDay(for: now)
        return InterventionResult(after: after, splitOff: nil, blockedReason: nil)
    }
}
