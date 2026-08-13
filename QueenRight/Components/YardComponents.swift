//
//  YardComponents.swift
//  QueenRight
//
//  §6.9 FlowLine, §6.10 EmptyStandComposition, and the hive glyph that stands in the
//  yard plan (§5.1). Hives are stacked-box glyphs where you placed them, tinted by risk,
//  with days-since-inspection in tabular figures beneath.
//

import SwiftUI

// MARK: - FlowLine (§6.9)

struct FlowLine: View {
    let text: String
    var staleness: String?
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: Space.tight) {
            Image(systemName: "wind")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
            Text(text)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
            if let staleness {
                Text("· \(staleness)")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary.opacity(0.8))
            }
            Spacer(minLength: 0)
            if isLoading {
                ProgressView().scaleEffect(0.6).tint(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.row)
        .padding(.vertical, Space.tight)
        .combPanel(fill: Palette.surfaceElevated, cut: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([text, staleness].compactMap { $0 }.joined(separator: ", "))
    }
}

// MARK: - Hive glyph in the yard plan (§5.1)

struct HivePlanGlyph: View {
    let hive: Hive
    let state: RiskState
    let daysSince: Int
    /// Nobody has looked inside for long enough that the projection is a guess.
    var isBlind: Bool = false
    var isCompact: Bool = false

    var body: some View {
        VStack(spacing: 5) {
            stack
            VStack(spacing: 1) {
                Text(hive.name)
                    .font(Typo.captionMed)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(verbatim: "\(daysSince)d")
                    .font(Typo.figureSmall)
                    .foregroundStyle(isBlind ? Palette.watch : Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    private var label: String {
        var parts = [hive.name, state.word.lowercased(),
                     "last looked at \(Fmt.days(daysSince)) ago"]
        if isBlind { parts.append("running blind") }
        return parts.joined(separator: ", ")
    }

    /// A stack of boxes seen from the side — literally what a hive is.
    private var stack: some View {
        VStack(spacing: 2) {
            ForEach(Array(hive.boxes.enumerated().reversed()), id: \.element.id) { _, box in
                Rectangle()
                    .fill(box.kind == .brood ? state.tint : state.tint.opacity(0.45))
                    .frame(width: isCompact ? 34 : 44,
                           height: box.kind == .brood ? (isCompact ? 16 : 20) : (isCompact ? 9 : 12))
                    .overlay { if isBlind { HatchOverlay() } }
                    .overlay(Rectangle().stroke(
                        isBlind ? Palette.watch : Palette.hairlineStrong,
                        lineWidth: isBlind ? 1 : 0.75))
            }
            // The stand.
            Rectangle()
                .fill(Palette.timber)
                .frame(width: isCompact ? 40 : 52, height: 3)
        }
    }
}

/// Diagonal hatching — the mark this app uses for "not measured, inferred" (§5.1).
struct HatchOverlay: View {
    var spacing: CGFloat = 5
    var colour: Color = Palette.surface.opacity(0.55)

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(colour), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - EmptyStandComposition (§6.10)

/// A drawn empty hive stand. The empty state is a picture of the thing that is missing,
/// not an icon and a shrug.
struct EmptyStandComposition: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let cx = w / 2

            // Two legs and a rail — an empty stand waiting for a hive.
            var stand = Path()
            stand.addRect(CGRect(x: cx - 62, y: h * 0.62, width: 124, height: 6))
            stand.addRect(CGRect(x: cx - 54, y: h * 0.62 + 6, width: 8, height: h * 0.24))
            stand.addRect(CGRect(x: cx + 46, y: h * 0.62 + 6, width: 8, height: h * 0.24))
            context.fill(stand, with: .color(Palette.timber))

            // The ghost of the hive that will sit here.
            var ghost = Path()
            ghost.addRect(CGRect(x: cx - 46, y: h * 0.62 - 46, width: 92, height: 46))
            ghost.addRect(CGRect(x: cx - 46, y: h * 0.62 - 72, width: 92, height: 24))
            context.stroke(ghost, with: .color(Palette.hairlineStrong),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // A few cells of comb drifting where the frames would be.
            for i in 0..<5 {
                let p = CGPoint(x: cx - 32 + CGFloat(i) * 16, y: h * 0.62 - 24)
                context.stroke(HexGrid.path(center: p, width: 13),
                               with: .color(Palette.accent.opacity(0.35)), lineWidth: 1)
            }
        }
        .frame(height: 190)
        .accessibilityHidden(true)
    }
}

// MARK: - Small shared row

struct StatRow: View {
    let label: String
    let value: String
    var tint: Color = Palette.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: Space.tight)
            Text(value)
                .font(Typo.figure)
                .foregroundStyle(tint)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}
