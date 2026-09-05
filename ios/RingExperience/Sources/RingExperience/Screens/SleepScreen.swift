//
//  SleepScreen.swift
//  RingExperience
//
//  Last night, honestly: night strip · score hero with bedtime → wake · hypnogram · stages ·
//  contributors · overnight vitals · sleep debt. A night not worn, or cut short by a flat
//  battery, says so as a full card with the wear guide, instead of showing an empty chart.
//

import SwiftUI

public struct SleepScreen<DS: RingDataSource>: View {
    @ObservedObject private var dataSource: DS
    private let navigator: RingNavigator
    @State private var selectedIndex: Int?

    public init(dataSource: DS, navigator: RingNavigator = .inert) {
        self.dataSource = dataSource
        self.navigator = navigator
    }

    private var nights: [SleepNight] { dataSource.nights }
    private var night: SleepNight? {
        guard !nights.isEmpty else { return nil }
        let index = min(selectedIndex ?? nights.count - 1, nights.count - 1)
        return nights[max(index, 0)]
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: RingTheme.Metrics.spacing16) {
                if nights.isEmpty {
                    EmptyStateCard(dataSource.connection == .unpaired ? .unpaired : .nothingYet("Your first night appears here tomorrow morning"), action: dataSource.connection == .unpaired ? { navigator.open(.pairing) } : nil)
                } else if let night {
                    nightStrip
                    if night.wasNotWorn {
                        EmptyStateCard(.notWorn(from: night.notWornRanges.first?.lowerBound, to: night.notWornRanges.first?.upperBound), action: { navigator.open(.wearGuide) })
                        WearGuide(hand: dataSource.profile?.wearHand ?? .left, finger: dataSource.profile?.wearFinger ?? .index).ringCard()
                    } else {
                        if let loss = night.batteryLossAt { partialBanner(loss) }
                        hero(night)
                        card("Stages") { Hypnogram(night: night) }
                        card("How the night was made") { StageBars(night: night, usualShares: usualShares(before: night)) }
                        card("What shaped the score") { ContributorList(contributors: night.contributors) }
                        card("Overnight vitals") { OvernightVitalsList(night: night) { navigator.open(.metric($0.kind)) } }
                        if nights.count < Baselines.nightsNeeded {
                            EmptyStateCard(.learning(nights: nights.count, needed: Baselines.nightsNeeded))
                        }
                    }
                    if let debt = dataSource.today.sleepDebt, nights.count >= 3 { SleepDebtCard(debt: debt) }
                    WellnessTag().frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, RingTheme.Metrics.spacing16)
            .padding(.bottom, RingTheme.Metrics.spacing24)
        }
        .background(RingTheme.Background.base)
        .navigationTitle("Sleep")
        .refreshable { await dataSource.sync() }
    }

    // MARK: Night strip

    private var nightStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: RingTheme.Metrics.spacing8) {
                    ForEach(Array(nights.enumerated()), id: \.element.id) { index, n in
                        let selected = index == (selectedIndex ?? nights.count - 1)
                        Button {
                            RingHaptics.selection()
                            selectedIndex = index
                        } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(barColor(n))
                                    .frame(width: 18, height: max(CGFloat(n.durationMin) / 600 * 44, 4))
                                Text(RingFormat.weekdayInitial(n.date)).font(RingTypography.caption2).foregroundStyle(selected ? RingTheme.Content.primary : RingTheme.Content.tertiary)
                            }
                            .frame(width: 28, height: 64, alignment: .bottom)
                            .padding(.horizontal, 4)
                            .background(selected ? RingTheme.Background.recessed : .clear, in: RoundedRectangle(cornerRadius: RingTheme.Metrics.cornerSmall, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id(index)
                        .accessibilityLabel("\(RingFormat.day(n.date)), \(n.wasNotWorn ? "not worn" : RingFormat.duration(minutes: n.durationMin))\(n.score.value.map { ", sleep \($0)" } ?? "")")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, RingTheme.Metrics.spacing4)
            }
            .onAppear { proxy.scrollTo(nights.count - 1, anchor: .trailing) }
        }
    }

    private func barColor(_ n: SleepNight) -> Color {
        if n.wasNotWorn { return RingTheme.Chart.noData }
        if case let .measured(metric) = n.score.state { return metric.color }
        return RingTheme.Status.abstained
    }

    // MARK: Hero

    private func hero(_ night: SleepNight) -> some View {
        VStack(spacing: RingTheme.Metrics.spacing16) {
            HStack(spacing: RingTheme.Metrics.spacing24) {
                ScoreRing(score: night.score, size: .hero)
                VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
                    RingVitalValue(value: RingFormat.duration(minutes: night.durationMin), size: .medium)
                    Text("\(RingFormat.clock(night.bedtime)) → \(RingFormat.clock(night.wake))").font(RingTypography.footnoteNumeric).foregroundStyle(RingTheme.Content.secondary)
                    if case let .measured(metric) = night.score.state { StateChip(metric: metric) }
                }
            }
            Text(night.score.caption).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .ringCard(padding: RingTheme.Metrics.spacing24)
    }

    private func partialBanner(_ loss: Date) -> some View {
        Label("Your ring ran out at \(RingFormat.clock(loss)). The night below is what it recorded.", systemImage: "battery.0percent")
            .font(RingTypography.footnote).foregroundStyle(RingTheme.Status.poor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RingTheme.Metrics.spacing12)
            .background(RingTheme.Status.poor.opacity(0.1), in: RoundedRectangle(cornerRadius: RingTheme.Metrics.cornerSmall, style: .continuous))
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RingEyebrow(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
    }

    /// Each stage's usual share, from the previous seven worn nights. Nil while learning.
    private func usualShares(before night: SleepNight) -> [SleepStage: Double]? {
        let previous = nights.filter { $0.date < night.date && !$0.wasNotWorn }.suffix(7)
        guard previous.count >= 3 else { return nil }
        var totals: [SleepStage: Double] = [:]
        var recorded = 0.0
        for n in previous {
            for (stage, minutes) in n.stageTotals where stage != .gap { totals[stage, default: 0] += Double(minutes) }
            recorded += Double(n.stages.filter { $0 != .gap }.count)
        }
        guard recorded > 0 else { return nil }
        return totals.mapValues { $0 / recorded }
    }
}

#Preview("Established · dark") {
    NavigationStack { SleepScreen(dataSource: MockRingDataSource()) }.preferredColorScheme(.dark)
}
#Preview("Not worn · light") {
    NavigationStack { SleepScreen(dataSource: MockRingDataSource(scenario: .notWorn)) }.preferredColorScheme(.light)
}
#Preview("Battery died") {
    NavigationStack { SleepScreen(dataSource: MockRingDataSource(scenario: .batteryDied)) }
}
