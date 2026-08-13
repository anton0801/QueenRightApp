//
//  SettingsView.swift
//  QueenRight
//
//  §5.5 — ruled sections on the hex ground. APIARY, QUEENS, METHOD, ACCOUNT.
//  QUEENS is the section that turns a settings list into visible evidence that the model
//  has been paying attention: each colony's LEARNED laying rate against the book figure.
//  METHOD names the constants in-app rather than linking out.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showingMethod = false
    @State private var showingAccount = false
    @State private var alertsAuthorized = false

    var body: some View {
        NavigationStack {
            ZStack {
                CombGround()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.section) {
                        apiarySection
                        queensSection
                        alertsSection
                        methodSection
                        accountSection
                        appearanceSection
                    }
                    .padding(Space.screen)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.accent)
                }
            }
            .sheet(isPresented: $showingMethod) { MethodView() }
            .sheet(isPresented: $showingAccount) { AccountView() }
        }
    }

    // MARK: APIARY

    private var apiarySection: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: "Apiary")
            if let apiary = state.apiary {
                StatRow(label: "Site", value: apiary.name)
                StatRow(label: "Frame type", value: apiary.system.displayName)
                StatRow(label: "Brood frame", value: apiary.system.broodFrameName)
                StatRow(label: "Cells per brood frame",
                        value: Fmt.cells(apiary.system.cellsPerFrame(for: .brood)))
                StatRow(label: "Position",
                        value: String(format: "%.3f, %.3f", apiary.latitude, apiary.longitude))
                StatRow(label: "Hives", value: "\(apiary.hives.count)")
            } else {
                Text("No apiary set up yet.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(Space.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .combPanel(fill: Palette.surfaceElevated)
    }

    // MARK: QUEENS — the model showing its working

    private var queensSection: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            SectionHead(title: "Queens")

            if state.hives.isEmpty {
                Text("No hives yet.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                ForEach(state.hives) { hive in
                    queenRow(hive)
                }
                Text("A laying rate is learned from your own frame captures. Until a colony has been measured across most of its brood box, the book figure is used instead.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .combPanel(fill: Palette.surfaceElevated)
    }

    private func queenRow(_ hive: Hive) -> some View {
        let queen = hive.queen
        let book = queen.bookPotential
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(hive.name)
                    .font(Typo.titleSm)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(verbatim: "\(queen.introducedYear) · \(queen.markColour.displayName.lowercased())")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            if let learned = queen.learnedLayRate {
                // e.g. "hive 3's queen is laying about 1,940 a day — above the book"
                Text("Laying about \(Fmt.cells(Int(learned))) a day — \(LayRateLearner.comparison(learned: learned, book: book))")
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.accent)
                Text("Book figure for a \(String(queen.ageYears))-year-old queen: \(Fmt.cells(Int(book))) a day. Learned from \(String(queen.estimateHistory.filter { $0.isRepresentative }.count)) measured inspections.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Book figure: \(Fmt.cells(Int(book))) a day")
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.textSecondary)
                let done = queen.estimateHistory.filter { $0.isRepresentative }.count
                Text(done == 0
                     ? "Not measured yet — capture the brood frames and this becomes her own figure."
                     : "\(String(done)) measured inspection\(done == 1 ? "" : "s") so far.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: ALERTS — permission asked for here, in context (acceptance 13)

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: "Alerts")
            Text("One notification when a colony crosses into imminent, and one when a hive has gone long enough without a look that the clock is guessing. Nothing else.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if alertsAuthorized {
                Text("Alerts are on.")
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.accent)
            } else {
                Button("Turn alerts on") {
                    Task {
                        let granted = await SwarmAlerts.requestPermission()
                        alertsAuthorized = granted
                        state.preferences.notificationsRequested = true
                        state.persistPreferences()
                        if granted { await state.rescheduleAlerts() }
                    }
                }
                .buttonStyle(OutlineButtonStyle())

                if state.preferences.notificationsRequested {
                    Text("Notifications are off for Queenright in iOS Settings. The app works exactly the same without them — it just won't interrupt you.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Space.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .combPanel(fill: Palette.surfaceElevated)
        .task {
            alertsAuthorized = await SwarmAlerts.authorizationStatus() == .authorized
        }
    }

    // MARK: METHOD

    private var methodSection: some View {
        Button { showingMethod = true } label: {
            VStack(alignment: .leading, spacing: Space.tight) {
                SectionHead(title: "Method")
                HStack {
                    Text("The brood cycle, the space formula, the flow rule")
                        .font(Typo.body)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(Space.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .combPanel(fill: Palette.surfaceElevated)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: ACCOUNT

    private var accountSection: some View {
        Button { showingAccount = true } label: {
            VStack(alignment: .leading, spacing: Space.tight) {
                SectionHead(title: "Account")
                HStack {
                    Text(AuthService.isConfigured ? "Sign in, members, delete account" : "Sync is off on this build")
                        .font(Typo.body)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(Space.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .combPanel(fill: Palette.surfaceElevated)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: "Appearance")
            Picker("Appearance", selection: Binding(
                get: { state.preferences.appearance },
                set: { state.preferences.appearance = $0; state.persistPreferences() }
            )) {
                ForEach(AppearanceMode.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(Space.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .combPanel(fill: Palette.surfaceElevated)
    }
}

// MARK: - METHOD (§5.5 — the constants named in-app, not linked out)

struct MethodView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            ZStack {
                CombGround()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.section) {
                        block(title: "The brood cycle", rows: [
                            ("Worker egg", "days 0–3"),
                            ("Worker capped", "day 9"),
                            ("Worker emerges", "day 21"),
                            ("Drone emerges", "day 24"),
                            ("Queen cell capped", "day 8"),
                            ("Queen emerges", "day 16"),
                            ("Mating and back to laying", "5–14 days after she emerges")
                        ], note: "A capped queen cell means days, not weeks. That is the whole reason this app exists.")

                        block(title: "Laying space, in cells", rows: [
                            ("National deep", "\(Fmt.cells(HiveSystem.national.broodCellsPerSide)) a side"),
                            ("National 14×12", "\(Fmt.cells(HiveSystem.nationalJumbo.broodCellsPerSide)) a side"),
                            ("Langstroth deep", "\(Fmt.cells(HiveSystem.langstroth.broodCellsPerSide)) a side"),
                            ("Cells needed", "lay rate × 21 days"),
                            ("Congested past", "75% space pressure")
                        ], note: "A worker cell is 5.4 mm across the flats, which packs to about 25.6 cells per square inch of comb. At 1,800 eggs a day a queen needs roughly \(Fmt.cells(37_800)) cells standing occupied — seven to eight National deep frames of solid brood.\n\nSupers are excluded from this sum. A super is stores comb, not laying space.")

                        block(title: "Forage", rows: [
                            ("A flow day", "mean ≥ 14 °C, rain < 3 mm, wind < 7 m/s"),
                            ("Flow factor", "0.4 + 0.6 × flow days in the last 7"),
                            ("Flow resumption", "a flow day after 4 dull ones raises risk for 3 days")
                        ], note: "A congested colony rained in for a week swarms on the first warm afternoon. When the forage reading is more than 48 hours old this term is set aside rather than guessed.")

                        block(title: "Population", rows: [
                            ("Brood survival", Fmt.percent(Population.broodSurvival)),
                            ("Lifespan in a flow", "\(Int(Population.lifespanInFlow)) days"),
                            ("Lifespan in a dearth", "\(Int(Population.lifespanInDearth)) days"),
                            ("Winter bee", "\(Int(Population.lifespanWinterBee)) days"),
                            ("First-year queen", "\(Fmt.cells(1600)) eggs a day"),
                            ("Third-year queen", "\(Fmt.cells(1200)) eggs a day")
                        ], note: "Brood laid today is flying bees in three weeks. That lag is why the projection can see trouble before you can.")

                        attribution
                    }
                    .padding(Space.screen)
                }
            }
            .navigationTitle("Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.accent)
                }
            }
        }
    }

    private func block(title: String, rows: [(String, String)], note: String) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: title)
            ForEach(rows, id: \.0) { row in
                StatRow(label: row.0, value: row.1)
            }
            Text(note)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(Space.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .combPanel(fill: Palette.surfaceElevated)
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            SectionHead(title: "Where the weather comes from")
            Text(OpenMeteoClient.licenceNote)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(OpenMeteoClient.attributionURL,
                 destination: URL(string: OpenMeteoClient.attributionURL) ?? URL(fileURLWithPath: "/"))
                .font(Typo.caption)
                .foregroundStyle(Palette.accent)
        }
        .padding(Space.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .combPanel(fill: Palette.surfaceElevated)
    }
}
