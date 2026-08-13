//
//  SwarmClockHeader.swift
//  QueenRight
//
//  §6.3 — the window and days remaining, in serif display, across the three risk
//  states. Colour never carries meaning alone: every state prints its word (§9).
//

import SwiftUI

struct SwarmClockHeader: View {
    let projection: SwarmProjection
    let hiveName: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            HStack(alignment: .center, spacing: Space.tight) {
                RiskChip(state: projection.riskState, label: projection.chipLabel)
                if projection.isBlind {
                    Text("RUNNING BLIND")
                        .font(Typo.label)
                        .tracking(1.1)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .combOutline(stroke: Palette.hairlineStrong, cut: 5, dash: [3, 3])
                }
                Spacer()
                Text("\(Fmt.days(projection.daysSinceInspection)) since you looked")
                    .font(Typo.figureSmall)
                    .foregroundStyle(Palette.textSecondary)
            }

            headline

            Text(projection.reason)
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let cellsReturn = projection.cellsReturnWindow {
                Label("New cells expected \(Fmt.window(cellsReturn))",
                      systemImage: "exclamationmark.triangle")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.watch)
            }
            if let age = projection.suspendedFlowTermAgeDays {
                Text(age == 0
                     ? "Forage reading is hours old — the flow term is set aside, not guessed."
                     : "Forage reading is \(Fmt.days(age)) old — the flow term is set aside, not guessed.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.gap)
        .combPanel(fill: Palette.surfaceElevated)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverSummary)
    }

    @ViewBuilder
    private var headline: some View {
        switch projection.verdict {
        case .imminent:
            VStack(alignment: .leading, spacing: 0) {
                Text("Today or tomorrow")
                    .font(Typo.display)
                    .foregroundStyle(Palette.imminent)
                    .fixedSize(horizontal: false, vertical: true)
                Text("the prime swarm issues")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

        case .watch:
            VStack(alignment: .leading, spacing: 0) {
                if let window = projection.window, let days = projection.daysUntilWindow() {
                    Text(days == 0 ? "Today" : Fmt.days(days))
                        .font(Typo.display)
                        .foregroundStyle(Palette.watch)
                    Text("until the window opens, \(Fmt.window(window))")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Watch")
                        .font(Typo.display)
                        .foregroundStyle(Palette.watch)
                    Text("no dated window yet")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }

        case .queenless(let queenDue, let layingResumes):
            VStack(alignment: .leading, spacing: 0) {
                Text("Queenless")
                    .font(Typo.display)
                    .foregroundStyle(Palette.textPrimary)
                if let due = queenDue {
                    Text("queen due \(Fmt.day(due))")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                if let resumes = layingResumes {
                    Text("laying resumes \(Fmt.window(resumes))")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }

        case .outOfSeason:
            VStack(alignment: .leading, spacing: 0) {
                Text("Clock off")
                    .font(Typo.display)
                    .foregroundStyle(Palette.calm)
                Text("out of the swarm season here")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

        case .calm:
            VStack(alignment: .leading, spacing: 0) {
                Text("Calm")
                    .font(Typo.display)
                    .foregroundStyle(Palette.calm)
                Text("nothing to do today")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    /// "hive 3, imminent, capped queen cells seen yesterday, swarm expected today or
    /// tomorrow" (§9).
    private var voiceOverSummary: String {
        var parts = [hiveName, projection.riskState.word.lowercased(), projection.reason]
        if projection.isBlind {
            parts.append("running blind, \(Fmt.days(projection.daysSinceInspection)) since the last inspection")
        }
        return parts.joined(separator: ", ")
    }
}
