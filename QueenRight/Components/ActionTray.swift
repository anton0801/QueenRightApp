//
//  ActionTray.swift
//  QueenRight
//
//  §6.7 — the interventions, reordered by state. When a colony is imminent the split
//  comes first, because space alone will no longer save it.
//

import SwiftUI

struct ActionTray: View {
    let state: RiskState
    var onPick: (Intervention) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.tight) {
                    ForEach(Intervention.trayOrder(for: state)) { action in
                        Button { onPick(action) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                    .font(Typo.captionMed)
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(action.subtitle)
                                    .font(Typo.caption)
                                    .foregroundStyle(Palette.textSecondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            // Width is fixed so the cards form a rhythm; height is not,
                            // so nothing clips as Dynamic Type grows.
                            .frame(width: 168, alignment: .topLeading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(Space.tight)
                            .combPanel(fill: Palette.surfaceElevated,
                                       stroke: isLead(action) ? Palette.imminent : Palette.hairlineStrong,
                                       cut: 7)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("\(action.title). \(action.subtitle)")
                    }
                }
                .padding(.horizontal, Space.screen)
                .padding(.vertical, Space.row)
            }
            .background(Palette.surface)
        }
    }

    /// The first action is highlighted only when the colony is imminent.
    private func isLead(_ action: Intervention) -> Bool {
        state == .imminent && Intervention.trayOrder(for: state).first == action
    }
}

// MARK: - DualPathProjection (§6.8)

/// Before and after on ONE axis — not two charts. For a split, both halves.
struct DualPathProjection: View {
    let before: SwarmProjection
    let after: SwarmProjection
    var splitOff: SwarmProjection?
    var isCommitted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            chart
            legend
        }
    }

    private var chart: some View {
        Canvas { context, size in
            let count = max(before.days.count, after.days.count)
            guard count > 1 else { return }
            let step = size.width / CGFloat(count - 1)

            func line(_ projection: SwarmProjection) -> Path {
                var p = Path()
                for (i, day) in projection.days.enumerated() {
                    let x = CGFloat(i) * step
                    let y = size.height * (1 - CGFloat(day.spacePressure.clamped(to: 0...1)))
                    i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
                }
                return p
            }

            // The congestion threshold — where cells get built.
            let thresholdY = size.height * (1 - CGFloat(RiskWeights.congestedSpacePressure))
            var threshold = Path()
            threshold.move(to: CGPoint(x: 0, y: thresholdY))
            threshold.addLine(to: CGPoint(x: size.width, y: thresholdY))
            context.stroke(threshold, with: .color(Palette.imminent.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

            // Today.
            let todayX = CGFloat(before.todayIndex) * step
            var todayLine = Path()
            todayLine.move(to: CGPoint(x: todayX, y: 0))
            todayLine.addLine(to: CGPoint(x: todayX, y: size.height))
            context.stroke(todayLine, with: .color(Palette.hairlineStrong), lineWidth: 1)

            context.stroke(line(before), with: .color(Palette.textSecondary), lineWidth: 1.5)
            context.stroke(line(after), with: .color(Palette.accent),
                           style: StrokeStyle(lineWidth: 2,
                                              dash: isCommitted ? [] : [5, 4]))
            if let splitOff {
                // The half that leaves belongs to the same future as `after`, so it
                // stays in the honey family — but dotted and lighter, because grey
                // would be indistinguishable from the "as it stands" line.
                context.stroke(line(splitOff), with: .color(Palette.accent.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 2, dash: [1.5, 3.5]))
            }
        }
        .frame(height: 120)
        .padding(Space.tight)
        .combPanel(fill: Palette.surfaceSunken)
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var legend: some View {
        HStack(spacing: Space.row) {
            key(Palette.textSecondary, "As it stands")
            key(Palette.accent, "After")
            if splitOff != nil {
                key(Palette.accent.opacity(0.55), "The half that leaves", dotted: true)
            }
            Spacer()
        }
    }

    private func key(_ colour: Color, _ label: String, dotted: Bool = false) -> some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(colour)
                .frame(width: 14, height: 2)
                .mask {
                    if dotted {
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { _ in Rectangle() }
                        }
                    } else {
                        Rectangle()
                    }
                }
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var accessibilitySummary: String {
        let b = before.days[safe: before.todayIndex]?.spacePressure ?? 0
        let a = after.days[safe: after.todayIndex]?.spacePressure ?? 0
        let delta = a - b
        let change: String
        if abs(delta) < 0.005 {
            change = "space pressure does not change at all"
        } else if delta < 0 {
            change = "space pressure falls from \(Fmt.percent(b)) to \(Fmt.percent(a))"
        } else {
            change = "space pressure rises from \(Fmt.percent(b)) to \(Fmt.percent(a))"
        }
        return "Projection. \(change)."
    }
}
