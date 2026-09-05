//
//  ProfileOnboardingFlow.swift
//  RingExperience
//
//  Welcome, then one question per screen — birth date, sex, height, weight, wear hand and
//  finger, bedtime and wake, sleep goal — each with a one-sentence reason. Nothing is asked that
//  is not used, and the user is told what each answer is for. Skippable at any point.
//

import SwiftUI

public struct ProfileOnboardingFlow: View {
    private let onComplete: (UserProfile) -> Void
    private let onSkip: () -> Void
    @State private var profile: UserProfile
    @State private var page = 0

    private static let questions = 7

    public init(initial: UserProfile = .draft(), onComplete: @escaping (UserProfile) -> Void, onSkip: @escaping () -> Void = {}) {
        _profile = State(initialValue: initial)
        self.onComplete = onComplete
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing24) {
                    if page == 0 { welcome } else { question }
                }
                .padding(RingTheme.Metrics.spacing24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .background(RingTheme.Background.base)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if page > 0 { Button("Back") { page -= 1 } }
            }
            ToolbarItem(placement: .navigationBarTrailing) { Button("Skip") { onSkip() } }
        }
        .ringMotion(RingMotion.cardAppear, value: page)
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing24) {
            RingIllustration(diameter: 96).frame(maxWidth: .infinity)
            Text("Your nights, explained").font(RingTypography.largeTitle).foregroundStyle(RingTheme.Content.primary)
            welcomeCard("moon.fill", "Sleep", "Stages, awakenings and how the night compares with your usual.")
            welcomeCard("sparkles", "Recovery", "A morning readiness score once the ring has learned your baseline.")
            welcomeCard("waveform", "Vitals", "Resting heart rate, HRV, oxygen, breathing and skin temperature, each against your own range.")
            Text("Seven questions, one screen each. Every answer is used, and we say what for.").font(RingTypography.footnote).foregroundStyle(RingTheme.Content.tertiary)
        }
    }

    private func welcomeCard(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: RingTheme.Metrics.spacing12) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(RingTheme.Brand.ink).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(RingTypography.headline).foregroundStyle(RingTheme.Content.primary)
                Text(body).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: Questions

    @ViewBuilder
    private var question: some View {
        RingEyebrow("About you · \(page) of \(Self.questions)")
        switch page {
        case 1:
            prompt("When were you born?", "Age sets the starting point for your heart-rate and sleep estimates until your own baseline takes over.")
            DatePicker("Birth date", selection: $profile.birthDate, in: ...Date(), displayedComponents: .date).datePickerStyle(.wheel).labelsHidden()
        case 2:
            prompt("Sex for ranges", "Used only for the ring's starting estimates. Choose \"Prefer not to say\" for a neutral model; your personal range replaces it after seven nights either way.")
            Picker("Sex", selection: $profile.sex) { ForEach(Sex.allCases) { Text($0.label).tag($0) } }.pickerStyle(.inline).labelsHidden()
        case 3:
            prompt("How tall are you?", "Turns steps into distance and calories on the ring itself.")
            unitsToggle
            ProfileMeasureRow(title: "Height", units: profile.units, kind: .height, value: $profile.heightCm).padding().ringCard()
        case 4:
            prompt("How much do you weigh?", "With height, this makes the calorie estimate honest.")
            unitsToggle
            ProfileMeasureRow(title: "Weight", units: profile.units, kind: .weight, value: $profile.weightKg).padding().ringCard()
        case 5:
            prompt("Which hand and finger?", "Wear detection and the fit guide use this, and support can help faster.")
            Picker("Hand", selection: $profile.wearHand) { ForEach(WearHand.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
            Picker("Finger", selection: $profile.wearFinger) { ForEach(WearFinger.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
            WearGuide(hand: profile.wearHand, finger: profile.wearFinger).ringCard()
        case 6:
            prompt("Your usual bedtime and wake time", "Times the \"charge before bed\" reminder and the evening card; tells the ring where to look for your night.")
            VStack(spacing: 0) {
                ClockTimeRow(title: "Bedtime", time: $profile.bedtime).padding(.vertical, 8)
                Rectangle().fill(RingTheme.Separator.hairline).frame(height: RingTheme.Metrics.hairline)
                ClockTimeRow(title: "Wake", time: $profile.wakeTime).padding(.vertical, 8)
            }
            .ringCard()
        default:
            prompt("How much sleep do you need?", "Your sleep goal is what Sleep debt is measured against. Most adults land between 7 and 8 hours.")
            VStack(spacing: RingTheme.Metrics.spacing12) {
                RingVitalValue(value: RingFormat.duration(minutes: profile.sleepGoalMin), size: .large)
                Slider(value: Binding(get: { Double(profile.sleepGoalMin) }, set: { profile.sleepGoalMin = Int($0 / 15) * 15 }), in: 300...600, step: 15)
                    .tint(RingTheme.Status.good)
                    .accessibilityLabel("Sleep goal")
                    .accessibilityValue(RingFormat.duration(minutes: profile.sleepGoalMin))
            }
            .frame(maxWidth: .infinity)
            .ringCard()
        }
    }

    private func prompt(_ title: String, _ reason: String) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
            Text(title).font(RingTypography.title).foregroundStyle(RingTheme.Content.primary).fixedSize(horizontal: false, vertical: true)
            Text(reason).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var unitsToggle: some View {
        Picker("Units", selection: $profile.units) { ForEach(Units.allCases) { Text($0.label).tag($0) } }
            .pickerStyle(.segmented)
            .accessibilityLabel("Units")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: RingTheme.Metrics.spacing8) {
            Button(page == 0 ? "Get started" : (page == Self.questions ? "Done" : "Continue")) {
                RingHaptics.selection()
                if page == Self.questions { onComplete(profile) } else { page += 1 }
            }
            .buttonStyle(RingPrimaryButtonStyle())
        }
        .padding(RingTheme.Metrics.spacing24)
        .background(RingTheme.Background.elevated)
    }
}

#Preview("Welcome") { NavigationStack { ProfileOnboardingFlow(onComplete: { _ in }) } }
#Preview("Dark") { NavigationStack { ProfileOnboardingFlow(onComplete: { _ in }) }.preferredColorScheme(.dark) }
