//
//  BreatheScreen.swift
//  RingExperience
//
//  Breathing, overnight and now: last night's breathing rate against the user's usual, the
//  60-second spot test, guided breathing (app-side, no sensor), and overnight oxygen with
//  "breathing disturbances" — a wellness estimate, never a diagnosis.
//

import SwiftUI
import Charts

public struct BreatheScreen<DS: RingDataSource>: View {
    @ObservedObject private var dataSource: DS
    private let navigator: RingNavigator
    @Binding private var breatheRequest: Int?

    public init(dataSource: DS, navigator: RingNavigator = .inert, breatheRequest: Binding<Int?> = .constant(nil)) {
        self.dataSource = dataSource
        self.navigator = navigator
        _breatheRequest = breatheRequest
    }

    private var overnight: VitalReading? { dataSource.today.vitals.first { $0.kind == .breathingRate } }
    private var lastNight: SleepNight? { dataSource.nights.last }

    /// The latest heart rate if the ring reported one in the last ten minutes.
    private func currentHeartRate() -> Double? {
        guard let last = dataSource.heartRateToday.last, Date().timeIntervalSince(last.time) < 600 else { return nil }
        return last.value
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: RingTheme.Metrics.spacing16) {
                if dataSource.capabilities.supports(VitalKind.breathingRate) || dataSource.connection == .unpaired { overnightCard }
                if dataSource.capabilities.supports(SpotKind.breathingRate) {
                    card("Measure now") {
                        MeasureGrid(kinds: [.breathingRate], capabilities: dataSource.capabilities, availability: MeasureAvailability(connection: dataSource.connection, battery: dataSource.battery), lastResults: dataSource.spotMeasurements.first { $0.kind == .breathingRate }.map { [.breathingRate: $0] } ?? [:]) { navigator.open(.measure($0)) }
                    }
                }
                card("Guided breathing") {
                    BreathingGuide(minutes: breatheRequest ?? 3, currentHeartRate: currentHeartRate)
                        .id(breatheRequest)
                }
                if dataSource.capabilities.spo2, let night = lastNight, let spo2 = night.series[.spo2], !spo2.isEmpty { oxygenCard(night: night, series: spo2) }
                WellnessTag().frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, RingTheme.Metrics.spacing16)
            .padding(.bottom, RingTheme.Metrics.spacing24)
        }
        .background(RingTheme.Background.base)
        .navigationTitle("Breathe")
        .refreshable { await dataSource.sync() }
        .onDisappear { breatheRequest = nil }
    }

    private var overnightCard: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RingEyebrow("Overnight breathing rate")
            if let overnight, let value = RingFormat.vital(.breathingRate, overnight.value) {
                HStack(alignment: .firstTextBaseline) {
                    RingVitalValue(value: value, unit: "brpm", size: .hero)
                    Spacer()
                    StateChip(state: overnight.state)
                }
                Text(sentence(overnight)).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).fixedSize(horizontal: false, vertical: true)
                Sparkline(values: overnight.history, band: overnight.typicalRange).frame(height: 36)
                RingProvenance(VitalKind.breathingRate.provenance + (RingFormat.range(overnight.typicalRange, kind: .breathingRate).map { " · usual \($0)" } ?? ""))
            } else if dataSource.connection == .unpaired {
                EmptyStateCard(.unpaired) { navigator.open(.pairing) }
            } else {
                EmptyStateCard(.notMeasured("Breathing rate"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
        .onTapGesture { if overnight?.value != nil { navigator.open(.metric(.breathingRate)) } }
    }

    private func sentence(_ reading: VitalReading) -> String {
        guard let value = reading.value else { return "" }
        let rate = "\(RingFormat.number(value, decimals: 0)) breaths a minute"
        switch reading.state {
        case .typical: return "Steady, \(rate), within your usual."
        case .outsideTypical: return "\(rate.capitalized), outside your usual range last night."
        case .learning: return "\(rate.capitalized). Your usual range appears after seven nights."
        case .notMeasured: return ""
        }
    }

    private func oxygenCard(night: SleepNight, series: [TimedSample]) -> some View {
        let lowest = series.map { $0.value }.min() ?? 0
        return VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RingEyebrow("Overnight oxygen")
            Chart {
                RectangleMark(yStart: .value("Low", 90), yEnd: .value("High", 100)).foregroundStyle(RingTheme.Chart.typicalBand)
                ForEach(series) { s in
                    LineMark(x: .value("Time", s.time), y: .value("SpO₂", s.value)).foregroundStyle(RingTheme.Chart.valueLine).interpolationMethod(.monotone)
                }
                ForEach(series.filter { $0.value < 90 }) { dip in
                    PointMark(x: .value("Time", dip.time), y: .value("Dip", dip.value)).foregroundStyle(RingTheme.Chart.outlier)
                }
            }
            .chartYScale(domain: (min(lowest, 88) - 2)...100)
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 2)) { _ in AxisGridLine().foregroundStyle(RingTheme.Chart.gridline); AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted))).foregroundStyle(RingTheme.Chart.axisLabel) } }
            .chartYAxis { AxisMarks(position: .trailing, values: [90, 95, 100]) { _ in AxisValueLabel().foregroundStyle(RingTheme.Chart.axisLabel) } }
            .frame(height: 120)
            .accessibilityLabel("Overnight blood oxygen")
            .accessibilityValue("Lowest \(Int(lowest)) percent, \(night.lowOxygenEvents) dips below 90 percent")
            HStack {
                Label("Lowest \(Int(lowest)) %", systemImage: "arrow.down.to.line").font(RingTypography.footnoteNumeric).foregroundStyle(RingTheme.Content.secondary)
                Spacer()
                Text("\(night.lowOxygenEvents) breathing disturbance\(night.lowOxygenEvents == 1 ? "" : "s")").font(RingTypography.footnote).foregroundStyle(night.lowOxygenEvents > 0 ? RingTheme.Status.fair : RingTheme.Content.tertiary)
            }
            RingProvenance("Dips below 90 % · wellness estimate, not a diagnosis")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
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
    NavigationStack { BreatheScreen(dataSource: MockRingDataSource()) }.preferredColorScheme(.dark)
}
#Preview("Learning · light") {
    NavigationStack { BreatheScreen(dataSource: MockRingDataSource(scenario: .learning(night: 2))) }.preferredColorScheme(.light)
}
