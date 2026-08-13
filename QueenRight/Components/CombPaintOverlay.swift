//
//  CombPaintOverlay.swift
//  QueenRight
//
//  §6.5 — finger-painted brood measurement on the rectified photo. The lattice fills
//  CELL BY CELL as you paint, so the unit of measurement is visible: you are not moving
//  a slider, you are counting cells. Area converts to cells from the frame's known
//  geometry, which is why the cells-per-frame constants matter.
//

import SwiftUI

struct CombPaintOverlay: View {
    /// Which pass is being painted.
    enum Pass {
        case sealedBrood
        case stores

        var tint: Color {
            switch self {
            case .sealedBrood: return Palette.sealedBrood
            case .stores: return Palette.stores
            }
        }

        var title: String {
            switch self {
            case .sealedBrood: return "Paint over the sealed brood"
            case .stores: return "Now paint the stores"
            }
        }
    }

    let pass: Pass
    /// Painted lattice cells, addressed row/col so a cell can only be counted once.
    @Binding var painted: Set<PaintedCell>
    /// Cells across the lattice — drives the resolution of the measurement.
    var columns: Int = 26

    struct PaintedCell: Hashable {
        let row: Int
        let col: Int
    }

    /// Fraction of the frame covered, which is what becomes a cell count.
    static func coverage(painted: Set<PaintedCell>, columns: Int, rows: Int) -> Double {
        let total = max(1, columns * rows)
        return Double(painted.count) / Double(total)
    }

    var body: some View {
        GeometryReader { geo in
            let cellWidth = geo.size.width / CGFloat(columns)
            let rows = max(1, Int(geo.size.height / HexGrid.rowHeight(cellWidth: cellWidth)))

            ZStack {
                // The lattice you are painting onto.
                Canvas { context, size in
                    var grid = Path()
                    for r in 0..<rows {
                        for c in 0..<columns {
                            grid.addPath(HexGrid.path(
                                center: HexGrid.center(row: r, col: c, cellWidth: cellWidth),
                                width: cellWidth))
                        }
                    }
                    context.stroke(grid, with: .color(Palette.textPrimary.opacity(0.25)),
                                   lineWidth: 0.5)

                    var filled = Path()
                    for cell in painted where cell.row < rows && cell.col < columns {
                        filled.addPath(HexGrid.path(
                            center: HexGrid.center(row: cell.row, col: cell.col, cellWidth: cellWidth),
                            width: cellWidth * 0.92))
                    }
                    context.fill(filled, with: .color(pass.tint.opacity(0.72)))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        paint(at: value.location, cellWidth: cellWidth, rows: rows)
                    }
            )
        }
        .accessibilityLabel(pass.title)
    }

    private func paint(at point: CGPoint, cellWidth: CGFloat, rows: Int) {
        let rowHeight = HexGrid.rowHeight(cellWidth: cellWidth)
        let row = Int((point.y - rowHeight * 0.5) / rowHeight + 0.5)
        guard row >= 0, row < rows else { return }
        let offset: CGFloat = row % 2 == 0 ? 0.5 : 1.0
        let col = Int(point.x / cellWidth - offset + 0.5)
        guard col >= 0, col < columns else { return }

        let cell = PaintedCell(row: row, col: col)
        if !painted.contains(cell) {
            painted.insert(cell)
            // A light tick per cell would be relentless; the count is the feedback.
        }
    }
}

// MARK: - Version-safe helpers

extension View {
    /// `onChange(of:perform:)` was deprecated in iOS 17 in favour of a two-argument
    /// closure. The app's floor is iOS 16, so both spellings have to be reachable —
    /// this picks the right one at compile time under a distinct name, avoiding any
    /// clash with the real SwiftUI overloads.
    @ViewBuilder
    func onValueChange<V: Equatable>(of value: V,
                                     perform: @escaping (V) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in perform(newValue) }
        } else {
            self.onChange(of: value) { newValue in perform(newValue) }
        }
    }

    /// `navigationDestination(item:destination:)` is iOS 17+. This drives the same
    /// push from an optional identifier on iOS 16 without shadowing the real API.
    @ViewBuilder
    func navigationDestination<D: View>(
        forOptional item: Binding<String?>,
        @ViewBuilder destination: @escaping (String) -> D
    ) -> some View {
        navigationDestination(isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )) {
            if let value = item.wrappedValue {
                destination(value)
            }
        }
    }
}
