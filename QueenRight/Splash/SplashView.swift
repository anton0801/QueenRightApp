//
//  SplashView.swift
//  QueenRight
//
//  Splash construction: COMB-FILL (§2 variance roll). Hexagons draw outward from the
//  centre in the spiral bees actually build comb in, and the wordmark sets in the
//  cleared middle. A seamless TimelineView loop — never a logo scale-and-fade.
//  Reduce Motion shows the settled frame and crossfades out.
//

import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rings of hexagons drawn out from the centre.
    private let rings = 6
    private let cell: CGFloat = 34

    var body: some View {
        ZStack {
            Palette.surface.ignoresSafeArea()

            if reduceMotion {
                combCanvas(progress: 1)
            } else {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let phase = (t.truncatingRemainder(dividingBy: Motion.splashLoop)) / Motion.splashLoop
                    // Ease the fill so comb accretes and settles, then repeats seamlessly.
                    combCanvas(progress: eased(phase))
                }
            }

            wordmark
        }
    }

    /// Fill out, hold, and fade back so the loop has no visible seam.
    private func eased(_ p: Double) -> Double {
        if p < 0.55 {
            let x = p / 0.55
            return x * x * (3 - 2 * x)
        } else if p < 0.8 {
            return 1
        } else {
            let x = (p - 0.8) / 0.2
            return 1 - (x * x * (3 - 2 * x))
        }
    }

    private func combCanvas(progress: Double) -> some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let cells = spiralCells()
            let shown = Int((Double(cells.count) * progress).rounded())
            guard shown > 0 else { return }

            for (index, offset) in cells.prefix(shown).enumerated() {
                let point = CGPoint(x: centre.x + offset.x * cell * 0.87,
                                    y: centre.y + offset.y * cell * 0.75)
                let path = HexGrid.path(center: point, width: cell)

                // Cells nearest the middle are cleared for the wordmark.
                let distance = hypot(offset.x, offset.y)
                guard distance > 1.6 else { continue }

                // The newest cells arrive in honey and cool into smoke, the way fresh
                // wax darkens as the colony works it.
                let age = Double(shown - index) / Double(max(1, cells.count))
                let honey = max(0, 1 - age * 5)
                context.fill(path, with: .color(Palette.accent.opacity(0.10 + honey * 0.25)))
                context.stroke(path, with: .color(Palette.accent.opacity(0.22 + honey * 0.5)),
                               lineWidth: 1)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Hex coordinates in a true outward spiral — the order bees build comb in.
    private func spiralCells() -> [CGPoint] {
        var result: [CGPoint] = [.zero]
        // Axial directions on a flat-top hex grid.
        let directions: [(Double, Double)] = [
            (1, 0), (0.5, 1), (-0.5, 1), (-1, 0), (-0.5, -1), (0.5, -1)
        ]
        for ring in 1...rings {
            // Step out to the start of this ring, then walk its six sides.
            var x = -0.5 * Double(ring)
            var y = -1.0 * Double(ring)
            for direction in directions {
                for _ in 0..<ring {
                    result.append(CGPoint(x: x, y: y))
                    x += direction.0
                    y += direction.1
                }
            }
        }
        return result
    }

    private var wordmark: some View {
        VStack(spacing: 6) {
            Text(AppInfo.name)
                .font(.system(size: Typo.scaled(38), weight: .semibold, design: .serif))
                .foregroundStyle(Palette.textPrimary)
            Text(AppInfo.tagline)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(AppInfo.name). \(AppInfo.tagline)")
    }
}

#Preview {
    SplashView()
}
