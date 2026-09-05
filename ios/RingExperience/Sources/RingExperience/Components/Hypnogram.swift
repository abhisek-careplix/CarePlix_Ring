//
//  Hypnogram.swift
//  RingExperience
//
//  Four lanes — Awake · REM · Light · Deep — from the per-minute sleep line. Gaps are gaps: a
//  minute the ring did not record draws nothing in a lane and a faint full-height well, and is
//  never interpolated. A battery death is a marker at the point of loss, so the user can see
//  where the night stopped rather than wonder why it is short.
//

import SwiftUI
import Charts

public struct Hypnogram: View {
    private let night: SleepNight

    public init(night: SleepNight) { self.night = night }

    /// Consecutive minutes of one stage, as one block.
    struct StageRun: Identifiable {
        let stage: SleepStage
        let start: Date
        let end: Date
        var id: Date { start }
    }

    private var runs: [StageRun] {
        var result: [StageRun] = []
        var current: SleepStage?
        var runStart = 0
        for (index, stage) in night.stages.enumerated() {
            if stage != current {
                if let c = current { result.append(StageRun(stage: c, start: minute(runStart), end: minute(index))) }
                current = stage
                runStart = index
            }
        }
        if let c = current { result.append(StageRun(stage: c, start: minute(runStart), end: minute(night.stages.count))) }
        return result
    }

    private func minute(_ m: Int) -> Date { night.bedtime.addingTimeInterval(Double(m) * 60) }

    private var lanes: [String] {
        (night.isPrecise ? SleepStage.lanes : [.awake, .light, .deep]).map { $0.label }
    }

    static func color(for stage: SleepStage) -> Color {
        switch stage {
        case .deep: return RingTheme.Sleep.deep
        case .light: return RingTheme.Sleep.light
        case .rem: return RingTheme.Sleep.rem
        case .awake: return RingTheme.Sleep.awake
        case .gap: return RingTheme.Sleep.gap
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
            Chart {
                ForEach(runs) { run in
                    if run.stage == .gap {
                        RectangleMark(xStart: .value("Start", run.start), xEnd: .value("End", run.end))
                            .foregroundStyle(RingTheme.Chart.noData.opacity(0.6))
                    } else {
                        RectangleMark(xStart: .value("Start", run.start), xEnd: .value("End", run.end), y: .value("Stage", run.stage.label), height: .ratio(0.7))
                            .foregroundStyle(Self.color(for: run.stage))
                            .cornerRadius(2)
                    }
                }
                ForEach(Array(night.notWornRanges.enumerated()), id: \.offset) { _, range in
                    RectangleMark(xStart: .value("Start", range.lowerBound), xEnd: .value("End", range.upperBound))
                        .foregroundStyle(RingTheme.Status.abstained.opacity(0.12))
                }
                if let loss = night.batteryLossAt {
                    RuleMark(x: .value("Battery ran out", loss))
                        .foregroundStyle(RingTheme.Status.poor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Ran out \(RingFormat.clock(loss))")
                                .font(RingTypography.caption2).foregroundStyle(RingTheme.Status.poor)
                        }
                }
            }
            .chartYScale(domain: lanes)
            .chartXScale(domain: night.bedtime...night.wake)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour)) { _ in
                    AxisGridLine().foregroundStyle(RingTheme.Chart.gridline)
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)), centered: false)
                        .foregroundStyle(RingTheme.Chart.axisLabel)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().foregroundStyle(RingTheme.Chart.axisLabel)
                }
            }
            .frame(height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sleep stages")
            .accessibilityValue(accessibilityValue)

            legend
        }
    }

    private var legend: some View {
        HStack(spacing: RingTheme.Metrics.spacing12) {
            ForEach(night.isPrecise ? SleepStage.lanes : [.awake, .light, .deep], id: \.self) { stage in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Self.color(for: stage)).frame(width: 10, height: 10)
                    Text(stage.label).font(RingTypography.caption2).foregroundStyle(RingTheme.Content.tertiary)
                }
            }
            if night.stages.contains(.gap) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(RingTheme.Chart.noData).frame(width: 10, height: 10)
                    Text("No data").font(RingTypography.caption2).foregroundStyle(RingTheme.Content.tertiary)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var accessibilityValue: String {
        var parts = SleepStage.lanes.compactMap { stage -> String? in
            guard let minutes = night.stageTotals[stage], minutes > 0 else { return nil }
            return "\(stage.label) \(RingFormat.duration(minutes: minutes))"
        }
        if let gap = night.stageTotals[.gap], gap > 0 { parts.append("no data for \(RingFormat.duration(minutes: gap))") }
        if let loss = night.batteryLossAt { parts.append("battery ran out at \(RingFormat.clock(loss))") }
        parts.append("from \(RingFormat.clock(night.bedtime)) to \(RingFormat.clock(night.wake))")
        return parts.joined(separator: ", ")
    }
}

#Preview {
    let mock = MockRingDataSource(scenario: .batteryDied)
    return VStack {
        if let night = mock.nights.last { Hypnogram(night: night).ringCard() }
        if let night = MockRingDataSource(scenario: .established).nights.last { Hypnogram(night: night).ringCard() }
    }
    .padding()
    .background(RingTheme.Background.base)
}
