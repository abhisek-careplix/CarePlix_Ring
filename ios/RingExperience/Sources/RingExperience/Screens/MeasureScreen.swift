//
//  MeasureScreen.swift
//  RingExperience
//
//  "How am I right now": today's heart-rate line with the resting band, the capability-gated
//  Measure-now grid with honest disabled reasons, the Recent list, and trend shortcuts.
//

import SwiftUI

public struct MeasureScreen<DS: RingDataSource>: View {
    @ObservedObject private var dataSource: DS
    private let navigator: RingNavigator

    public init(dataSource: DS, navigator: RingNavigator = .inert) {
        self.dataSource = dataSource
        self.navigator = navigator
    }

    private var lastResults: [SpotKind: SpotMeasurement] {
        var result: [SpotKind: SpotMeasurement] = [:]
        for m in dataSource.spotMeasurements where result[m.kind] == nil { result[m.kind] = m }
        return result
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: RingTheme.Metrics.spacing16) {
                if dataSource.connection == .unpaired {
                    EmptyStateCard(.unpaired) { navigator.open(.pairing) }
                } else {
                    card("Today's heart rate") {
                        HeartRateDayChart(samples: dataSource.heartRateToday, restingRange: dataSource.today.vitals.first { $0.kind == .restingHeartRate }?.typicalRange, spots: dataSource.spotMeasurements)
                    }
                    card("Measure now") {
                        MeasureGrid(kinds: [.heartRate, .bloodOxygen, .hrv, .stress, .skinTemperature], capabilities: dataSource.capabilities, availability: MeasureAvailability(connection: dataSource.connection, battery: dataSource.battery), lastResults: lastResults) { kind in
                            navigator.open(.measure(kind))
                        }
                    }
                    card("Recent") { recent }
                    card("Trends") { trends }
                    WellnessTag().frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, RingTheme.Metrics.spacing16)
            .padding(.bottom, RingTheme.Metrics.spacing24)
        }
        .background(RingTheme.Background.base)
        .navigationTitle("Measure")
        .refreshable { await dataSource.sync() }
    }

    private var recent: some View {
        VStack(spacing: 0) {
            let items = Array(dataSource.spotMeasurements.prefix(20))
            if items.isEmpty {
                Text("Spot tests you save appear here.").font(RingTypography.footnote).foregroundStyle(RingTheme.Content.tertiary).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, m in
                HStack(spacing: RingTheme.Metrics.spacing12) {
                    Image(systemName: m.kind.symbol).font(.system(size: 14)).foregroundStyle(RingTheme.Content.secondary).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.kind.title).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
                        Text(RingFormat.relative(m.at)).font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary)
                    }
                    Spacer()
                    StateChip(state: m.state, compact: true)
                    RingVitalValue(value: RingFormat.spot(m.kind, m.value), unit: m.unit.isEmpty ? nil : m.unit, size: .small).frame(width: 84, alignment: .trailing)
                }
                .padding(.vertical, RingTheme.Metrics.spacing8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(m.kind.title) \(RingFormat.spot(m.kind, m.value)) \(m.unit), \(m.state.spoken), \(RingFormat.relative(m.at))")
                if index < items.count - 1 { Rectangle().fill(RingTheme.Separator.hairline).frame(height: RingTheme.Metrics.hairline) }
            }
        }
    }

    private var trends: some View {
        HStack(spacing: RingTheme.Metrics.spacing8) {
            ForEach([VitalKind.restingHeartRate, .hrv, .spo2].filter { dataSource.capabilities.supports($0) }) { kind in
                Button { navigator.open(.metric(kind)) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: kind.symbol).font(.system(size: 16)).foregroundStyle(RingTheme.Content.secondary)
                        Text(kind == .restingHeartRate ? "Resting HR" : kind.title).font(RingTypography.caption).foregroundStyle(RingTheme.Content.primary).lineLimit(1).minimumScaleFactor(0.8)
                        Text("30 days").font(RingTypography.caption2).foregroundStyle(RingTheme.Content.tertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(RingTheme.Background.recessed, in: RoundedRectangle(cornerRadius: RingTheme.Metrics.cornerSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.title) trend, 30 days")
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RingEyebrow(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
    }
}

#Preview("Established · dark") {
    NavigationStack { MeasureScreen(dataSource: MockRingDataSource()) }.preferredColorScheme(.dark)
}
#Preview("Battery died · light") {
    NavigationStack { MeasureScreen(dataSource: MockRingDataSource(scenario: .batteryDied)) }.preferredColorScheme(.light)
}
