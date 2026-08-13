//
//  ActionSheetView.swift
//  QueenRight
//
//  §5.4 — commit a change and see both futures. The action at the head, then before and
//  after on ONE axis. For a split, both halves with their own clocks.
//
//  This screen carries the app's central honesty: adding a super changes space pressure
//  by exactly zero and the interface says so in words (§10.2, acceptance 3), and cutting
//  cells never clears the risk (§10.3).
//

import SwiftUI

struct ActionSheetView: View {
    let hiveId: String
    let action: Intervention

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var committed = false

    var body: some View {
        NavigationStack {
            ZStack {
                CombGround()
                if let hive = state.hive(id: hiveId) {
                    content(hive: hive)
                } else {
                    Text("This hive is no longer here.")
                        .font(Typo.body)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Palette.textPrimary)
                }
            }
        }
    }

    private func content(hive: Hive) -> some View {
        let snapshot = state.snapshot(for: hive)
        let result = Interventions.apply(action, to: snapshot)
        let before = state.projection(for: hive)
        let after = state.projection(forHypothetical: result.after)
        let splitOff = result.splitOff.map { state.projection(forHypothetical: $0) }

        return ScrollView {
            VStack(alignment: .leading, spacing: Space.gap) {
                if let blocked = result.blockedReason {
                    notApplicable(blocked)
                } else {
                    Text(action.explanation)
                        .font(Typo.body)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    DualPathProjection(before: before, after: after,
                                       splitOff: splitOff, isCommitted: committed)

                    verdict(before: before, after: after)

                    if let splitOff {
                        splitHalves(keeper: after, leaver: splitOff)
                    }

                    Button(committed ? "Done" : "Commit this") {
                        if committed { dismiss() } else { commit(result: result) }
                    }
                    .buttonStyle(HoneyButtonStyle())
                }
            }
            .padding(Space.screen)
        }
    }

    // MARK: - The verdict, in words and cells

    private func verdict(before: SwarmProjection, after: SwarmProjection) -> some View {
        let b = before.days[safe: before.todayIndex]
        let a = after.days[safe: after.todayIndex]
        let deltaPressure = (a?.spacePressure ?? 0) - (b?.spacePressure ?? 0)
        let deltaCells = Int((a?.openCells ?? 0) - (b?.openCells ?? 0))

        return VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: "What this does")

            HStack(alignment: .top, spacing: Space.gap) {
                FigureBlock(value: deltaCells == 0 ? "None" : Fmt.cells(abs(deltaCells)),
                            caption: deltaCells >= 0 ? "cells gained to lay in" : "cells lost",
                            tint: deltaCells > 0 ? Palette.accent : Palette.textPrimary)
                FigureBlock(value: Fmt.percent(a?.spacePressure ?? 0),
                            caption: "space pressure after")
            }

            // The sentence the whole app exists to be able to say (§10.2).
            Text(sentence(deltaPressure: deltaPressure, deltaCells: deltaCells,
                          before: before, after: after))
                .font(Typo.bodyMedium)
                .foregroundStyle(deltaPressure < -0.001 ? Palette.textPrimary : Palette.watch)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.gap)
        .combPanel(fill: Palette.surfaceElevated)
    }

    private func sentence(deltaPressure: Double, deltaCells: Int,
                          before: SwarmProjection, after: SwarmProjection) -> String {
        switch action {
        case .addSuper:
            return "Space pressure does not move. A super is somewhere to put honey, not somewhere to lay — the queen has exactly as many cells as before."
        case .cutCells:
            return "The risk does not clear. Cells were cut and the cause was left untouched, so expect new cells within 4 to 7 days."
        case .swapBroodForDrawn:
            return deltaCells > 0
                ? "The queen gets \(Fmt.cells(deltaCells)) empty cells today, and the bees in the frames you took out still emerge."
                : "There was no sealed brood to swap out, so nothing changed."
        case .addBroodBox:
            return deltaCells > 0
                ? "\(Fmt.cells(deltaCells)) more cells to lay in, available now because the comb is already drawn."
                : "The colony already has more room than it can use."
        case .split:
            return "The colony reproduces on your terms. Both halves are drawn above."
        }
    }

    private func splitHalves(keeper: SwarmProjection, leaver: SwarmProjection) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: "Both halves")
            halfRow(title: "Keeps the queen", projection: keeper)
            halfRow(title: "Queenless half", projection: leaver)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.gap)
        .combPanel(fill: Palette.surfaceElevated)
    }

    private func halfRow(title: String, projection: SwarmProjection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.textPrimary)
                RiskChip(state: projection.riskState, label: projection.chipLabel, compact: true)
            }
            Text(projection.reason)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notApplicable(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            Text("Not this one")
                .font(Typo.displaySm)
                .foregroundStyle(Palette.textPrimary)
            Text(reason)
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.gap)
        .combPanel(fill: Palette.surfaceElevated)
    }

    // MARK: - Commit

    private func commit(result: InterventionResult) {
        let newHive = result.after.hive
        state.updateHive(id: hiveId) { hive in
            hive.boxes = newHive.boxes
            hive.cellObservations = newHive.cellObservations
            hive.cellsCutAt = newHive.cellsCutAt
            hive.queenlessSince = newHive.queenlessSince
        }
        if let leaver = result.splitOff?.hive {
            state.addHive(leaver)
        }
        Haptics.actionDropped()
        withAnimation(.comb) { committed = true }
    }
}
