//
//  VitalTile.swift
//  RingExperience
//
//  A doorway, not a destination: one number, one state word, one trend, everything else behind
//  the tap. Renders only for capabilities the ring reports (the caller gates), and can always
//  render an honest state — Learning · night n of 7, Not measured — instead of a zero.
//

import SwiftUI

public struct VitalTile: View {
    private let reading: VitalReading
    private let onTap: (() -> Void)?

    public init(reading: VitalReading, onTap: (() -> Void)? = nil) {
        self.reading = reading
        self.onTap = onTap
    }

    private var displayValue: String? { RingFormat.vital(reading.kind, reading.value) }

    public var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
                HStack(spacing: RingTheme.Metrics.spacing4) {
                    Image(systemName: reading.kind.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RingTheme.Content.tertiary)
                    Text(reading.kind.title)
                        .font(RingTypography.caption)
                        .foregroundStyle(RingTheme.Content.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                RingVitalValue(value: displayValue, unit: RingFormat.vitalUnit(reading.kind), size: .medium, abstentionNote: reading.state.spoken)

                StateChip(state: reading.state, compact: true)

                Sparkline(values: reading.history, band: reading.typicalRange, lineColor: reading.state.metric == .abstained ? RingTheme.Content.tertiary : RingTheme.Content.secondary)
                    .frame(height: 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ringCard(padding: RingTheme.Metrics.spacing12)
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(onTap == nil ? "" : "Shows detail and trend")
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    /// "Resting heart rate 58 beats per minute, typical for you, measured last night."
    private var accessibilityLabel: String {
        var parts = [reading.kind.title]
        if let displayValue {
            parts.append("\(displayValue) \(reading.kind.spokenUnit)")
        }
        parts.append(reading.state.spoken)
        if reading.measuredAt != nil { parts.append("measured last night") }
        return parts.joined(separator: ", ")
    }
}

#Preview("Tiles") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        VitalTile(reading: VitalReading(kind: .restingHeartRate, value: 58, state: .typical, typicalRange: 54...61, history: [56, 58, 55, 57, 60, 54, 58], measuredAt: Date()), onTap: {})
        VitalTile(reading: VitalReading(kind: .hrv, value: 31, state: .outsideTypical, typicalRange: 38...52, history: [44, 46, 41, 48, 39, 45, 31], measuredAt: Date()), onTap: {})
        VitalTile(reading: VitalReading(kind: .spo2, value: 96, state: .learning(nights: 3, needed: 7), history: [97, 96, 96]), onTap: {})
        VitalTile(reading: .notMeasured(.skinTempDelta))
    }
    .padding()
    .background(RingTheme.Background.base)
}
