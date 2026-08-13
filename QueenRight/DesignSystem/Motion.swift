//
//  Motion.swift
//  QueenRight
//
//  §3 Motion. Base spring response 0.45 / damping 0.85 — unhurried, like smoke
//  settling a colony. The signature move is the board playing forward at roughly
//  one day per 0.12s. Reduce Motion replaces play-forward with a jump-to-day
//  slider (§9, acceptance 16), so every animated surface reads `reduceMotion`.
//

import SwiftUI

enum Motion {
    /// One simulated day per 0.12s while the board plays forward (§3).
    static let dayStep: Double = 0.12
    /// Frames redraw left to right within a box.
    static let frameStagger: Double = 0.03
    /// The honey pulse travelling across the lattice on a swarm averted (§3).
    static let celebration: Double = 0.9
    /// Seconds the splash holds before the comb-fill hands over.
    static let splashHold: Double = 2.2
    static let splashLoop: Double = 2.4
    static let splashExit: Double = 0.55
    /// Vision rectification snapping square (§5.3).
    static let rectify: Double = 0.30
}

extension Animation {
    /// Base spring — response 0.45, damping 0.85.
    static let comb       = Animation.spring(response: 0.45, dampingFraction: 0.85)
    /// Slightly quicker for small commits and presses.
    static let combSnappy = Animation.spring(response: 0.30, dampingFraction: 0.84)
    static let combPress  = Animation.spring(response: 0.26, dampingFraction: 0.80)
    /// Larger transitions — sheets, splash exit, screen changes.
    static let combExit   = Animation.spring(response: 0.55, dampingFraction: 0.88)
    /// One tick of the play-forward transport.
    static let combDay    = Animation.easeInOut(duration: Motion.dayStep)
}

/// Resolve an animation against Reduce Motion in one place.
/// Returns `nil` (i.e. no animation) when the user has asked for less movement.
func combAnimation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : animation
}

// MARK: - Stagger

/// Frames appear left to right within a box, 0.03s apart, capped so a 22-frame
/// box never takes longer to settle than a 10-frame one.
struct StaggerIn: ViewModifier {
    let index: Int
    var step: Double = Motion.frameStagger
    var cap: Int = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                let delay = Double(min(index, cap)) * step
                withAnimation(.comb.delay(delay)) { shown = true }
            }
    }
}

extension View {
    func staggerIn(_ index: Int) -> some View {
        modifier(StaggerIn(index: index))
    }
}
