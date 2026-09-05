//
//  StageBars.swift
//  RingExperience
//
//  Four horizontal bars: duration and share of the night, each against the user's usual share.
//  "Usual" comes from the previous nights; before there are enough, the comparison is omitted
//  rather than invented.
//

import SwiftUI

public struct StageBars: View {
    private let night: SleepNight
    private let usualShares: [SleepStage: Double]?

    /// - Parameter usualShares: each stage's usual fraction of the night (0…1), or nil while learning.
    public init(night: SleepNight, usualShares: [SleepStage: Double]? = nil) {
        self.night = night
        self.usualShares = usualShares
    }

    private var stages: [SleepStage] { night.isPrecise ? [.deep, .light, .rem, .awake] : [.deep, .light, .awake] }
    private var recorded: Int { max(night.stages.filter { $0 != .gap }.count, 1) }

    public var body: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            ForEach(stages, id: \.self) { stage in
                let minutes = night.stageTotals[stage] ?? 0
                let share = Double(minutes) / Double(recorded)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(stage.label).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
                        Spacer()
                        Text(RingFormat.duration(minutes: minutes)).font(RingTypography.footnoteNumeric).foregroundStyle(RingTheme.Content.secondary)
                        Text(comparison(share: share, stage: stage)).font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(RingTheme.Background.recessed)
                            Capsule().fill(Hypnogram.color(for: stage)).frame(width: max(geo.size.width * CGFloat(min(share / 0.6, 1)), 4))
                            if let usual = usualShares?[stage] {
                                Rectangle().fill(RingTheme.Content.tertiary).frame(width: 2, height: 12)
                                    .offset(x: geo.size.width * CGFloat(min(usual / 0.6, 1)) - 1)
                            }
                        }
                    }
                    .frame(height: 8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(stage.label) \(RingFormat.duration(minutes: minutes)), \(Int((share * 100).rounded())) percent of the night\(usualShares?[stage].map { ", usually \(Int(($0 * 100).rounded())) percent" } ?? "")")
            }
        }
    }

    private func comparison(share: Double, stage: SleepStage) -> String {
        let pct = Int((share * 100).rounded())
        guard let usual = usualShares?[stage] else { return "\(pct) %" }
        return "\(pct) % · usual \(Int((usual * 100).rounded())) %"
    }
}

#Preview {
    let night = MockRingDataSource().nights.last!
    return StageBars(night: night, usualShares: [.deep: 0.2, .light: 0.5, .rem: 0.22, .awake: 0.08]).ringCard().padding().background(RingTheme.Background.base)
}
