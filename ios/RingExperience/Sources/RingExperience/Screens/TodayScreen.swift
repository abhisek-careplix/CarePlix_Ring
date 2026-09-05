//
//  TodayScreen.swift
//  RingExperience
//
//  The answer, then the evidence. Order is time-aware but fixed; only the hero changes:
//  header · hero · score row · overnight vitals · activity · timeline · weekly card.
//  Syncing shows skeletons (never stale numbers); unpaired shows one "Pair your ring" card.
//

import SwiftUI
import Charts

public struct TodayScreen<DS: RingDataSource>: View {
    @ObservedObject private var dataSource: DS
    private let navigator: RingNavigator
    @State private var showsWeekly = false

    public init(dataSource: DS, navigator: RingNavigator = .inert) {
        self.dataSource = dataSource
        self.navigator = navigator
    }

    private var isSyncing: Bool { if case .syncing = dataSource.connection { return true }; return false }
    private var isUnpaired: Bool { dataSource.connection == .unpaired }

    public var body: some View {
        TimelineView(.everyMinute) { context in
            ScrollView {
                RingMotionReader { reduceMotion in
                    VStack(spacing: RingTheme.Metrics.spacing16) {
                        header(now: context.date)
                        if dataSource.connection == .bluetoothOff { bluetoothBanner }

                        if isSyncing {
                            SkeletonCard(height: 220)
                            SkeletonCard(height: 120)
                        } else {
                            HeroCard(hero: dataSource.heroNow(at: context.date), onAction: handle)
                                .transition(.opacity)
                        }

                        if !isUnpaired {
                            scoreRow
                            vitals
                            activityCard
                            timelineCard
                            if let weekly = dataSource.today.weekly, showsWeekly || Calendar.current.component(.weekday, from: context.date) == 1 {
                                WeeklyCard(weekly: weekly, needMin: dataSource.profile?.sleepGoalMin ?? 450)
                            } else if dataSource.today.weekly != nil {
                                Button("Show this week") { showsWeekly = true }.buttonStyle(RingSecondaryButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, RingTheme.Metrics.spacing16)
                    .padding(.bottom, RingTheme.Metrics.spacing24)
                    .animation(RingMotion.cardAppear.resolved(reduceMotion: reduceMotion), value: isSyncing)
                }
            }
            .background(RingTheme.Background.base)
            .navigationTitle("Today")
            .refreshable { await dataSource.sync() }
        }
    }

    // MARK: Sections

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting(now: now)).font(RingTypography.title2).foregroundStyle(RingTheme.Content.primary)
            Text(RingFormat.day(now)).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func greeting(now: Date) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        if let name = dataSource.profile?.name, !name.isEmpty { return "\(part), \(name)" }
        return part
    }

    private var bluetoothBanner: some View {
        Label("Bluetooth is off. Your ring keeps recording; turn it on to sync.", systemImage: "antenna.radiowaves.left.and.right.slash")
            .font(RingTypography.footnote).foregroundStyle(RingTheme.Status.fair)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RingTheme.Metrics.spacing12)
            .background(RingTheme.Status.fair.opacity(0.12), in: RoundedRectangle(cornerRadius: RingTheme.Metrics.cornerSmall, style: .continuous))
    }

    private var scoreRow: some View {
        HStack(spacing: RingTheme.Metrics.spacing12) {
            scoreShortcut(dataSource.today.readiness) { navigator.switchTab(.sleep) }
            scoreShortcut(dataSource.today.sleep) { navigator.switchTab(.sleep) }
            scoreShortcut(dataSource.today.activityScore) { navigator.switchTab(.measure) }
        }
        .frame(maxWidth: .infinity)
        .ringCard()
    }

