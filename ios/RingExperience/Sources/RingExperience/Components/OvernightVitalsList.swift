//
//  OvernightVitalsList.swift
//  RingExperience
//
//  One row per overnight vital: the night's line, the night's value, the typical band. Chart
//  grammar is fixed — continuous → line with the 10th–90th band in the recessed tone, outliers
//  and low-oxygen dips in `status.fair`. Rows only exist for vitals the ring measured.
//

import SwiftUI
import Charts

public struct OvernightVitalsList: View {
    private let night: SleepNight
    private let onSelect: ((VitalReading) -> Void)?

    public init(night: SleepNight, onSelect: ((VitalReading) -> Void)? = nil) {
        self.night = night
        self.onSelect = onSelect
    }

    private var readings: [VitalReading] {
        night.overnightVitals.filter { $0.kind != .sleepDuration }
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                Button { onSelect?(reading) } label: { row(reading) }
                    .buttonStyle(.plain)
                    .disabled(onSelect == nil)
                if index < readings.count - 1 {
                    Rectangle().fill(RingTheme.Separator.hairline).frame(height: RingTheme.Metrics.hairline)
                }
            }
        }
    }

    private func row(_ reading: VitalReading) -> some View {
        let series = night.series[reading.kind] ?? []
        return HStack(spacing: RingTheme.Metrics.spacing12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(reading.kind.title).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
                StateChip(state: reading.state, compact: true)
                if let band = RingFormat.range(reading.typicalRange, kind: reading.kind) {
                    Text("Usual \(band)").font(RingTypography.caption2).foregroundStyle(RingTheme.Content.tertiary)
                }
            }
            .frame(width: 118, alignment: .leading)

            line(series, reading: reading)
                .frame(height: 44)

            RingVitalValue(value: RingFormat.vital(reading.kind, reading.value), unit: RingFormat.vitalUnit(reading.kind), size: .small, abstentionNote: reading.state.spoken)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, RingTheme.Metrics.spacing12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.kind.title), \(RingFormat.vital(reading.kind, reading.value).map { "\($0) \(reading.kind.spokenUnit)" } ?? "not measured"), \(reading.state.spoken)")
    }

    @ViewBuilder
    private func line(_ series: [TimedSample], reading: VitalReading) -> some View {
        if series.count < 2 {
            Text("No data").font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary).frame(maxWidth: .infinity)
        } else {
            Chart {
                if let band = seriesBand(reading, series: series) {
                    RectangleMark(yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                        .foregroundStyle(RingTheme.Chart.typicalBand)
                }
                ForEach(series) { sample in
                    LineMark(x: .value("Time", sample.time), y: .value(reading.kind.title, sample.value))
                        .foregroundStyle(RingTheme.Chart.valueLine)
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                        .interpolationMethod(.monotone)
                }
                if reading.kind == .spo2 {
                    ForEach(series.filter { $0.value < 90 }) { dip in
                        PointMark(x: .value("Time", dip.time), y: .value("Dip", dip.value))
                            .foregroundStyle(RingTheme.Chart.outlier)
                            .symbolSize(18)
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: yDomain(series, reading: reading))
            .accessibilityHidden(true)
        }
    }

    /// The nightly typical band only makes sense against a series of the same quantity; skin
    /// temperature series are absolute, so its band is not drawn behind the line.
    private func seriesBand(_ reading: VitalReading, series: [TimedSample]) -> ClosedRange<Double>? {
        guard reading.kind != .skinTempDelta else { return nil }
        return reading.typicalRange
    }

    private func yDomain(_ series: [TimedSample], reading: VitalReading) -> ClosedRange<Double> {
        var lo = series.map { $0.value }.min() ?? 0, hi = series.map { $0.value }.max() ?? 1
        if let band = seriesBand(reading, series: series) { lo = min(lo, band.lowerBound); hi = max(hi, band.upperBound) }
        let pad = max((hi - lo) * 0.15, 0.5)
        return (lo - pad)...(hi + pad)
    }
}

#Preview {
    OvernightVitalsList(night: MockRingDataSource().nights.last!, onSelect: { _ in }).ringCard().padding().background(RingTheme.Background.base)
}
