//
//  Palette.swift
//  QueenRight
//
//  "Honey & smoke" — §3 Art Direction. Honey #C98A22 over COOL smoke-grey surfaces;
//  the cold ground is what keeps this clear of the amber-on-cream family.
//  Risk WARMS as it rises: smoke-grey (calm) → honey (watch) → propolis (imminent).
//  There is deliberately NO GREEN token anywhere (§10.4) — green belongs to the
//  pasture sibling, and here calm must be the coldest, quietest colour on screen.
//

import SwiftUI
import UIKit

// MARK: - App identity

enum AppInfo {
    static let name = "Queenright"
    static let tagline = "Which hive is about to swarm."
    /// Shown on the Hive Board (§15 note) — this app models swarming, not disease.
    static let diseaseNote = """
        This app models swarming. It does not diagnose disease. If you suspect European or \
        American foulbrood, stop and contact your national bee inspector — in many countries \
        reporting is a legal requirement.
        """
}

// MARK: - Hex → UIColor helpers

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: alpha
        )
    }

    /// A trait-reactive colour: resolves light/dark automatically, so no view ever
    /// branches on `colorScheme`. This is how the app earns real dark mode.
    static func comb(dark: UInt32, light: UInt32,
                     darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkAlpha)
                : UIColor(rgb: light, alpha: lightAlpha)
        }
    }
}

// MARK: - Palette (§3 token table, light / dark)

enum Palette {
    /// Smoke — the cool ground everything sits on.
    static let surface         = Color(.comb(dark: 0x1A1916, light: 0xDEDEDA))
    static let surfaceElevated = Color(.comb(dark: 0x24221D, light: 0xEFEEE9))
    /// A deeper well for insets, pressed fills and the inside of a box.
    static let surfaceSunken   = Color(.comb(dark: 0x141310, light: 0xD2D2CD))

    static let textPrimary     = Color(.comb(dark: 0xEFEEE9, light: 0x241F16))
    static let textSecondary   = Color(.comb(dark: 0xA29B8C, light: 0x5E594E))

    /// Honey — the one accent.
    static let accent          = Color(.comb(dark: 0xE0A63C, light: 0xC98A22))
    static let accentMuted     = Color(.comb(dark: 0x7A5E1C, light: 0xE3C489))
    /// Legible ink to sit ON a honey fill.
    static let onAccent        = Color(.comb(dark: 0x1A1916, light: 0xFFFCF4))

    // MARK: Risk states — never colour-only, always paired with the word (§9)

    /// Calm: nothing to do. The coldest, quietest colour on screen — by design.
    static let calm            = Color(.comb(dark: 0x8F958D, light: 0x7A8079))
    /// Watch: cells charged, or the projection says congestion is coming.
    static let watch           = Color(.comb(dark: 0xE0A63C, light: 0xC98A22))
    /// Imminent: cells capped. Propolis red — keeps its luminance in BOTH
    /// appearances (§9): the one state that must never get quieter.
    static let imminent        = Color(.comb(dark: 0xC4553C, light: 0xA33B26))

    // MARK: Comb content

    /// Sealed (capped) brood — the biscuit-brown of a capped worker cell.
    /// Kept deliberately BROWN and well clear of `stores` in both appearances: telling
    /// capped brood from honey at a glance is the single most important read on the
    /// board, and in dark mode the two golds collapse into each other if this drifts.
    static let sealedBrood     = Color(.comb(dark: 0x8C6733, light: 0x8A6A2E))
    /// Open brood — pearl-white larvae in royal jelly, read cooler than stores.
    static let openBrood       = Color(.comb(dark: 0xE2DCCA, light: 0xF2EFE4))
    /// Stores — honey and pollen. Bright and yellow, never brown.
    static let stores          = Color(.comb(dark: 0xD9A945, light: 0xD9AE55))
    /// Drawn comb with nothing in it.
    static let drawnComb       = Color(.comb(dark: 0x4A463C, light: 0xC4C2B6))
    /// Bare foundation — not yet drawn, so it holds nothing.
    static let foundation      = Color(.comb(dark: 0x2C2A24, light: 0xCBCAC3))

    // MARK: Structure

    static let hairline        = Color(.comb(dark: 0xEFEEE9, light: 0x241F16,
                                             darkAlpha: 0.14, lightAlpha: 0.12))
    static let hairlineStrong  = Color(.comb(dark: 0xEFEEE9, light: 0x241F16,
                                             darkAlpha: 0.26, lightAlpha: 0.22))
    /// The hex lattice showing through behind elevated content — comb, faintly.
    static let lattice         = Color(.comb(dark: 0xEFEEE9, light: 0x241F16,
                                             darkAlpha: 0.07, lightAlpha: 0.06))
    /// Woodwork of the boxes.
    static let timber          = Color(.comb(dark: 0x332F27, light: 0xC7C4B9))
}

// MARK: - Risk state → colour + word (accessibility: never colour alone)

enum RiskState: String, Codable, CaseIterable {
    case calm
    case watch
    case imminent

    /// The word. Always rendered next to the colour (§9, §10.5).
    var word: String {
        switch self {
        case .calm: return "CALM"
        case .watch: return "WATCH"
        case .imminent: return "IMMINENT"
        }
    }

    var tint: Color {
        switch self {
        case .calm: return Palette.calm
        case .watch: return Palette.watch
        case .imminent: return Palette.imminent
        }
    }

    /// Ink that stays legible on `tint`.
    var onTint: Color {
        switch self {
        case .calm, .imminent: return Color(.comb(dark: 0xF4F2EC, light: 0xF7F5EF))
        case .watch: return Palette.onAccent
        }
    }

    /// Sort order for the inspection queue — worst first.
    var urgency: Int {
        switch self {
        case .imminent: return 0
        case .watch: return 1
        case .calm: return 2
        }
    }
}