    private func scoreShortcut(_ score: Score, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: RingTheme.Metrics.spacing4) {
                ScoreRing(score: score, size: .compact)
                if case let .measured(metric) = score.state { StateChip(metric: metric, compact: true) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(score.kind.title.lowercased())")
    }

    private var vitals: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
            RingEyebrow("Overnight vitals")
            let readings = dataSource.today.vitals.filter { dataSource.capabilities.supports($0.kind) }
            if readings.isEmpty {
                EmptyStateCard(.nothingYet("No overnight vitals yet"))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: RingTheme.Metrics.spacing12), GridItem(.flexible(), spacing: RingTheme.Metrics.spacing12)], spacing: RingTheme.Metrics.spacing12) {
                    ForEach(readings) { reading in
                        VitalTile(reading: reading) { navigator.open(.metric(reading.kind)) }
                    }
                }
            }
        }
    }

    private var activityCard: some View {
        let day = dataSource.today.activity
        return VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RingEyebrow("Activity")
            HStack(alignment: .firstTextBaseline) {
                RingVitalValue(value: RingFormat.steps(day.steps), unit: "steps", size: .medium)
                Spacer()
                Text("of \(RingFormat.steps(day.goal))").font(RingTypography.footnote).foregroundStyle(RingTheme.Content.tertiary)
            }
            ProgressView(value: day.goalFraction).tint(RingTheme.Status.good)
                .accessibilityLabel("Step goal").accessibilityValue("\(Int(day.goalFraction * 100)) percent")
            HStack(spacing: RingTheme.Metrics.spacing16) {
                Label(RingFormat.distance(km: day.distanceKm, units: dataSource.profile?.units ?? .metric), systemImage: "figure.walk")
                Label("\(day.kcal) kcal", systemImage: "flame")
            }
            .font(RingTypography.footnoteNumeric).foregroundStyle(RingTheme.Content.secondary)
            Chart {
                ForEach(Array(day.halfHourSteps.enumerated()), id: \.offset) { index, steps in
                    BarMark(x: .value("Half hour", index), y: .value("Steps", steps), width: .ratio(0.6))
                        .foregroundStyle(steps > 0 ? RingTheme.Status.good : RingTheme.Chart.noData)
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, 12, 24, 36, 47]) { value in
                    AxisValueLabel { if let i = value.as(Int.self) { Text("\(i / 2):00").foregroundStyle(RingTheme.Chart.axisLabel) } }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 64)
            .accessibilityLabel("Steps through the day")
            .accessibilityValue("\(RingFormat.steps(day.steps)) steps so far, busiest around \(busiestHour(day)):00")
            if !day.workouts.isEmpty {
                ForEach(day.workouts) { w in
                    HStack {
                        Label(w.name, systemImage: "figure.run").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
                        Spacer()
                        Text("\(RingFormat.duration(minutes: w.durationMin)) · \(w.kcal) kcal\(w.averageHeartRate.map { " · \($0) bpm" } ?? "")").font(RingTypography.caption).monospacedDigit().foregroundStyle(RingTheme.Content.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
    }

    private func busiestHour(_ day: ActivityDay) -> Int {
        (day.halfHourSteps.enumerated().max { $0.element < $1.element }?.offset ?? 0) / 2
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RingEyebrow("Today's story")
            DayTimeline(items: dataSource.timeline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
    }

    // MARK: Hero actions

    private func handle(_ action: HeroAction) {
        switch action {
        case .openSleep: navigator.switchTab(.sleep)
        case let .breathe(minutes): navigator.breathe(minutes)
        case .openRing: navigator.open(.ring)
        case .sync: Task { await dataSource.sync() }
        case .pair: navigator.open(.pairing)
        case .showWearGuide: navigator.open(.wearGuide)
        case .openActivity: navigator.switchTab(.measure)
        }
    }
}

/// J7: seven nights of sleep vs need, readiness, and how many nights were outside typical.
struct WeeklyCard: View {
    let weekly: WeeklySummary
    let needMin: Int

    var body: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RingEyebrow("This week")
            Chart {
                RuleMark(y: .value("Need", needMin)).foregroundStyle(RingTheme.Separator.strong).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(Array(weekly.sleepMinutes.enumerated()), id: \.offset) { index, minutes in
                    BarMark(x: .value("Night", index), y: .value("Sleep", minutes), width: .ratio(0.5))
                        .foregroundStyle(minutes >= needMin - 30 ? RingTheme.Sleep.light : RingTheme.Sleep.awake)
                        .cornerRadius(3)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(values: [0, 240, 480]) { v in AxisValueLabel { if let m = v.as(Int.self) { Text("\(m / 60) h").foregroundStyle(RingTheme.Chart.axisLabel) } } } }
            .frame(height: 90)
            .accessibilityLabel("Sleep this week")
            .accessibilityValue(weekly.sleepMinutes.map { RingFormat.duration(minutes: $0) }.joined(separator: ", "))
            HStack {
                let scored = weekly.readiness.compactMap { $0 }
                if !scored.isEmpty {
                    Text("Readiness \(scored.min() ?? 0)–\(scored.max() ?? 0)").font(RingTypography.footnoteNumeric).foregroundStyle(RingTheme.Content.secondary)
                }
                Spacer()
                Text(weekly.nightsOutsideTypical == 0 ? "All nights within your typical range" : "\(weekly.nightsOutsideTypical) night\(weekly.nightsOutsideTypical == 1 ? "" : "s") outside your typical range")
                    .font(RingTypography.footnote).foregroundStyle(weekly.nightsOutsideTypical == 0 ? RingTheme.Content.tertiary : RingTheme.Status.fair)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
    }
}

#Preview("Established · dark") {
    NavigationStack { TodayScreen(dataSource: MockRingDataSource(scenario: .established)) }.preferredColorScheme(.dark)
}
#Preview("Battery died · light") {
    NavigationStack { TodayScreen(dataSource: MockRingDataSource(scenario: .batteryDied)) }.preferredColorScheme(.light)
}
#Preview("Not worn") {
    NavigationStack { TodayScreen(dataSource: MockRingDataSource(scenario: .notWorn)) }
}
#Preview("Bluetooth off") {
    NavigationStack { TodayScreen(dataSource: MockRingDataSource(scenario: .bluetoothOff)) }
}
