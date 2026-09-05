//
//  HeroCard.swift
//  RingExperience
//
//  The "one big thing" on Today. The hero is the ONLY element of Today that changes with the
//  clock: Readiness in the morning, Stress or Activity in the afternoon, Tonight in the evening,
//  and honest cards when there is nothing to score — learning, no night, no ring.
//

import SwiftUI

public enum HeroAction: Equatable {
    case openSleep
    case breathe(minutes: Int)
    case openRing
    case sync
    case pair
    case showWearGuide
    case openActivity
}

public struct HeroCard: View {
    private let hero: TodayHero
    private let onAction: (HeroAction) -> Void

    public init(hero: TodayHero, onAction: @escaping (HeroAction) -> Void) {
        self.hero = hero
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing16) {
            switch hero {
            case let .morning(score): morning(score)
            case let .afternoonStress(stress): afternoonStress(stress)
            case let .afternoonActivity(day): afternoonActivity(day)
            case let .evening(bedtime, battery): evening(bedtime: bedtime, battery: battery)
            case let .learning(nights): learning(nights)
            case let .noNight(reason): noNight(reason)
            case .unpaired: unpaired
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard(padding: RingTheme.Metrics.spacing24)
        .ringMotion(RingMotion.cardAppear, value: hero)
    }

    // MARK: Morning — Readiness

    private func morning(_ score: Score) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing16) {
            RingEyebrow("This morning")
            HStack(alignment: .center, spacing: RingTheme.Metrics.spacing24) {
                ScoreRing(score: score, size: .hero)
                VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
                    if case let .measured(metric) = score.state { StateChip(metric: metric) }
                    Text(score.caption)
                        .font(RingTypography.headline)
                        .foregroundStyle(RingTheme.Content.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !score.contributors.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RingTheme.Metrics.spacing8) {
                        ForEach(score.contributors) { c in
                            HStack(spacing: RingTheme.Metrics.spacing4) {
                                Text(c.name).font(RingTypography.caption).foregroundStyle(RingTheme.Content.secondary)
                                if let trend = c.trend { Image(systemName: trend.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(c.state.metric.color) }
                            }
                            .padding(.horizontal, RingTheme.Metrics.spacing8).padding(.vertical, 4)
                            .background(RingTheme.Background.recessed, in: Capsule())
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(c.name) \(c.reading), \(c.state.spoken)")
                        }
                    }
                }
            }
            Button("See last night") { onAction(.openSleep) }.buttonStyle(RingSecondaryButtonStyle())
            WellnessTag()
        }
    }

    // MARK: Afternoon — Stress

    private func afternoonStress(_ stress: Int) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RingEyebrow("Stress now")
            HStack(alignment: .firstTextBaseline, spacing: RingTheme.Metrics.spacing8) {
                RingVitalValue(value: "\(stress)", unit: "of 100", size: .hero)
                Spacer()
                StateChip(metric: stress < 40 ? .good : (stress < 70 ? .fair : .poor))
            }
            Text(stress < 40 ? "Calm afternoon. Your heartbeat timing is steady." : "Your heartbeat timing suggests some load. Three minutes of slow breathing usually settles it.")
                .font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).fixedSize(horizontal: false, vertical: true)
            Button { onAction(.breathe(minutes: 3)) } label: { Label("Breathe 3 min", systemImage: "wind") }.buttonStyle(RingPrimaryButtonStyle())
            RingProvenance("From heartbeat timing · wellness estimate")
        }
    }

    // MARK: Afternoon — Activity

    private func afternoonActivity(_ day: ActivityDay) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RingEyebrow("This afternoon")
            HStack(alignment: .firstTextBaseline, spacing: RingTheme.Metrics.spacing4) {
                RingVitalValue(value: RingFormat.steps(day.steps), unit: "steps", size: .large)
                Spacer()
                Text("of \(RingFormat.steps(day.goal))").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.tertiary)
            }
            ProgressView(value: day.goalFraction)
                .tint(RingTheme.Status.good)
                .accessibilityLabel("Step goal progress")
                .accessibilityValue("\(Int(day.goalFraction * 100)) percent")
            Text(day.goalFraction >= 1 ? "Goal reached. Nothing more to do today." : "A \(RingFormat.duration(minutes: max(10, Int(Double(day.goal - day.steps) / 100)))) walk would close the gap.")
                .font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).fixedSize(horizontal: false, vertical: true)
            Button("See activity") { onAction(.openActivity) }.buttonStyle(RingSecondaryButtonStyle())
        }
    }

    // MARK: Evening — Tonight

    private func evening(bedtime: ClockTime, battery: Battery?) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing16) {
            RingEyebrow("Tonight")
            HStack(spacing: RingTheme.Metrics.spacing16) {
                BatteryGauge(battery: battery, size: .compact)
                VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing4) {
                    Text("Bedtime \(RingFormat.clock(bedtime))").font(RingTypography.headline).foregroundStyle(RingTheme.Content.primary)
                    Text(eveningLine(battery)).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let battery, !battery.isEnoughForTonight, !battery.isCharging {
                Button { onAction(.openRing) } label: { Label("Charge now", systemImage: "bolt.fill") }.buttonStyle(RingPrimaryButtonStyle())
            }
            Button { onAction(.breathe(minutes: 5)) } label: { Label("Wind down · Breathe 5 min", systemImage: "wind") }.buttonStyle(RingSecondaryButtonStyle())
        }
    }

    private func eveningLine(_ battery: Battery?) -> String {
        guard let battery else { return "Battery unknown · check your ring" }
        if battery.isCharging { return "Ring charging · \(battery.percent.map { "\($0) %" } ?? "")".trimmingCharacters(in: .whitespaces) }
        let level = battery.percent.map { "Ring \($0) %" } ?? "Ring"
        return battery.isEnoughForTonight ? "\(level) · enough for tonight" : "\(level) · charge for about 40 minutes before bed"
    }

    // MARK: Learning

    private func learning(_ nights: Int) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing16) {
            RingEyebrow(nights == 0 ? "Your first night starts tonight" : "Learning your usual")
            HStack(alignment: .center, spacing: RingTheme.Metrics.spacing24) {
                ScoreRing(title: "Readiness", state: .learning(night: nights, of: HeroSelection.nightsNeeded), size: .hero)
                    .ringBreathingPulse()
                VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
                    milestone("Tonight", "Sleep with the ring on", done: nights > 0)
                    milestone("Tomorrow", "Your first Sleep page", done: nights > 0)
                    milestone("Night 7", "Typical ranges and Readiness", done: nights >= HeroSelection.nightsNeeded)
                }
            }
            if nights == 0 { Button("How to wear it") { onAction(.showWearGuide) }.buttonStyle(RingSecondaryButtonStyle()) }
        }
    }

    private func milestone(_ when: String, _ what: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: RingTheme.Metrics.spacing8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? RingTheme.Status.optimal : RingTheme.Content.tertiary).font(.system(size: 14))
            VStack(alignment: .leading, spacing: 1) {
                Text(when).font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary)
                Text(what).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: No night

    private func noNight(_ reason: NoNightReason) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RingEyebrow("Last night")
            Text(reason.headline).font(RingTypography.title2).foregroundStyle(RingTheme.Content.primary)
            Text(reason.body).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).fixedSize(horizontal: false, vertical: true)
            Button(reason.actionTitle) {
                switch reason {
                case .notWorn: onAction(.showWearGuide)
                case .batteryRanOut: onAction(.openRing)
                case .notSynced: onAction(.sync)
                }
            }
            .buttonStyle(RingPrimaryButtonStyle())
        }
    }

    // MARK: Unpaired

    private var unpaired: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing16) {
            HStack(spacing: RingTheme.Metrics.spacing16) {
                RingIllustration(diameter: 72)
                VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing4) {
                    Text("Pair your ring").font(RingTypography.title2).foregroundStyle(RingTheme.Content.primary)
                    Text("Take it off the charger and hold it near your phone.").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("Pair ring") { onAction(.pair) }.buttonStyle(RingPrimaryButtonStyle())
        }
    }
}

#Preview("Heroes") {
    ScrollView {
        VStack(spacing: 16) {
            HeroCard(hero: .morning(Score(kind: .readiness, value: 82, state: .measured(.good), caption: "Recovered. HRV above your usual, resting heart rate steady.", contributors: [Contributor(name: "HRV", reading: "48 ms", state: .typical, trend: .up), Contributor(name: "Resting heart rate", reading: "56 bpm", state: .typical, trend: .steady), Contributor(name: "Sleep", reading: "84", state: .typical)])), onAction: { _ in })
            HeroCard(hero: .afternoonStress(34), onAction: { _ in })
            HeroCard(hero: .evening(bedtime: ClockTime(hour: 23), battery: Battery(percent: 24, forecastNights: 0.8)), onAction: { _ in })
            HeroCard(hero: .learning(nights: 3), onAction: { _ in })
            HeroCard(hero: .noNight(.batteryRanOut(at: Date())), onAction: { _ in })
            HeroCard(hero: .unpaired, onAction: { _ in })
        }
        .padding()
    }
    .background(RingTheme.Background.base)
}
