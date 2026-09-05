//
//  ScoreRing.swift
//  RingExperience
//
//  The circular gauge that makes a ring app look like a ring. Three jobs, done equally well:
//  show a score; show that a baseline is still being learned ("night 3 of 7"); show abstention.
//  The value case is the only one that carries a number, so a nil score cannot reach it.
//
//  Motion: the arc fills with `RingMotion.ringFill` (Reduce Motion → short cross-fade). While
//  learning, the ring is a still dashed circle — accumulating, not scoring — never a spinner.
//

import SwiftUI

public enum ScoreRingSize: Equatable, Sendable {
    case hero, medium, compact

    /// docs/ux/06: hero 176 pt, medium 96, compact 44.
    public var baseDiameter: CGFloat {
        switch self {
        case .hero: return 176
        case .medium: return 96
        case .compact: return 44
        }
    }

    public var baseStroke: CGFloat {
        switch self {
        case .hero: return RingTheme.Metrics.ringStroke
        case .medium: return 10
        case .compact: return RingTheme.Metrics.ringStrokeCompact - 2
        }
    }

    var valueSize: RingVitalSize {
        switch self {
        case .hero: return .hero
        case .medium: return .medium
        case .compact: return .small
        }
    }

    var scalingTextStyle: Font.TextStyle {
        switch self {
        case .hero: return .largeTitle
        case .medium: return .title
        case .compact: return .title3
        }
    }
}

public enum ScoreRingState: Equatable {
    case value(fraction: Double, displayValue: String, unit: String?, metric: RingMetricState)
    case learning(night: Int, of: Int)
    case abstained(reason: String)
}

public struct ScoreRing: View {
    private let title: String
    private let state: ScoreRingState
    private let subtitle: String?
    private let size: ScoreRingSize
    @ScaledMetric private var scaledDiameter: CGFloat
    @State private var animatedFraction: Double = 0

    public init(title: String, state: ScoreRingState, subtitle: String? = nil, size: ScoreRingSize = .medium) {
        self.title = title
        self.state = state
        self.subtitle = subtitle
        self.size = size
        _scaledDiameter = ScaledMetric(wrappedValue: size.baseDiameter, relativeTo: size.scalingTextStyle)
    }

    /// The one mapping from a `Score` so every screen renders the same treatment.
    public init(score: Score, subtitle: String? = nil, size: ScoreRingSize = .medium) {
        let ringState: ScoreRingState
        switch score.state {
        case let .measured(metric):
            ringState = .value(fraction: Double(score.value ?? 0) / 100, displayValue: score.value.map { "\($0)" } ?? "", unit: nil, metric: metric)
        case let .learning(nights, needed):
            ringState = .learning(night: nights, of: needed)
        case let .abstained(reason):
            ringState = .abstained(reason: reason)
        }
        self.init(title: score.kind.title, state: ringState, subtitle: subtitle, size: size)
    }

    /// Ring growth is capped at 1.35× so a hero ring stays on a 375 pt screen at AX5.
    private var diameter: CGFloat { min(scaledDiameter, size.baseDiameter * 1.35) }
    private var strokeWidth: CGFloat { size.baseStroke * diameter / size.baseDiameter }

    private var targetFraction: Double {
        switch state {
        case let .value(fraction, _, _, _): return fraction.isFinite ? min(max(fraction, 0), 1) : 0
        case .learning, .abstained: return 0
        }
    }

    private var metric: RingMetricState {
        if case let .value(_, _, _, m) = state { return m }
        return .abstained
    }

    public var body: some View {
        VStack(spacing: RingTheme.Metrics.spacing8) {
            ZStack {
                Circle().stroke(RingTheme.Background.recessed, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                arc
                centre.padding(strokeWidth * 1.4)
            }
            .frame(width: diameter, height: diameter)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValue)

            if size != .compact, let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(RingTypography.footnote)
                    .foregroundStyle(RingTheme.Content.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            if size == .compact {
                Text(title)
                    .font(RingTypography.caption)
                    .foregroundStyle(RingTheme.Content.secondary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
        }
        .onAppear { animatedFraction = targetFraction }
        .onChange(of: targetFraction) { _, newValue in animatedFraction = newValue }
    }

    @ViewBuilder
    private var arc: some View {
        switch state {
        case .abstained:
            EmptyView()     // no arc: a partial ring is a measurement claim
        case .learning:
            Circle().stroke(RingTheme.Status.abstained, style: StrokeStyle(lineWidth: strokeWidth * 0.62, lineCap: .round, dash: [strokeWidth * 0.5, strokeWidth * 0.85]))
        case .value:
            Circle()
                .trim(from: 0, to: animatedFraction)
                .stroke(metric.color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .ringMotion(size == .hero ? RingMotion.ringFillHero : RingMotion.ringFill, value: animatedFraction)
        }
    }

    @ViewBuilder
    private var centre: some View {
        VStack(spacing: 2) {
            switch state {
            case let .value(_, display, unit, _):
                RingVitalValue(value: display, unit: unit, size: size.valueSize)
                    .ringNumericTransition()
                if size == .hero {
                    Text(title).font(RingTypography.footnote).foregroundStyle(RingTheme.Content.secondary)
                }
            case let .learning(night, of):
                if size == .compact {
                    Text("\(night)/\(of)").font(RingTypography.caption).fontWeight(.semibold).monospacedDigit().foregroundStyle(RingTheme.Content.secondary)
                } else {
                    Text("\(night) of \(of)").font(size == .hero ? RingTypography.title2 : RingTypography.subheadline).monospacedDigit().foregroundStyle(RingTheme.Content.secondary)
                    Text("nights").font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary)
                }
            case .abstained:
                RingVitalValue(value: nil, size: size.valueSize)
                if size == .hero {
                    Text(title).font(RingTypography.footnote).foregroundStyle(RingTheme.Content.secondary)
                }
            }
        }
        .minimumScaleFactor(0.6)
    }

    private var accessibilityValue: String {
        switch state {
        case let .value(_, display, unit, metric):
            return "\(display)\(unit.map { " \($0)" } ?? ""), \(metric.accessibilityLabel)" + (subtitle.map { ". \($0)" } ?? "")
        case let .learning(night, of):
            return "Learning your usual. Night \(night) of \(of). A score appears once your baseline is established."
        case let .abstained(reason):
            return "Not enough signal to score. \(reason)"
        }
    }
}

#Preview("Rings") {
    VStack(spacing: 32) {
        ScoreRing(title: "Readiness", state: .value(fraction: 0.82, displayValue: "82", unit: nil, metric: .good), subtitle: "vs your 14-night usual", size: .hero)
        HStack(spacing: 24) {
            ScoreRing(title: "Sleep", state: .learning(night: 3, of: 7), size: .medium)
            ScoreRing(title: "Activity", state: .abstained(reason: "No steps yet"), size: .medium)
            ScoreRing(title: "Readiness", state: .value(fraction: 0.6, displayValue: "60", unit: nil, metric: .fair), size: .compact)
        }
    }
    .padding()
    .background(RingTheme.Background.base)
}
