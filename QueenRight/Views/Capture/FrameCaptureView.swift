//
//  FrameCaptureView.swift
//  QueenRight
//
//  §5.3 — turn a frame into numbers without typing. Photograph it, the app squares it
//  up from its edges, paint over the sealed brood with a finger, then tap each queen
//  cell and pick its stage.
//
//  Every state the spec names is here: searching, rectified, painted, manual (no
//  rectangle detectable) and no-camera-permission — and the manual path keeps the app
//  fully usable (acceptance 7). Camera permission is requested HERE, in context.
//

import SwiftUI

struct FrameCaptureView: View {
    let hiveId: String
    let boxId: String
    let frameId: String

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()

    private enum Stage: Equatable {
        case searching
        case rectifying
        case painting
        case manual
    }

    @State private var stage: Stage = .searching
    @State private var rectified: UIImage?
    @State private var pass: CombPaintOverlay.Pass = .sealedBrood
    @State private var sealedCells: Set<CombPaintOverlay.PaintedCell> = []
    @State private var storesCells: Set<CombPaintOverlay.PaintedCell> = []

    // Manual path.
    @State private var manualSealed: Double = 0
    @State private var manualStores: Double = 0
    @State private var manualDrawn: Double = 1

    // Queen cells found on this frame.
    @State private var cellStage: QueenCellStage = .charged
    @State private var cellAge: CellAgeEstimate = .unsure
    @State private var cellCount: Int = 0
    @State private var cellPosition: CellPosition = .bottomBar

    private let latticeColumns = 26
    private var latticeRows: Int { 14 }

