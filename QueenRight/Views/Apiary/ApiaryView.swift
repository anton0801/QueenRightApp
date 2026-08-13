//
//  ApiaryView.swift
//  QueenRight
//
//  §5.1 — the hub. Which hive needs opening today. The site is drawn as a plan with
//  hives where you placed them, tinted by risk, days-since-inspection beneath. One line
//  across the top carries the apiary's forage state; the inspection queue sits below.
//
//  All five states are handled: empty, populated, all calm (quiet is VALID and must not
//  read as an error), stale, and out of season.
//

import SwiftUI

struct ApiaryView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var weatherService: WeatherService

    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var openHiveId: String?
    @State private var showingSettings = false
    @State private var showingAddHive = false
    /// Both columns from the start on iPad — the yard is the point of the layout.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        // iPad and landscape: the yard sits beside the board, so you can move between
        // hives without losing the one you are reading (§9).
        if sizeClass == .regular {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                yardColumn
            } detail: {
                if let openHiveId, state.hive(id: openHiveId) != nil {
                    HiveBoardView(hiveId: openHiveId)
                } else {
                    detailPlaceholder
                }
            }
            .navigationSplitViewStyle(.balanced)
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingAddHive) { AddHiveView() }
            .task {
                state.refreshWeather()
                // Land on the hive that most needs opening rather than an empty panel —
                // the whole point of the yard is that it already knows which one.
                if openHiveId == nil { openHiveId = state.inspectionQueue.first?.id }
            }
        } else {
            phoneStack
        }
    }

    /// The yard on its own, for the iPad's leading column.
    private var yardColumn: some View {
        ZStack {
            CombGround()
            if state.apiary == nil || state.hives.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    private var detailPlaceholder: some View {
        ZStack {
            CombGround()
            VStack(spacing: Space.tight) {
                Text("Pick a hive")
                    .font(Typo.display)
                    .foregroundStyle(Palette.textPrimary)
                Text("The board draws here.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var phoneStack: some View {
        NavigationStack {
            ZStack {
                CombGround()

                if state.apiary == nil || state.hives.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(forOptional: $openHiveId) { id in
                HiveBoardView(hiveId: id)
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingAddHive) { AddHiveView() }
            .task { state.refreshWeather() }
        }
    }

    /// Shared by the phone stack and the iPad's leading column.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Text(state.apiary?.name ?? AppInfo.name)
                .font(Typo.title)
                .foregroundStyle(Palette.textPrimary)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: Space.gap) {
                if state.apiary != nil {
                    Button { showingAddHive = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add a hive")
                }
                Button { showingSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Settings")
            }
            .foregroundStyle(Palette.textPrimary)
        }
    }

    // MARK: - Populated

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.gap) {
                FlowLine(text: weatherService.flowLineText(),
                         staleness: weatherService.stalenessText(),
                         isLoading: weatherService.isLoading)

                if state.isOutOfSeason {
                    outOfSeasonBanner
                } else if let summary = calmSummary {
                    NotePanel(text: summary)
                }

                yardPlan

                SectionHead(title: "Next to look at", trailing: "\(state.hives.count) hives")

                VStack(spacing: Space.tight) {
                    ForEach(Array(state.inspectionQueue.enumerated()), id: \.element.id) { index, hive in
                        queueRow(hive)
                            .staggerIn(index)
                    }
                }
            }
            .padding(Space.screen)
        }
        .refreshable { state.refreshWeather(force: true) }
    }

    /// Quiet is valid and must not read as an error (§5.1).
    private var calmSummary: String? {
        guard state.yardState == .calm, !state.hives.isEmpty else { return nil }
        guard let next = state.nextDue else { return "Nothing pressing." }
        let due = Calendar.current.date(byAdding: .day, value: 7, to: next.lastInspection) ?? Date()
        return "Nothing pressing. Next check due \(Fmt.weekday(due)) on \(next.name)."
    }

    private var outOfSeasonBanner: some View {
        let month = state.apiary.flatMap {
            SeasonWindow.nextSeasonMonthName(latitude: $0.latitude, from: Date())
        }
        return NotePanel(
            text: month.map { "Swarm season is over here. The clock is off until \($0)." }
                ?? "Swarm season is over here. The clock is off.",
            tint: Palette.textSecondary)
    }

    // MARK: - The yard plan

    private var yardPlan: some View {
        GeometryReader { geo in
            ZStack {
                HexLatticeView(cellWidth: 30, color: Palette.lattice)

                ForEach(nudgedPositions(in: geo.size), id: \.hive.id) { placed in
                    let projection = state.projection(for: placed.hive)
                    Button {
                        openHiveId = placed.hive.id
                    } label: {
                        HivePlanGlyph(hive: placed.hive,
                                      state: projection.riskState,
                                      daysSince: projection.daysSinceInspection,
                                      isBlind: projection.isBlind,
                                      isCompact: isCompactPlan(width: geo.size.width))
                    }
                    .buttonStyle(PressableStyle())
                    .position(placed.point)
                }
            }
        }
        .frame(height: state.hives.count > 8 ? 320 : 260)
        .combPanel(fill: Palette.surfaceSunken)
    }

    private struct PlacedHive {
        let hive: Hive
        let point: CGPoint
    }

    /// Two hives standing on the same spot are nudged apart so both stay tappable (§5.1).
    private func nudgedPositions(in size: CGSize) -> [PlacedHive] {
        var used: [CGPoint] = []
        // Everything scales off the container, so the plan stays legible in an iPad
        // sidebar as well as full width on a phone.
        let compact = isCompactPlan(width: size.width)
        let inset: CGFloat = compact ? 40 : 54
        let clearance: CGFloat = compact ? 78 : 88
        let stepX: CGFloat = compact ? 52 : 64
        let stepY: CGFloat = compact ? 62 : 70
        let w = max(1, size.width - inset * 2)
        let h = max(1, size.height - inset * 2)

        return state.hives.map { hive in
            var p = CGPoint(x: inset + w * hive.positionX,
                            y: inset + h * hive.positionY)
            var attempts = 0
            while used.contains(where: { hypot($0.x - p.x, $0.y - p.y) < clearance }) && attempts < 16 {
                p.x += stepX
                if p.x > size.width - inset {
                    p.x = inset
                    p.y += stepY
                }
                attempts += 1
            }
            used.append(p)
            return PlacedHive(hive: hive, point: p)
        }
    }

    /// A plan is compact when it is narrow or crowded — the glyphs shrink so the
    /// name and day count under each one never collide with its neighbour.
    private func isCompactPlan(width: CGFloat) -> Bool {
        width < 380 || state.hives.count > 8
    }

    // MARK: - Queue row

    private func queueRow(_ hive: Hive) -> some View {
        let projection = state.projection(for: hive)
        return Button {
            openHiveId = hive.id
        } label: {
            HStack(spacing: Space.row) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(hive.name)
                            .font(Typo.titleSm)
                            .foregroundStyle(Palette.textPrimary)
                        RiskChip(state: projection.riskState, label: projection.chipLabel, compact: true)
                        if projection.isBlind {
                            Text("BLIND")
                                .font(Typo.label)
                                .tracking(1)
                                .foregroundStyle(Palette.watch)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .combOutline(stroke: Palette.watch, cut: 4, dash: [2.5, 2.5])
                        }
                    }
                    Text(projection.reason)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Space.tight)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: "\(projection.daysSinceInspection)")
                        .font(Typo.figureLarge)
                        .foregroundStyle(projection.isBlind ? Palette.watch : Palette.textPrimary)
                    Text("days")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(Space.row)
            .frame(maxWidth: .infinity)
            .combPanel(fill: Palette.surfaceElevated,
                       stroke: projection.riskState == .imminent ? Palette.imminent : Palette.hairline)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(hive.name), \(projection.riskState.word.lowercased()), \(projection.reason)")
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: Space.gap) {
            Spacer()
            EmptyStandComposition()
            VStack(spacing: Space.tight) {
                Text("No hives yet")
                    .font(Typo.display)
                    .foregroundStyle(Palette.textPrimary)
                Text("Add one and I'll start the clock from your last inspection.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Add a hive") { showingAddHive = true }
                .buttonStyle(HoneyButtonStyle())
                .padding(.top, Space.tight)
            Spacer()
            Spacer()
        }
        .padding(Space.screen)
    }
}

