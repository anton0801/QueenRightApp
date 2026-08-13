//
//  Interactions.swift
//  QueenRight
//
//  Shared control styles and section furniture used across all five screens.
//  Elevation is flat fills + 1px hairlines + a hairline hex outline behind elevated
//  content. No shadows, no translucency anywhere (§3).
//

import SwiftUI

// MARK: - Button styles

struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.combPress, value: configuration.isPressed)
    }
}

/// The one honey CTA.
struct HoneyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.bodyMedium)
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(CombChamfer().fill(isEnabled ? Palette.accent : Palette.accentMuted))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.combPress, value: configuration.isPressed)
    }
}

/// A quieter outlined action.
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.bodyMedium)
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(CombChamfer().fill(Palette.surfaceElevated))
            .overlay(CombChamfer().stroke(Palette.hairlineStrong, lineWidth: 1))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.combPress, value: configuration.isPressed)
    }
}

// MARK: - Section furniture

/// A ruled section head on the hex ground (§5.5).
struct SectionHead: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(Typo.label)
                .tracking(1.2)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: Space.tight)
            if let trailing {
                Text(trailing)
                    .font(Typo.figureSmall)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.bottom, Space.tight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// A labelled figure: the number in tabular serif, its unit spelled out beneath.
struct FigureBlock: View {
    let value: String
    let caption: String
    var tint: Color = Palette.textPrimary
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(value)
                .font(Typo.figureLarge)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(caption)")
    }
}

/// The house screen background: smoke with the comb showing faintly through.
struct CombGround: View {
    var body: some View {
        ZStack {
            Palette.surface
            HexLatticeView(cellWidth: 26)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Risk chip — colour ALWAYS carries its word (§9, §10.5)

struct RiskChip: View {
    let state: RiskState
    /// Overrides the word when the state alone would mislead — a queenless colony
    /// reads QUEENLESS, not CALM.
    var label: String?
    var compact: Bool = false

    private var word: String { label ?? state.word }

    var body: some View {
        Text(word)
            .font(Typo.label)
            .tracking(1.1)
            .foregroundStyle(state.onTint)
            .padding(.horizontal, compact ? 6 : 9)
            .padding(.vertical, compact ? 3 : 5)
            .background(CombChamfer(cut: 5).fill(state.tint))
            .accessibilityLabel(word.lowercased())
    }
}

/// A plain sentence panel — used for the disease note and every honest caveat.
struct NotePanel: View {
    let text: String
    var tint: Color = Palette.textSecondary

    var body: some View {
        Text(text)
            .font(Typo.caption)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.row)
            .combPanel(fill: Palette.surfaceSunken)
    }
}
