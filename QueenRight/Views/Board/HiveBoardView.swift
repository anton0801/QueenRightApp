//
//  HiveBoardView.swift
//  QueenRight
//
//  §5.2 — the board IS the projection. The stack in section above, the swarm window in
//  serif display at the top, the time scrub underneath, and the action tray at the
//  bottom edge. Change anything and the board replays the affected days.
//

import SwiftUI

struct HiveBoardView: View {
    let hiveId: String

    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var dayIndex = 0
    @State private var didSetInitialDay = false
    @State private var captureTarget: CaptureTarget?
    @State private var pendingAction: Intervention?
    @State private var showCelebration = false
    @State private var recordingSwarm = false

    struct CaptureTarget: Identifiable {
        let boxId: String
        let frameId: String
        var id: String { frameId }
    }

    private var hive: Hive? { state.hive(id: hiveId) }

    var body: some View {
        ZStack {
            CombGround()

            if let hive {
                let projection = state.projection(for: hive)
                board(hive: hive, projection: projection)

                if showCelebration {
                    SwarmAvertedOverlay()
                        .transition(.opacity)
                        .zIndex(20)
                }
            } else {
                Text("This hive is no longer here.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .navigationTitle(hive?.name ?? "Hive")
        .navigationBarTitleDisplayMode(.inline)
        .coordinateSpace(name: "stack")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("It swarmed", role: .destructive) { recordingSwarm = true }
                    if hive?.queenlessSince != nil {
                        Button("A queen is laying again") { clearQueenless() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Palette.textPrimary)
                }
                .accessibilityLabel("Hive options")
            }
        }
        .confirmationDialog("Record a swarm from this colony?",
                            isPresented: $recordingSwarm, titleVisibility: .visible) {
            Button("Yes, and cells were left behind", role: .destructive) { recordSwarm(cellsLeft: true) }
            Button("Yes, no cells left", role: .destructive) { recordSwarm(cellsLeft: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("What this app predicted beforehand is kept alongside it. A model you can't audit is one you shouldn't trust.")
        }
        .fullScreenCover(item: $captureTarget) { target in
            FrameCaptureView(hiveId: hiveId, boxId: target.boxId, frameId: target.frameId)
        }
        .sheet(item: $pendingAction) { action in
            ActionSheetView(hiveId: hiveId, action: action)
        }
        .onValueChange(of: state.celebrateHiveId) { newValue in
            guard newValue == hiveId else { return }
            withAnimation(.comb) { showCelebration = true }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(Motion.celebration * 1_000_000_000))
                withAnimation(.comb) { showCelebration = false }
                state.celebrateHiveId = nil
            }
        }
    }

    // MARK: - Board

    private func board(hive: Hive, projection: SwarmProjection) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.gap) {
                    SwarmClockHeader(projection: projection, hiveName: hive.name)

                    if projection.days.isEmpty {
                        EmptyView()
                    } else {
                        HiveStack(hive: hive,
                                  system: state.apiary?.system ?? .national,
                                  projectedFrames: projectedFrames(hive: hive, projection: projection),
                                  onTapFrame: { boxId, frameId in
                                      captureTarget = CaptureTarget(boxId: boxId, frameId: frameId)
                                  },
                                  onMoveFrame: { frameId, from, to in
                                      moveFrame(frameId, from: from, to: to)
                                  })

                        TimeScrub(projection: projection, dayIndex: $dayIndex)
                    }

                    spaceReadout(projection: projection)

                    if !hive.liveCellObservations().isEmpty {
                        cellPanel(hive: hive)
                    }

                    if !hive.swarmEvents.isEmpty {
                        swarmHistory(hive: hive)
                    }

                    // §15 — this app models swarming, it does not diagnose disease.
                    NotePanel(text: AppInfo.diseaseNote)
                }
                .padding(Space.screen)
            }
            // A safe-area inset rather than an overlay: SwiftUI then insets the scroll
            // content by whatever the tray actually measures, so the tray never covers
            // the scrub panel at large Dynamic Type sizes.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ActionTray(state: projection.riskState) { action in
                    pendingAction = action
                }
            }
        }
        .onAppear {
            guard !didSetInitialDay else { return }
            dayIndex = projection.todayIndex
            didSetInitialDay = true
        }
    }

    /// The frames as the simulation says they stand on the scrubbed day. This is the
    /// play-forward: brood fills and empties as eggs become capped brood and emerge.
    private func projectedFrames(hive: Hive, projection: SwarmProjection) -> [String: Frame] {
        guard let day = projection.days[safe: dayIndex],
              dayIndex != projection.todayIndex else { return [:] }

        let system = state.apiary?.system ?? .national
        let broodBoxes = hive.boxes.filter { $0.kind == .brood }
        let capacity = broodBoxes.reduce(0.0) { total, box in
            total + box.frames.reduce(0.0) { $0 + $1.capacity(system: system, kind: box.kind) }
        }
        guard capacity > 0 else { return [:] }

        // Spread the day's brood across the brood-box frames in the order the nest
        // actually grows: outward from the middle of the box.
        let sealedShare = day.sealedBroodCells / capacity
        let openShare = day.openBroodCells / capacity

        var out: [String: Frame] = [:]
        for box in broodBoxes {
            let middle = Double(box.frames.count - 1) / 2
            for (index, frame) in box.frames.enumerated() {
                guard frame.drawnFraction > 0.15 else { continue }
                // Frames nearer the centre of the nest carry proportionally more brood.
                let distance = abs(Double(index) - middle) / max(1, middle)
                let weight = (1.35 - distance * 0.7).clamped(to: 0...1.35)
                var projected = frame
                projected.sealedBroodFraction = (sealedShare * weight).clamped(to: 0...1)
                projected.openBroodFraction = (openShare * weight).clamped(to: 0...(1 - projected.sealedBroodFraction))
                out[frame.id] = projected
            }
        }
        return out
    }

    // MARK: - Space readout, in cells (§10.5)

    private func spaceReadout(projection: SwarmProjection) -> some View {
        let day = projection.days[safe: dayIndex]
        return VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: "Laying space")
            HStack(alignment: .top, spacing: Space.gap) {
                FigureBlock(value: Fmt.cells(Int(day?.openCells ?? 0)),
                            caption: "cells to lay in")
                FigureBlock(value: Fmt.cells(Int(day?.eggsLaid ?? 0)),
                            caption: "eggs laid that day")
                FigureBlock(value: Fmt.percent(day?.spacePressure ?? 0),
                            caption: "space pressure",
                            tint: (day?.spacePressure ?? 0) >= RiskWeights.congestedSpacePressure
                                ? Palette.watch : Palette.textPrimary)
            }
            if (day?.spacePressure ?? 0) >= RiskWeights.congestedSpacePressure {
                Text("Past 75% the colony is congested — this is the condition queen cells get built in.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.gap)
        .combPanel(fill: Palette.surfaceElevated)
    }

    // MARK: - Cells seen

    private func cellPanel(hive: Hive) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: "Queen cells seen")
            ForEach(hive.liveCellObservations()) { obs in
                HStack(spacing: Space.row) {
                    QueenCellMark(stage: obs.stage, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "\(obs.count) × \(obs.stage.displayName.lowercased())")
                            .font(Typo.bodyMedium)
                            .foregroundStyle(Palette.textPrimary)
                        Text("\(obs.position.displayName), seen \(Fmt.day(obs.date))")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    if obs.looksLikeSupersedure {
                        Text("supersedure")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.gap)
        .combPanel(fill: Palette.surfaceElevated)
    }

    // MARK: - History (§10.7 — the projection stays visible after a swarm)

    private func swarmHistory(hive: Hive) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: "This colony swarmed")
            ForEach(hive.swarmEvents.sorted { $0.date > $1.date }) { event in
                VStack(alignment: .leading, spacing: 3) {
                    Text(Fmt.day(event.date))
                        .font(Typo.bodyMedium)
                        .foregroundStyle(Palette.textPrimary)
                    if let prior = event.priorProjection {
                        Text("Beforehand this app said: \(prior.stateWord.lowercased()) — \(prior.note)")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No projection was recorded before this one.")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.gap)
        .combPanel(fill: Palette.surfaceElevated)
    }

    // MARK: - Recording a swarm (§10.7, acceptance 12)

    /// The projection is archived BEFORE the record changes, so what the model said
    /// beforehand survives and stays visible in this hive's history.
    private func recordSwarm(cellsLeft: Bool) {
        guard let hive else { return }
        let projection = state.projection(for: hive)

        let archived = ArchivedProjection(
            recordedAt: Date(),
            stateWord: projection.chipLabel,
            windowStart: projection.window?.lowerBound,
            windowEnd: projection.window?.upperBound,
            note: projection.reason)

        state.updateHive(id: hiveId) { hive in
            hive.archivedProjections.append(archived)
            hive.swarmEvents.append(SwarmEvent(
                date: Date(),
                priorProjection: archived,
                cappedCellsRemaining: cellsLeft ? 1 : 0))
            // The prime swarm takes the laying queen with it.
            hive.queenlessSince = Calendar.current.startOfDay(for: Date())
            hive.cellObservations = []
            hive.cellsCutAt = nil
            hive.lastInspection = Date()
        }
        Haptics.warning()
    }

    /// The virgin mated and is laying — the queenless clock stops.
    private func clearQueenless() {
        state.updateHive(id: hiveId) { hive in
            hive.queenlessSince = nil
            hive.queen = Queen(introducedYear: Calendar.current.component(.year, from: Date()),
                               markColour: QueenMark.forYear(Calendar.current.component(.year, from: Date())))
            hive.lastInspection = Date()
        }
        Haptics.selection()
    }

    // MARK: - Moving frames

    private func moveFrame(_ frameId: String, from: String, to: String) {
        state.updateHive(id: hiveId) { hive in
            guard let fromIndex = hive.boxes.firstIndex(where: { $0.id == from }),
                  let toIndex = hive.boxes.firstIndex(where: { $0.id == to }),
                  let frameIndex = hive.boxes[fromIndex].frames.firstIndex(where: { $0.id == frameId })
            else { return }
            let frame = hive.boxes[fromIndex].frames.remove(at: frameIndex)
            hive.boxes[toIndex].frames.append(frame)
        }
        // Re-read rather than force-unwrapping the captured hive: it can be gone if the
        // record changed underneath the gesture.
        guard let updated = state.hive(id: hiveId) else { return }
        dayIndex = state.projection(for: updated).todayIndex
    }
}

// MARK: - The single celebration (§3)

/// A honey pulse travelling once across the lattice. This fires ONLY on
/// imminent → calm, and in a normal season two or three times a year.
struct SwarmAvertedOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = -0.4

    var body: some View {
        ZStack {
            if !reduceMotion {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Palette.accent.opacity(0.55), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: sweep * geo.size.width * 1.8)
                        .blendMode(.plusLighter)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            Text("SWARM AVERTED")
                .font(Typo.label)
                .tracking(2)
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(CombChamfer(cut: 7).fill(Palette.accent))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: Motion.celebration)) { sweep = 1.0 }
        }
        .accessibilityLabel("Swarm averted")
    }
}
