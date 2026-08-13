//
//  HexLattice.swift
//  QueenRight
//
//  The hex lattice at every scale (§3 Texture): behind panels as a hairline, as the
//  substrate brood is painted on, inside frame glyphs, and in the icon.
//  `HexGrid` is the geometry; `HexLatticeView` draws it; `HexCoverage` paints a
//  fraction of the lattice cell-by-cell so the unit of measurement stays visible —
//  brood is NEVER drawn as a bar (§3).
//

import SwiftUI

/// Pointy-top hex grid geometry in a unit space, addressed row/column.
enum HexGrid {
    /// Centre of the hex at (row, col) for a given cell width, with odd rows offset.
    static func center(row: Int, col: Int, cellWidth w: CGFloat) -> CGPoint {
        let h = w * 1.1547005  // 2/√3 — height of a flat-top hex of width w
        let x = w * (CGFloat(col) + (row % 2 == 0 ? 0.5 : 1.0))
        let y = h * 0.75 * CGFloat(row) + h * 0.5
        return CGPoint(x: x, y: y)
    }

    static func rowHeight(cellWidth w: CGFloat) -> CGFloat { w * 1.1547005 * 0.75 }

    /// How many rows/cols of `cellWidth` fit in `size`.
    static func dimensions(in size: CGSize, cellWidth w: CGFloat) -> (rows: Int, cols: Int) {
        guard w > 0 else { return (0, 0) }
        let rows = max(1, Int(ceil(size.height / rowHeight(cellWidth: w))) + 1)
        let cols = max(1, Int(ceil(size.width / w)) + 1)
        return (rows, cols)
    }

    /// A flat-top hexagon path centred on `c`.
    static func path(center c: CGPoint, width w: CGFloat) -> Path {
        let h = w * 1.1547005
        var p = Path()
        p.addLines([
            CGPoint(x: c.x - w * 0.5, y: c.y - h * 0.25),
            CGPoint(x: c.x,           y: c.y - h * 0.5),
            CGPoint(x: c.x + w * 0.5, y: c.y - h * 0.25),
            CGPoint(x: c.x + w * 0.5, y: c.y + h * 0.25),
            CGPoint(x: c.x,           y: c.y + h * 0.5),
            CGPoint(x: c.x - w * 0.5, y: c.y + h * 0.25)
        ])
        p.closeSubpath()
        return p
    }
}

/// The hairline comb showing through behind elevated content (§3 Elevation).
struct HexLatticeView: View {
    var cellWidth: CGFloat = 14
    var color: Color = Palette.lattice
    var lineWidth: CGFloat = 0.75

    var body: some View {
        Canvas { context, size in
            let (rows, cols) = HexGrid.dimensions(in: size, cellWidth: cellWidth)
            var path = Path()
            for r in 0..<rows {
                for c in 0..<cols {
                    path.addPath(HexGrid.path(
                        center: HexGrid.center(row: r, col: c, cellWidth: cellWidth),
                        width: cellWidth))
                }
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}

/// Fills `coverage` (0…1) of the lattice, cell by cell, from the bottom up —
/// the way brood actually sits on a frame, with stores arcing over the top.
/// The count of filled cells IS the measurement, so it must be drawn as cells.
struct HexCoverage: View {
    var coverage: Double
    var color: Color
    var cellWidth: CGFloat = 10
    /// Fill from the bottom (brood) rather than the top (stores).
    var fromBottom: Bool = true

    var body: some View {
        Canvas { context, size in
            let (rows, cols) = HexGrid.dimensions(in: size, cellWidth: cellWidth)
            let total = rows * cols
            guard total > 0 else { return }
            let target = Int((Double(total) * coverage.clamped(to: 0...1)).rounded())
            guard target > 0 else { return }

            // Walk rows in fill order and take whole cells until the budget runs out.
            let order = fromBottom ? Array((0..<rows).reversed()) : Array(0..<rows)
            var filled = 0
            var path = Path()
            outer: for r in order {
                for c in 0..<cols {
                    if filled >= target { break outer }
                    path.addPath(HexGrid.path(
                        center: HexGrid.center(row: r, col: c, cellWidth: cellWidth),
                        width: cellWidth * 0.92))   // slight gap = visible cell walls
                    filled += 1
                }
            }
            context.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Small numeric helper used across the domain and the views

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}
