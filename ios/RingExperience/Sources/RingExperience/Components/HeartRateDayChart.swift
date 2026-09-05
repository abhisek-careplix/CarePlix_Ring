//
//  HeartRateDayChart.swift
//  RingExperience
//
//  Today's heart rate from 5-minute origin data, 00:00 → now: a line with the resting band
//  behind it, spot tests as dots, and gaps as gaps (no line is drawn across a missing slot). A
//  scrubber pill follows the finger. The chart also exposes an audio-graph descriptor so
//  VoiceOver users can hear the day's shape.
//

import SwiftUI
import Charts
import Accessibility

public struct HeartRateDayChart: View {
    private let samples: [TimedSample]
    private let restingRange: ClosedRange<Double>?
    private let spots: [SpotMeasurement]
    private let now: Date
    @State private var scrub: TimedSample?

    public init(samples: [TimedSample], restingRange: ClosedRange<Double>?, spots: [SpotMeasurement], now: Date = Date()) {
        self.samples = samples.sorted { $0.time < $1.time }
        self.restingRange = restingRange
        self.spots = spots.filter { $0.kind == .heartRate }
        self.now = now
    }

    /// Runs of samples with no gap larger than 10 minutes between them.
    private var segments: [[TimedSample]] {
        var result: [[TimedSample]] = []
        var current: [TimedSample] = []
        for sample in samples {
            if let last = current.last, sample.time.timeIntervalSince(last.time) > 10 * 60 {
                result.append(current)
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private var dayStart: Date { Calendar.current.startOfDay(for: now) }
    private var dayEnd: Date { dayStart.addingTimeInterval(86_400) }

    private var yDomain: ClosedRange<Double> {
        var lo = samples.map { $0.value }.min() ?? 50, hi = samples.map { $0.value }.max() ?? 100
        if let restingRange { lo = min(lo, restingRange.lowerBound) }
        for s in spots { lo = min(lo, s.value); hi = max(hi, s.value) }
        return (lo - 8)...(hi + 8)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
            HStack {
                if let scrub {
                    Text("\(Int(scrub.value)) bpm · \(RingFormat.clock(scrub.time))")
                        .font(RingTypography.footnoteNumeric).foregroundStyle(RingTheme.Content.primary)
                        .padding(.horizontal, RingTheme.Metrics.spacing8).padding(.vertical, 4)
                        .background(RingTheme.Background.recessed, in: Capsule())
                } else if let last = samples.last {
                    Text("\(Int(last.value)) bpm · \(RingFormat.relative(last.time, now: now))")
                        .font(RingTypography.footnoteNumeric).foregroundStyle(RingTheme.Content.secondary)
                } else {
                    Text("No heart rate yet today").font(RingTypography.footnote).foregroundStyle(RingTheme.Content.tertiary)
                }
                Spacer()
                if let restingRange {
                    Text("Resting \(Int(restingRange.lowerBound))–\(Int(restingRange.upperBound))").font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary)
                }
            }
            .ringMotion(RingMotion.valueChange, value: scrub?.time)

            Chart {
                if let restingRange {
                    RectangleMark(yStart: .value("Low", restingRange.lowerBound), yEnd: .value("High", restingRange.upperBound))
                        .foregroundStyle(RingTheme.Chart.typicalBand)
                }
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    ForEach(segment) { sample in
                        LineMark(x: .value("Time", sample.time), y: .value("Heart rate", sample.value), series: .value("Segment", index))
                            .foregroundStyle(RingTheme.Chart.valueLine)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.monotone)
                    }
                }
                ForEach(spots) { spot in
                    PointMark(x: .value("Time", spot.at), y: .value("Spot test", spot.value))
                        .foregroundStyle(RingTheme.Brand.coral)
                        .symbolSize(40)
                }
                if let scrub {
                    RuleMark(x: .value("Scrub", scrub.time)).foregroundStyle(RingTheme.Separator.strong).lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Scrub", scrub.time), y: .value("Value", scrub.value)).foregroundStyle(RingTheme.Content.primary).symbolSize(50)
                }
            }
            .chartXScale(domain: dayStart...dayEnd)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine().foregroundStyle(RingTheme.Chart.gridline)
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted))).foregroundStyle(RingTheme.Chart.axisLabel)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(RingTheme.Chart.gridline)
                    AxisValueLabel().foregroundStyle(RingTheme.Chart.axisLabel)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let origin = geo[proxy.plotAreaFrame].origin
                                    guard let date: Date = proxy.value(atX: value.location.x - origin.x) else { return }
                                    scrub = samples.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
                                }
                                .onEnded { _ in scrub = nil }
                        )
                }
            }
            .frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Heart rate today")
            .accessibilityValue(accessibilityValue)
            .accessibilityChartDescriptor(HeartRateChartDescriptor(samples: samples, dayStart: dayStart, yDomain: yDomain))
        }
    }

    private var accessibilityValue: String {
        guard let lo = samples.map({ $0.value }).min(), let hi = samples.map({ $0.value }).max(), let last = samples.last else { return "No readings yet today" }
        var text = "From \(Int(lo)) to \(Int(hi)) beats per minute, latest \(Int(last.value)) at \(RingFormat.clock(last.time))"
        if segments.count > 1 { text += ", with \(segments.count - 1) gaps where the ring was not worn or not read" }
        if !spots.isEmpty { text += ", \(spots.count) spot tests" }
        return text
    }
}

/// Audio-graph description: hours on x, bpm on y.
struct HeartRateChartDescriptor: AXChartDescriptorRepresentable {
    let samples: [TimedSample]
    let dayStart: Date
    let yDomain: ClosedRange<Double>

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXNumericDataAxisDescriptor(title: "Time of day", range: 0...24, gridlinePositions: [0, 6, 12, 18, 24]) { "\(Int($0)):00" }
        let yAxis = AXNumericDataAxisDescriptor(title: "Heart rate", range: yDomain, gridlinePositions: []) { "\(Int($0)) beats per minute" }
        let points = samples.map { AXDataPoint(x: $0.time.timeIntervalSince(dayStart) / 3600, y: $0.value) }
        let series = AXDataSeriesDescriptor(name: "Heart rate", isContinuous: true, dataPoints: points)
        return AXChartDescriptor(title: "Heart rate today", summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}

#Preview {
    let mock = MockRingDataSource()
    return HeartRateDayChart(samples: mock.heartRateToday, restingRange: mock.today.vitals.first { $0.kind == .restingHeartRate }?.typicalRange, spots: mock.spotMeasurements)
        .ringCard().padding().background(RingTheme.Background.base)
}
