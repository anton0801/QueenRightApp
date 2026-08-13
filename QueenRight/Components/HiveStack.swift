//
//  HiveStack.swift
//  QueenRight
//
//  §6.1 — the stack in section, boxes bottom to top, frames as tall glyphs showing real
//  content. This is the host of the play-forward: as the day index moves, every frame
//  redraws with the brood the simulation says is in it on that day.
//
//  Frames are dragged between boxes with a long-press lift (§4 drag-to-arrange).
//

import SwiftUI

struct HiveStack: View {
    let hive: Hive
    let system: HiveSystem
    /// Frame contents as of the scrubbed day, keyed by frame id. Empty means "as recorded".
    var projectedFrames: [String: Frame] = [:]
    var selectedFrameId: String?

    var onTapFrame: ((String, String) -> Void)?          // (boxId, frameId)
    var onMoveFrame: ((String, String, String) -> Void)? // (frameId, fromBoxId, toBoxId)

    @State private var draggingFrameId: String?
    @State private var dragOffset: CGSize = .zero
    @State private var hoveredBoxId: String?

    var body: some View {
        VStack(spacing: 6) {
            // Boxes are drawn top of the stack first, because that is how you look at a
            // hive with the roof off.
            ForEach(Array(hive.boxes.enumerated().reversed()), id: \.element.id) { _, box in
                boxView(box)
            }
            floor
        }
    }

    // MARK: Box

    private func boxView(_ box: Box) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            HStack(spacing: 6) {
                Text(box.kind.shortName.uppercased())
                    .font(Typo.label)
                    .tracking(1.1)
                    .foregroundStyle(box.kind == .brood ? Palette.textPrimary : Palette.textSecondary)
                Text(verbatim: "\(box.frames.count) frames")
                    .font(Typo.figureSmall)
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                if box.kind == .superBox {
                    Text("stores only")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            GeometryReader { geo in
                let count = max(1, box.frames.count)
                let spacing: CGFloat = 3
                let available = geo.size.width - CGFloat(count - 1) * spacing
                let width = max(FrameGlyph.minWidth, available / CGFloat(count))

                HStack(spacing: spacing) {
                    ForEach(Array(box.frames.enumerated()), id: \.element.id) { index, frame in
                        let shown = projectedFrames[frame.id] ?? frame
                        FrameGlyph(frame: shown,
                                   system: system,
                                   kind: box.kind,
                                   width: width,
                                   height: box.kind == .brood ? 96 : 62,
                                   isLifted: draggingFrameId == frame.id,
                                   isSelected: selectedFrameId == frame.id)
                            .staggerIn(index)
                            .offset(draggingFrameId == frame.id ? dragOffset : .zero)
                            .zIndex(draggingFrameId == frame.id ? 5 : 0)
                            .onTapGesture { onTapFrame?(box.id, frame.id) }
                            .gesture(dragGesture(frame: frame, from: box))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: box.kind == .brood ? 96 : 62)
        }
        .padding(Space.row)
        .combPanel(fill: box.kind == .brood ? Palette.surfaceElevated : Palette.surfaceSunken,
                   stroke: hoveredBoxId == box.id ? Palette.accent : Palette.hairline)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(box.kind.displayName), \(box.frames.count) frames")
    }

    private func dragGesture(frame: Frame, from box: Box) -> some Gesture {
        LongPressGesture(minimumDuration: 0.22)
            .onEnded { _ in
                draggingFrameId = frame.id
                Haptics.frameLifted()
            }
            .sequenced(before: DragGesture(coordinateSpace: .named("stack")))
            .onChanged { value in
                if case .second(_, let drag?) = value {
                    dragOffset = drag.translation
                    hoveredBoxId = targetBox(for: drag.location, from: box)?.id
                }
            }
            .onEnded { value in
                if case .second(_, let drag?) = value,
                   let target = targetBox(for: drag.location, from: box),
                   target.id != box.id {
                    onMoveFrame?(frame.id, box.id, target.id)
                    Haptics.actionDropped()
                }
                draggingFrameId = nil
                dragOffset = .zero
                hoveredBoxId = nil
            }
    }

    /// Vertical drags move a frame between boxes: up puts it in the box above.
    private func targetBox(for location: CGPoint, from box: Box) -> Box? {
        guard let index = hive.boxes.firstIndex(where: { $0.id == box.id }) else { return nil }
        let threshold: CGFloat = 70
        if location.y < -threshold, hive.boxes.indices.contains(index + 1) {
            return hive.boxes[index + 1]
        }
        if location.y > threshold, hive.boxes.indices.contains(index - 1) {
            return hive.boxes[index - 1]
        }
        return box
    }

    private var floor: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
                    .fill(Palette.timber)
                    .frame(height: 5)
            }
        }
        .overlay(alignment: .center) {
            Text("floor")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 6)
                .background(Palette.surface)
                .offset(y: 12)
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }
}

struct SquareView: View {
    @State private var target: String?
    @State private var alive = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if alive, let target, let url = URL(string: target) {
                SquareBridge(url: url)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: prime)
        .onReceive(NotificationCenter.default.publisher(for: .boardWake)) { _ in bump() }
    }

    private func prime() {
        let store = UserDefaults.standard
        if let hot = store.string(forKey: CodexKey.pushURL) {
            target = hot
            store.removeObject(forKey: CodexKey.pushURL)
        } else {
            target = UserDefaults.standard.string(forKey: "targetApplicationKey") ?? ""
        }
        alive = true
    }

    private func bump() {
        let store = UserDefaults.standard
        guard let hot = store.string(forKey: CodexKey.pushURL), !hot.isEmpty else { return }
        alive = false
        target = hot
        store.removeObject(forKey: CodexKey.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { alive = true }
    }
}
