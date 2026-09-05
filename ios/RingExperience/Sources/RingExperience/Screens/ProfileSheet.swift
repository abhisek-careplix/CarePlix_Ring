//
//  ProfileSheet.swift
//  RingExperience
//
//  Every onboarding answer, editable. Saving writes the profile to the ring; sleep goal and
//  bedtime feed Sleep Debt and the evening hero, so an edit here changes tomorrow's story.
//

import SwiftUI

public struct ProfileSheet<DS: RingDataSource>: View {
    @ObservedObject private var dataSource: DS
    @Environment(\.dismiss) private var dismiss
    @State private var draft: UserProfile
    @State private var isSaving = false

    @MainActor public init(dataSource: DS) {
        self.dataSource = dataSource
        _draft = State(initialValue: dataSource.profile ?? .draft())
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Name (optional)", text: Binding(get: { draft.name ?? "" }, set: { draft.name = $0.isEmpty ? nil : $0 }))
                    DatePicker("Birth date", selection: $draft.birthDate, in: ...Date(), displayedComponents: .date)
                    Picker("Sex", selection: $draft.sex) { ForEach(Sex.allCases) { Text($0.label).tag($0) } }
                    Picker("Units", selection: $draft.units) { ForEach(Units.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    ProfileMeasureRow(title: "Height", units: draft.units, kind: .height, value: $draft.heightCm)
                    ProfileMeasureRow(title: "Weight", units: draft.units, kind: .weight, value: $draft.weightKg)
                }
                Section {
                    Picker("Hand", selection: $draft.wearHand) { ForEach(WearHand.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    Picker("Finger", selection: $draft.wearFinger) { ForEach(WearFinger.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                } header: { Text("Wear") } footer: { Text("Used for wear detection and support.") }
                Section {
                    ClockTimeRow(title: "Usual bedtime", time: $draft.bedtime)
                    ClockTimeRow(title: "Usual wake time", time: $draft.wakeTime)
                    Stepper("Sleep goal \(RingFormat.duration(minutes: draft.sleepGoalMin))", value: $draft.sleepGoalMin, in: 300...600, step: 15)
                } header: { Text("Sleep") } footer: { Text("Bedtime times the charge reminder and the evening card. The goal feeds Sleep debt.") }
                Section("Activity") {
                    Stepper("Step goal \(RingFormat.steps(draft.stepGoal))", value: $draft.stepGoal, in: 2000...20000, step: 500)
                }
            }
            .scrollContentBackground(.hidden)
            .background(RingTheme.Background.base)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        isSaving = true
                        Task { await dataSource.saveProfile(draft); isSaving = false; dismiss() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}

/// Height or weight with an inline unit conversion, stored metric.
struct ProfileMeasureRow: View {
    enum Kind { case height, weight }
    let title: String
    let units: Units
    let kind: Kind
    @Binding var value: Double

    private var shown: Binding<Double> {
        Binding(
            get: {
                switch (units, kind) {
                case (.metric, _): return value.rounded()
                case (.imperial, .height): return (value / 2.54).rounded()
                case (.imperial, .weight): return (value * 2.20462).rounded()
                }
            },
            set: { new in
                switch (units, kind) {
                case (.metric, _): value = new
                case (.imperial, .height): value = new * 2.54
                case (.imperial, .weight): value = new / 2.20462
                }
            }
        )
    }

    private var unit: String {
        switch (units, kind) {
        case (.metric, .height): return "cm"
        case (.metric, .weight): return "kg"
        case (.imperial, .height): return "in"
        case (.imperial, .weight): return "lb"
        }
    }

    private var range: ClosedRange<Double> {
        switch (units, kind) {
        case (.metric, .height): return 120...230
        case (.metric, .weight): return 30...250
        case (.imperial, .height): return 47...91
        case (.imperial, .weight): return 66...550
        }
    }

    var body: some View {
        Stepper(value: shown, in: range, step: 1) {
            HStack { Text(title); Spacer(); Text("\(Int(shown.wrappedValue)) \(unit)").monospacedDigit().foregroundStyle(RingTheme.Content.secondary) }
        }
        .accessibilityValue("\(Int(shown.wrappedValue)) \(unit)")
    }
}

/// A wall-clock picker bound to `ClockTime`.
struct ClockTimeRow: View {
    let title: String
    @Binding var time: ClockTime

    private var dateBinding: Binding<Date> {
        Binding(get: { time.date(on: Date()) }, set: { time = ClockTime(date: $0) })
    }

    var body: some View {
        DatePicker(title, selection: dateBinding, displayedComponents: .hourAndMinute)
    }
}

#Preview { ProfileSheet(dataSource: MockRingDataSource()) }
