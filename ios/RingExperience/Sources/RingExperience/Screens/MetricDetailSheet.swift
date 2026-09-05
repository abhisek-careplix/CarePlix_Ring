//
//  MetricDetailSheet.swift
//  RingExperience
//
//  One vital, over time: the night's value with its state, a 7 / 14 / 30-night chart against the
//  typical band, and how it was measured. Outliers are coloured, never diagnosed.
//

import SwiftUI
import Charts

public struct MetricDetailSheet: View {
    private let kind: VitalKind
    private let nights: [SleepNight]
    private let today: TodayDashboard
    @Environment(\.dismiss) private var dismiss
    @State private var window = 14

    public init(kind: VitalKind, nights: [SleepNight], today: TodayDashboard) {
        self.kind = kind
        self.nights = nights
        self.today = today
    }

    private var current: VitalReading? { today.vitals.first { $0.kind == kind } }

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        let outside: Bool
        var id: Date { date }
    }

    private var points: [Point] {
        nights.suffix(window).compactMap { night in
            guard let reading = night.vital(kind), let value = reading.value else { return nil }
            return Point(date: night.date, value: value, outside: reading.state == .outsideTypical)
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: RingTheme.Metrics.spacing16) {
                    headline
                    chartCard
                    VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
                        RingEyebrow("How it was measured")
                        Text(kind.provenance).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).fixedSize(horizontal: false, vertical: true)
                        Text("Your typical range is the 10th–90th percentile of your last 14 nights. It needs seven nights to exist.").font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ringCard()
                    WellnessTag().frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(RingTheme.Metrics.spacing16)
            }
            .background(RingTheme.Background.base)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
            RingEyebrow("Last night")
            HStack(alignment: .firstTextBaseline) {
                RingVitalValue(value: RingFormat.vital(kind, current?.value), unit: RingFormat.vitalUnit(kind), size: .hero, abstentionNote: current?.state.spoken ?? "not measured")
                Spacer()
                StateChip(state: current?.state ?? .notMeasured)
            }
            if let band = RingFormat.range(current?.typicalRange, kind: kind) {
                Text("Your usual \(band)").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary)
            }
            if let at = current?.measuredAt { RingProvenance("Measured \(RingFormat.day(at)) · \(kind.provenance.lowercased())") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            Picker("Range", selection: $window) {
                Text("Week").tag(7); Text("Two weeks").tag(14); Text("Month").tag(30)
            }
            .pickerStyle(.segmented)
            if points.count < 2 {
                Text("Not enough nights yet for a trend.").font(RingTypography.footnote).foregroundStyle(RingTheme.Content.tertiary)
            } else {
                Chart {
                    if let band = current?.typicalRange {
                        RectangleMark(yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound)).foregroundStyle(RingTheme.Chart.typicalBand)
                    }
                    ForEach(points) { p in
                        LineMark(x: .value("Night", p.date), y: .value(kind.title, p.value)).foregroundStyle(RingTheme.Chart.valueLine).interpolationMethod(.monotone)
                        PointMark(x: .value("Night", p.date), y: .value(kind.title, p.value)).foregroundStyle(p.outside ? RingTheme.Chart.outlier : RingTheme.Chart.valueLine).symbolSize(p.outside ? 40 : 20)
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: max(window / 7, 1))) { _ in AxisGridLine().foregroundStyle(RingTheme.Chart.gridline); AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(RingTheme.Chart.axisLabel) } }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(RingTheme.Chart.gridline); AxisValueLabel().foregroundStyle(RingTheme.Chart.axisLabel) } }
                .frame(height: 180)
                .accessibilityLabel("\(kind.title) over \(points.count) nights")
                .accessibilityValue(accessibilitySummary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
    }

    private var accessibilitySummary: String {
        let values = points.map { $0.value }
        guard let lo = values.min(), let hi = values.max() else { return "" }
        let outside = points.filter { $0.outside }.count
        return "From \(RingFormat.vital(kind, lo) ?? "") to \(RingFormat.vital(kind, hi) ?? "") \(kind.spokenUnit), \(outside) nights outside your typical range"
    }
}

#Preview("HRV · dark") {
    let mock = MockRingDataSource()
    return MetricDetailSheet(kind: .hrv, nights: mock.nights, today: mock.today).preferredColorScheme(.dark)
}
#Preview("Learning · light") {
    let mock = MockRingDataSource(scenario: .learning(night: 3))
    return MetricDetailSheet(kind: .restingHeartRate, nights: mock.nights, today: mock.today).preferredColorScheme(.light)
}