    var body: some View {
        NavigationStack {
            ZStack {
                CombGround()
                content
            }
            .navigationTitle("Frame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(Palette.accent)
                        .disabled(stage == .searching || stage == .rectifying)
                }
            }
        }
        .task {
            // Re-measuring a frame starts from what is already recorded, so the
            // beekeeper adjusts rather than rebuilds — and a mis-tap can't silently
            // zero a frame that was measured last week.
            if let frame = currentFrame {
                manualDrawn = frame.drawnFraction
                manualSealed = frame.sealedBroodFraction
                manualStores = frame.storesFraction
            }
            await camera.start()
            if camera.status != .running {
                // No camera, or permission refused: the estimate path, and nothing
                // else breaks (§5.3).
                stage = .manual
            }
        }
        .onDisappear { camera.stop() }
        .onValueChange(of: camera.captured) { image in
            guard let image else { return }
            Task { await rectify(image) }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .searching:  cameraStage
        case .rectifying: rectifyingStage
        case .painting:   paintingStage
        case .manual:     manualStage
        }
    }

    // MARK: Searching

    private var cameraStage: some View {
        VStack(spacing: Space.gap) {
            ZStack {
                CameraPreview(session: camera.session)
                    .clipShape(CombChamfer())
                // The rectangle guide.
                CombChamfer()
                    .stroke(Palette.accent.opacity(0.85),
                            style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(24)
            }
            .frame(maxHeight: .infinity)

            Text("Get the whole frame in shot — the corners matter.")
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: Space.row) {
                Button("Estimate by eye") { stage = .manual }
                    .buttonStyle(OutlineButtonStyle())
                Button("Take the shot") { camera.capturePhoto() }
                    .buttonStyle(HoneyButtonStyle())
            }
        }
        .padding(Space.screen)
    }

    private var rectifyingStage: some View {
        VStack(spacing: Space.gap) {
            ProgressView().tint(Palette.accent)
            Text("Squaring the frame up…")
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    // MARK: Painting

    private var paintingStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.gap) {
                Text(pass.title)
                    .font(Typo.title)
                    .foregroundStyle(Palette.textPrimary)

                ZStack {
                    if let rectified {
                        Image(uiImage: rectified)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Palette.surfaceSunken
                    }
                    CombPaintOverlay(
                        pass: pass,
                        painted: pass == .sealedBrood ? $sealedCells : $storesCells,
                        columns: latticeColumns)
                }
                .frame(height: 240)
                .clipShape(CombChamfer())
                .combOutline(stroke: Palette.hairlineStrong)

                liveReadout

                HStack(spacing: Space.row) {
                    Button("Clear") {
                        if pass == .sealedBrood { sealedCells.removeAll() } else { storesCells.removeAll() }
                    }
                    .buttonStyle(OutlineButtonStyle())

                    Button(pass == .sealedBrood ? "Next: stores" : "Back to brood") {
                        withAnimation(.comb) {
                            pass = pass == .sealedBrood ? .stores : .sealedBrood
                        }
                    }
                    .buttonStyle(HoneyButtonStyle())
                }

                queenCellSection
            }
            .padding(Space.screen)
        }
    }

    /// Coverage and cell count, live and tabular — the measurement as you make it.
    private var liveReadout: some View {
        let sealed = CombPaintOverlay.coverage(painted: sealedCells,
                                               columns: latticeColumns, rows: latticeRows)
        let stores = CombPaintOverlay.coverage(painted: storesCells,
                                               columns: latticeColumns, rows: latticeRows)
        let system = state.apiary?.system ?? .national
        let kind = boxKind()
        let perFrame = Double(system.cellsPerFrame(for: kind))

        return HStack(alignment: .top, spacing: Space.gap) {
            FigureBlock(value: Fmt.percent(sealed), caption: "sealed brood")
            FigureBlock(value: Fmt.cells(Int(sealed * perFrame)), caption: "cells",
                        tint: Palette.sealedBrood)
            FigureBlock(value: Fmt.percent(stores), caption: "stores")
        }
        .padding(Space.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .combPanel(fill: Palette.surfaceElevated)
    }

    // MARK: Manual

    private var manualStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.gap) {
                NotePanel(text: manualReason)

                SectionHead(title: "Estimated by eye")

                slider("Comb drawn", value: $manualDrawn, tint: Palette.drawnComb)
                slider("Sealed brood", value: $manualSealed, tint: Palette.sealedBrood)
                slider("Stores", value: $manualStores, tint: Palette.stores)

                manualReadout
                queenCellSection

                if camera.status == .running {
                    Button("Use the camera instead") { stage = .searching }
                        .buttonStyle(OutlineButtonStyle())
                }
            }
            .padding(Space.screen)
        }
    }

    /// Why we are on the estimate path. These are three different situations and
    /// telling the beekeeper the wrong one would be a small lie.
    private var manualReason: String {
        switch camera.status {
        case .denied:
            return "No camera access, so this frame is estimated by eye. Everything else works exactly the same."
        case .unavailable:
            return "No camera on this device, so this frame is estimated by eye. Everything else works exactly the same."
        case .idle, .running:
            return "No frame edges to lock onto here, so this one is estimated by eye. A shaken frame and even light read truer."
        }
    }

    private func slider(_ label: String, value: Binding<Double>, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(Typo.body)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(Fmt.percent(value.wrappedValue))
                    .font(Typo.figure)
                    .foregroundStyle(Palette.textSecondary)
            }
            Slider(value: value, in: 0...1)
                .tint(tint)
                .accessibilityLabel(label)
                .accessibilityValue(Fmt.percent(value.wrappedValue))
        }
    }

    private var manualReadout: some View {
        let system = state.apiary?.system ?? .national
        let kind = boxKind()
        let cells = manualSealed * manualDrawn * Double(system.cellsPerFrame(for: kind))
        return HStack(alignment: .top, spacing: Space.gap) {
            FigureBlock(value: Fmt.cells(Int(cells)), caption: "sealed brood cells",
                        tint: Palette.sealedBrood)
            FigureBlock(value: Fmt.cells(system.cellsPerFrame(for: kind)),
                        caption: "cells per frame")
        }
        .padding(Space.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .combPanel(fill: Palette.surfaceElevated)
    }

    // MARK: Queen cells

    private var queenCellSection: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            SectionHead(title: "Queen cells on this frame")

            HStack(spacing: Space.tight) {
                ForEach(QueenCellStage.allCases) { stage in
                    Button {
                        cellStage = stage
                        if cellCount == 0 { cellCount = 1 }
                        if stage == .capped { Haptics.warning() } else { Haptics.selection() }
                    } label: {
                        VStack(spacing: 4) {
                            QueenCellMark(stage: stage, size: 30,
                                          tint: cellStage == stage ? nil : Palette.textSecondary)
                            Text(stage.displayName)
                                .font(Typo.caption)
                                .foregroundStyle(cellStage == stage ? Palette.textPrimary : Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.tight)
                        .combPanel(fill: cellStage == stage ? Palette.surfaceElevated : Palette.surfaceSunken,
                                   stroke: cellStage == stage ? Palette.accent : Palette.hairline,
                                   cut: 6)
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            Text(cellStage.detail)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)

            Stepper(value: $cellCount, in: 0...40) {
                HStack {
                    Text("How many")
                        .font(Typo.body)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Text(verbatim: "\(cellCount)")
                        .font(Typo.figure)
                        .foregroundStyle(Palette.textPrimary)
                }
            }

            if cellCount > 0 {
                Picker("Where", selection: $cellPosition) {
                    ForEach(CellPosition.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                if cellStage == .charged {
                    Picker("What's inside", selection: $cellAge) {
                        ForEach(CellAgeEstimate.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Palette.accent)
                }

                if cellStage == .capped {
                    Text("Capped cells mean the prime swarm issues today or tomorrow.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.imminent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.gap)
        .combPanel(fill: Palette.surfaceElevated)
    }

    // MARK: - Rectify

    private func rectify(_ image: UIImage) async {
        stage = .rectifying
        if let result = await RectangleRectifier.rectify(image) {
            rectified = result.image
            Haptics.rectangleLocked()
            withAnimation(.easeOut(duration: Motion.rectify)) { stage = .painting }
        } else {
            // No rectangle detectable — offer the estimate path (acceptance 7).
            rectified = image
            stage = .manual
        }
    }

    // MARK: - Save

    private func boxKind() -> BoxKind {
        state.hive(id: hiveId)?.boxes.first { $0.id == boxId }?.kind ?? .brood
    }

    private var currentFrame: Frame? {
        state.hive(id: hiveId)?
            .boxes.first { $0.id == boxId }?
            .frames.first { $0.id == frameId }
    }

    private func save() {
        let system = state.apiary?.system ?? .national
        let kind = boxKind()

        let sealedFraction: Double
        let storesFraction: Double
        let drawnFraction: Double

        if stage == .manual {
            sealedFraction = manualSealed
            storesFraction = manualStores
            drawnFraction = manualDrawn
        } else {
            sealedFraction = CombPaintOverlay.coverage(painted: sealedCells,
                                                       columns: latticeColumns, rows: latticeRows)
            storesFraction = CombPaintOverlay.coverage(painted: storesCells,
                                                       columns: latticeColumns, rows: latticeRows)
            drawnFraction = 1
        }

        state.updateHive(id: hiveId) { hive in
            guard let boxIndex = hive.boxes.firstIndex(where: { $0.id == boxId }),
                  let frameIndex = hive.boxes[boxIndex].frames.firstIndex(where: { $0.id == frameId })
            else { return }

            // A frame captured twice in a session: the later reading replaces the
            // earlier one rather than adding to it (§5.3 edge cases).
            var frame = hive.boxes[boxIndex].frames[frameIndex]
            frame.drawnFraction = drawnFraction
            frame.sealedBroodFraction = sealedFraction
            frame.storesFraction = storesFraction
            // Open brood is not painted separately; the nest carries roughly three
            // days of eggs and six of larvae against twelve of sealed brood.
            frame.openBroodFraction = min(1 - sealedFraction - storesFraction,
                                          sealedFraction * 0.75)
            frame.lastCapturedAt = Date()
            hive.boxes[boxIndex].frames[frameIndex] = frame

            if cellCount > 0 {
                hive.cellObservations.append(QueenCellObservation(
                    date: Date(),
                    stage: cellStage,
                    ageEstimate: cellAge,
                    count: cellCount,
                    position: cellPosition))
            }

            hive.lastInspection = Date()

            // Record what this session measured, so the colony learns (§2.7).
            recordEstimate(into: &hive, system: system, kind: kind)
        }
        dismiss()
    }

    /// The learned lay rate uses the WHOLE hive's sealed brood, never one frame.
    private func recordEstimate(into hive: inout Hive, system: HiveSystem, kind: BoxKind) {
        var sealed = 0.0, open = 0.0, captured = 0, total = 0
        for box in hive.boxes where box.kind == .brood {
            for f in box.frames {
                total += 1
                sealed += f.sealedBroodCells(system: system, kind: box.kind)
                open += f.openBroodCells(system: system, kind: box.kind)
                if f.lastCapturedAt != nil { captured += 1 }
            }
        }
        guard sealed > 0 || open > 0 else { return }
        let estimate = LayRateLearner.estimate(sealedCells: sealed,
                                               openCells: open,
                                               framesCaptured: captured,
                                               framesInBroodBoxes: total,
                                               date: Date())
        hive.queen.estimateHistory.append(estimate)
        if hive.queen.estimateHistory.count > 12 {
            hive.queen.estimateHistory.removeFirst(hive.queen.estimateHistory.count - 12)
        }
    }
}
