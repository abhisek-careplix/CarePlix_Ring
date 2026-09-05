//
//  StateChip.swift
//  RingExperience
//
//  A pill that says where a value sits — with colour, a symbol AND a label, so the state survives
//  colour-blindness, greyscale and VoiceOver. Copy is fixed by docs/ux/05:
//  Typical · Outside typical · Learning · Not measured (vitals) and Optimal · Good · Fair · Low ·
//  Not enough signal (scores).
//

import SwiftUI

public struct StateChip: View {
    private let label: String
    private let symbol: String
    private let color: Color
    private let detail: String?
    private let compact: Bool

    /// A vital's chip. `Learning` carries "night n of 7" as detail at full size.
    public init(state: RangeState, compact: Bool = false) {
        label = state.label
        symbol = state.symbol
        color = state.metric.color
        if case let .learning(n, needed) = state { detail = "night \(n) of \(needed)" } else { detail = nil }
        self.compact = compact
    }

    /// A score's chip.
    public init(metric: RingMetricState, compact: Bool = false) {
        label = metric.label
        symbol = metric.symbol
        color = metric.color
        detail = nil
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: RingTheme.Metrics.spacing4) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
            Text(label)
                .font(compact ? RingTypography.caption2 : RingTypography.caption)
                .fontWeight(.semibold)
            if !compact, let detail {
                Text("· \(detail)")
                    .font(RingTypography.caption2)
                    .foregroundStyle(RingTheme.Content.tertiary)
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? RingTheme.Metrics.spacing8 : RingTheme.Metrics.spacing12)
        .padding(.vertical, compact ? 3 : 5)
        .background(color.opacity(0.14), in: Capsule())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\(label), \($0)" } ?? label)
    }
}

#Preview("Chips") {
    VStack(alignment: .leading, spacing: 12) {
        StateChip(state: .typical)
        StateChip(state: .outsideTypical)
        StateChip(state: .learning(nights: 3, needed: 7))
        StateChip(state: .notMeasured)
        StateChip(metric: .optimal)
        StateChip(metric: .poor, compact: true)
    }
    .padding()
    .background(RingTheme.Background.base)
}
