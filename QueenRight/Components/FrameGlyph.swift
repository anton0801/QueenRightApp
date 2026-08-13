//
//  FrameGlyph.swift
//  QueenRight
//
//  §6.2 — a frame with its REAL sealed-brood region painted on a hex lattice.
//  Frames are tall narrow glyphs; the brood area inside one is a filled region on the
//  lattice, NEVER a bar (§3). Minimum width is 14pt because these are touch targets
//  used in gloves (§9).
//

import SwiftUI

struct FrameGlyph: View {
    let frame: Frame
    let system: HiveSystem
    let kind: BoxKind

    var width: CGFloat = 18
    var height: CGFloat = 86
    var isLifted: Bool = false
    var isSelected: Bool = false

    /// Minimum touch width — never shrinks past this (§5.2 edge cases).
    static let minWidth: CGFloat = 14

    private var latticeCell: CGFloat {
        max(3.5, width / 4.2)
    }

    var body: some View {
        ZStack {
            // Comb body: foundation reads flat and empty, drawn comb has cells.
            Rectangle().fill(frame.drawnFraction < 0.15 ? Palette.foundation : Palette.drawnComb)

            if frame.drawnFraction >= 0.15 {
                // The lattice IS the substrate; content is painted onto it.
                HexLatticeView(cellWidth: latticeCell,
                               color: Palette.hairline,
                               lineWidth: 0.4)

                // Stores arc over the top, the way bees actually store honey.
                HexCoverage(coverage: frame.storesFraction * frame.drawnFraction,
                            color: Palette.stores,
                            cellWidth: latticeCell,
                            fromBottom: false)

                // The whole brood nest is laid down in open-brood pearl first…
                HexCoverage(coverage: (frame.sealedBroodFraction + frame.openBroodFraction)
                                * frame.drawnFraction,
                            color: Palette.openBrood,
                            cellWidth: latticeCell,
                            fromBottom: true)

                // …then the sealed part is painted over it, from the bottom up. Drawing
                // in this order leaves open brood as the band ABOVE the sealed area —
                // which is where it actually sits — and keeps sealed brood its own
                // biscuit brown instead of bleaching it out.
                HexCoverage(coverage: frame.sealedBroodFraction * frame.drawnFraction,
                            color: Palette.sealedBrood,
                            cellWidth: latticeCell,
                            fromBottom: true)
            }
        }
        .frame(width: max(Self.minWidth, width), height: height)
        .overlay(
            Rectangle()
                .stroke(isSelected ? Palette.accent : Palette.hairlineStrong,
                        lineWidth: isSelected ? 1.5 : 0.75)
        )
        // Top bar — the wooden lug you actually hold.
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.timber)
                .frame(height: 4)
        }
        .rotationEffect(.degrees(isLifted ? 3 : 0))
        .scaleEffect(isLifted ? 1.06 : 1)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts: [String] = [frame.appearance.label]
        if frame.sealedBroodFraction > 0.01 {
            parts.append("sealed brood \(Fmt.percent(frame.sealedBroodFraction))")
            parts.append("\(Fmt.cells(Int(frame.sealedBroodCells(system: system, kind: kind)))) cells")
        }
        if frame.storesFraction > 0.01 {
            parts.append("stores \(Fmt.percent(frame.storesFraction))")
        }
        if frame.lastCapturedAt == nil {
            parts.append("not measured")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - The three queen-cell silhouettes (§6.6)

/// Cup, charged and capped drawn as three distinct shapes — their stage sets the clock,
/// so they are the most important icons in the app and are never a generic dot.
struct QueenCellMark: View {
    let stage: QueenCellStage
    var size: CGFloat = 24
    var tint: Color?

    var body: some View {
        let colour = tint ?? defaultTint
        Canvas { context, canvasSize in
            let w = canvasSize.width, h = canvasSize.height
            var path = Path()

            switch stage {
            case .cup:
                // A shallow open cup — a rim with nothing in it.
                path.addArc(center: CGPoint(x: w / 2, y: h * 0.42),
                            radius: w * 0.30,
                            startAngle: .degrees(0), endAngle: .degrees(180),
                            clockwise: false)
                context.stroke(path, with: .color(colour), lineWidth: 2)

            case .charged:
                // A lengthening cell, open at the tip, with a seed inside.
                path.move(to: CGPoint(x: w * 0.32, y: h * 0.18))
                path.addQuadCurve(to: CGPoint(x: w * 0.40, y: h * 0.80),
                                  control: CGPoint(x: w * 0.24, y: h * 0.55))
                path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.80))
                path.addQuadCurve(to: CGPoint(x: w * 0.68, y: h * 0.18),
                                  control: CGPoint(x: w * 0.76, y: h * 0.55))
                context.stroke(path, with: .color(colour), lineWidth: 2)
                var seed = Path()
                seed.addEllipse(in: CGRect(x: w * 0.43, y: h * 0.50,
                                           width: w * 0.14, height: h * 0.16))
                context.fill(seed, with: .color(colour))

            case .capped:
                // A full peanut, sealed over — solid, because it is closed.
                path.move(to: CGPoint(x: w * 0.30, y: h * 0.14))
                path.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.90),
                                  control: CGPoint(x: w * 0.18, y: h * 0.62))
                path.addQuadCurve(to: CGPoint(x: w * 0.70, y: h * 0.14),
                                  control: CGPoint(x: w * 0.82, y: h * 0.62))
                path.closeSubpath()
                context.fill(path, with: .color(colour))
                // The dimpled tip that says it is sealed.
                var tip = Path()
                tip.addEllipse(in: CGRect(x: w * 0.44, y: h * 0.74,
                                          width: w * 0.12, height: h * 0.10))
                context.fill(tip, with: .color(Palette.surface))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(stage.displayName) queen cell")
    }

    private var defaultTint: Color {
        switch stage {
        case .cup: return Palette.textSecondary
        case .charged: return Palette.watch
        case .capped: return Palette.imminent
        }
    }
}
