//
//  AddHiveView.swift
//  QueenRight
//
//  Adding a hive to an existing apiary. Same shape as onboarding's entry page: the date
//  it was last open is what starts the clock, so it is asked for plainly and defaults to
//  today rather than being hidden behind an "advanced" disclosure.
//

import SwiftUI

struct AddHiveView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var broodBoxes = 1
    @State private var supers = 0
    @State private var queenYear = Calendar.current.component(.year, from: Date())
    @State private var lastOpened = Date()

    private var system: HiveSystem { state.apiary?.system ?? .national }

    var body: some View {
        NavigationStack {
            ZStack {
                CombGround()
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.gap) {
                        field("Hive name", text: $name, placeholder: suggestedName)

                        stepperRow("Brood boxes", value: $broodBoxes, range: 1...3)
                        stepperRow("Supers", value: $supers, range: 0...4)

                        VStack(alignment: .leading, spacing: Space.tight) {
                            Text("Queen introduced")
                                .font(Typo.label)
                                .foregroundStyle(Palette.textSecondary)
                            Picker("Queen year", selection: $queenYear) {
                                ForEach(queenYears, id: \.self) { Text(String($0)).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Text("Marked \(QueenMark.forYear(queenYear).displayName.lowercased())")
                                .font(Typo.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }

                        DatePicker("Last had it open", selection: $lastOpened,
                                   in: ...Date(), displayedComponents: .date)
                            .font(Typo.body)
                            .foregroundStyle(Palette.textPrimary)
                            .tint(Palette.accent)

                        NotePanel(text: "The board draws from that date and plays forward. Capture one brood frame and the clock starts running on this colony's own numbers.")

                        Button("Add the hive") { add() }
                            .buttonStyle(HoneyButtonStyle())
                    }
                    .padding(Space.screen)
                }
            }
            .navigationTitle("New hive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textPrimary)
                }
            }
        }
    }

    private var suggestedName: String { "Hive \((state.hives.count) + 1)" }

    private var queenYears: [Int] {
        let year = Calendar.current.component(.year, from: Date())
        return [year, year - 1, year - 2, year - 3]
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            Text(label)
                .font(Typo.label)
                .foregroundStyle(Palette.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .foregroundStyle(Palette.textPrimary)
                .padding(Space.row)
                .combPanel(fill: Palette.surfaceElevated)
        }
    }

    private func stepperRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(label)
                    .font(Typo.body)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(verbatim: "\(value.wrappedValue)")
                    .font(Typo.figure)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
    }

    private func add() {
        let finalName = name.trimmed.isEmpty ? suggestedName : name.trimmed
        var boxes: [Box] = (0..<broodBoxes).map { _ in
            Box(kind: .brood, frames: (0..<system.framesPerBox).map { _ in Frame.drawn() })
        }
        boxes.append(contentsOf: (0..<supers).map { _ in
            Box(kind: .superBox, frames: (0..<system.framesPerBox).map { _ in Frame.drawn() })
        })

        // Spread new hives across the yard rather than stacking them on one spot.
        let index = state.hives.count
        let hive = Hive(name: finalName,
                        boxes: boxes,
                        queen: Queen(introducedYear: queenYear,
                                     markColour: QueenMark.forYear(queenYear)),
                        positionX: 0.2 + Double(index % 3) * 0.3,
                        positionY: 0.25 + Double(index / 3) * 0.28,
                        lastInspection: lastOpened)
        state.addHive(hive)
        Haptics.actionDropped()
        dismiss()
    }
}
