//
//  TimeScrub.swift
//  QueenRight
//
//  §6.4 — the day-by-day transport under the board. Drag it and the board plays
//  forward: frames fill and empty with brood colour as eggs become capped brood and
//  capped brood emerges, and the population counts alongside.
//
//  Reduce Motion replaces the play-forward with a plain jump-to-day slider (§9,
//  acceptance 16) — same information, no travel.
//

import SwiftUI

struct TimeScrub: View {
    let projection: SwarmProjection
    @Binding var dayIndex: Int
    /// Fires when the user starts moving so the board can stop animating incidentally.
    var onScrubStart: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlaying = false
    @State private var playTask: Task<Void, Never>?

    private var count: Int { max(1, projection.days.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            header

            if reduceMotion {
                reducedSlider
            } else {
                track
            }

            legend
        }
        .padding(Space.gap)
        .combPanel(fill: Palette.surfaceElevated)
        .onDisappear { stopPlaying() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            let day = projection.days[safe: dayIndex]
            VStack(alignment: .leading, spacing: 0) {
                Text(dayLabel)
                    .font(Typo.titleSm)
                    .foregroundStyle(Palette.textPrimary)
                if let day {
                    Text("\(Fmt.cells(Int(day.adults))) bees · \(Fmt.cells(Int(day.openCells))) cells to lay in")
                        .font(Typo.figureSmall)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            if !reduceMotion {
                Button {
                    isPlaying ? stopPlaying() : startPlaying()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 34, height: 34)
                        .background(CombChamfer(cut: 6).fill(Palette.accent))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(isPlaying ? "Pause the projection" : "Play the projection forward")
            }
        }
    }

    private var dayLabel: String {
        guard let day = projection.days[safe: dayIndex] else { return "" }
        let delta = dayIndex - projection.todayIndex
        if delta == 0 { return "Today" }
        if delta < 0 { return "\(Fmt.days(-delta)) ago · \(Fmt.day(day.date))" }
        return "In \(Fmt.days(delta)) · \(Fmt.day(day.date))"
    }

    // MARK: Track

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                // The risk ribbon: the shape of the season ahead, at a glance.
                Canvas { context, size in
                    guard count > 1 else { return }
                    let step = size.width / CGFloat(count - 1)
                    for (i, day) in projection.days.enumerated() {
                        let x = CGFloat(i) * step
                        let h = size.height * CGFloat(day.spacePressure.clamped(to: 0...1))
                        let bar = Path(CGRect(x: x, y: size.height - h,
                                              width: max(1, step * 0.85), height: h))
                        let past = i < projection.todayIndex
                        context.fill(bar, with: .color(
                            past ? Palette.hairlineStrong
                                 : Palette.accent.opacity(0.30 + 0.5 * day.risk)))
                    }
                }
                .frame(height: 34)

                // Today's mark.
                if count > 1 {
                    let todayX = w * CGFloat(projection.todayIndex) / CGFloat(count - 1)
                    Rectangle()
                        .fill(Palette.textSecondary)
                        .frame(width: 1, height: 40)
                        .offset(x: todayX)
                }

                // The handle.
                if count > 1 {
                    let x = w * CGFloat(dayIndex) / CGFloat(count - 1)
                    Rectangle()
                        .fill(Palette.textPrimary)
                        .frame(width: 2, height: 46)
                        .offset(x: x - 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        stopPlaying()
                        onScrubStart?()
                        let fraction = (value.location.x / max(1, w)).clamped(to: 0...1)
                        let target = Int((Double(count - 1) * fraction).rounded())
                        if target != dayIndex {
                            dayIndex = target
                            Haptics.selection()
                        }
                    }
            )
        }
        .frame(height: 46)
        .accessibilityElement()
        .accessibilityLabel("Day scrubber")
        .accessibilityValue(dayLabel)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: dayIndex = min(count - 1, dayIndex + 1)
            case .decrement: dayIndex = max(0, dayIndex - 1)
            default: break
            }
        }
    }

    /// Reduce Motion: a slider that jumps straight to the chosen day.
    private var reducedSlider: some View {
        Slider(
            value: Binding(
                get: { Double(dayIndex) },
                set: { dayIndex = Int($0.rounded()) }
            ),
            in: 0...Double(max(1, count - 1)),
            step: 1
        )
        .tint(Palette.accent)
        .accessibilityLabel("Jump to day")
        .accessibilityValue(dayLabel)
    }

    private var legend: some View {
        HStack(spacing: Space.row) {
            legendSwatch(Palette.sealedBrood, "Sealed brood")
            legendSwatch(Palette.openBrood, "Open brood")
            legendSwatch(Palette.stores, "Stores")
            Spacer()
        }
    }

    private func legendSwatch(_ colour: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            // Open brood is near-white, so every swatch carries a hairline or the
            // pale one vanishes into the panel.
            Hexagon().fill(colour)
                .overlay(Hexagon().stroke(Palette.hairlineStrong, lineWidth: 0.75))
                .frame(width: 10, height: 11)
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    // MARK: Play-forward

    private func startPlaying() {
        guard !reduceMotion else { return }
        stopPlaying()
        isPlaying = true
        if dayIndex >= count - 1 { dayIndex = projection.todayIndex }
        playTask = Task { @MainActor in
            while !Task.isCancelled && dayIndex < count - 1 {
                try? await Task.sleep(nanoseconds: UInt64(Motion.dayStep * 1_000_000_000))
                if Task.isCancelled { break }
                withAnimation(.combDay) { dayIndex += 1 }
            }
            isPlaying = false
        }
    }

    private func stopPlaying() {
        playTask?.cancel()
        playTask = nil
        isPlaying = false
    }
}
