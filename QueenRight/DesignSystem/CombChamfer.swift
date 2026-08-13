//
//  CombChamfer.swift
//  QueenRight
//
//  Shape language (§3): 0pt radius with a 10pt 60° chamfer on the TOP-LEFT and
//  BOTTOM-RIGHT corners, so every panel reads as one cell in a lattice and panels
//  tessellate like comb. No rounded corners anywhere in the app.
//

import SwiftUI

/// A rectangle with two opposing corners cut at 60°, like a comb cell wall.
struct CombChamfer: Shape {
    /// Length of the cut along each edge. 10pt is the house value (§3).
    var cut: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        // Never let the chamfer eat more than half of the shorter side.
        let c = min(cut, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        p.closeSubpath()
        return p
    }
}

/// A single hexagon, flat-topped, used for the icon mark and lattice cells.
struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // Flat-top hexagon: vertices at 0°, 60°, 120°, 180°, 240°, 300°.
        let pts = [
            CGPoint(x: rect.minX + w * 0.25, y: rect.minY),
            CGPoint(x: rect.minX + w * 0.75, y: rect.minY),
            CGPoint(x: rect.maxX,            y: rect.minY + h * 0.5),
            CGPoint(x: rect.minX + w * 0.75, y: rect.maxY),
            CGPoint(x: rect.minX + w * 0.25, y: rect.maxY),
            CGPoint(x: rect.minX,            y: rect.minY + h * 0.5)
        ]
        p.addLines(pts)
        p.closeSubpath()
        return p
    }
}

// MARK: - Panel treatment

extension View {
    /// The house panel: flat fill, 1px hairline, chamfered on opposing corners.
    /// Flat fills only — no shadows, no translucency (§3 Elevation).
    func combPanel(fill: Color = Palette.surfaceElevated,
                   stroke: Color = Palette.hairline,
                   cut: CGFloat = 10) -> some View {
        background(CombChamfer(cut: cut).fill(fill))
            .overlay(CombChamfer(cut: cut).stroke(stroke, lineWidth: 1))
            .contentShape(CombChamfer(cut: cut))
    }

    /// A chamfered outline with no fill — used for empty/foundation states.
    func combOutline(stroke: Color = Palette.hairline,
                     cut: CGFloat = 10,
                     dash: [CGFloat] = []) -> some View {
        overlay(
            CombChamfer(cut: cut)
                .stroke(stroke, style: StrokeStyle(lineWidth: 1, dash: dash))
        )
    }
}
