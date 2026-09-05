//
//  WearGuide.swift
//  RingExperience
//
//  How to wear the ring, drawn from the profile's hand and finger. Fit determines every night's
//  data quality, so this appears in onboarding, in the Not-worn state and in the Ring sheet.
//  The illustration is a soft graphite ring with the sensor bumps visible — never photoreal.
//

import SwiftUI

/// The ring, as a drawing. Sensor bumps face the palm side.
public struct RingIllustration: View {
    private let diameter: CGFloat
    private let showsHeartbeat: Bool

    public init(diameter: CGFloat = 120, showsHeartbeat: Bool = false) {
        self.diameter = diameter
        self.showsHeartbeat = showsHeartbeat
    }

    public var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [RingTheme.Content.secondary.opacity(0.9), RingTheme.Content.tertiary.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: diameter * 0.16
                )
            // Sensor bumps on the inside of the band, palm side (bottom).
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(RingTheme.Background.recessed)
                    .overlay(Circle().stroke(RingTheme.Separator.strong, lineWidth: 1))
                    .frame(width: diameter * 0.07, height: diameter * 0.07)
                    .offset(x: CGFloat(index - 1) * diameter * 0.12, y: diameter * 0.33)
            }
            if showsHeartbeat {
                Image(systemName: "heart.fill")
                    .font(.system(size: diameter * 0.2))
                    .foregroundStyle(RingTheme.Brand.gradient())
                    .ringBreathingPulse(scale: 0.92...1.08, opacity: 0.8...1.0)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

public struct WearGuide: View {
    private let hand: WearHand
    private let finger: WearFinger
    private let compact: Bool

    public init(hand: WearHand, finger: WearFinger, compact: Bool = false) {
        self.hand = hand
        self.finger = finger
        self.compact = compact
    }

    private var placement: String { "\(hand.label) hand · \(finger.label.lowercased()) finger" }

    public var body: some View {
        HStack(alignment: .top, spacing: RingTheme.Metrics.spacing16) {
            RingIllustration(diameter: compact ? 56 : 96)
            VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
                Text(placement)
                    .font(RingTypography.headline)
                    .foregroundStyle(RingTheme.Content.primary)
                if !compact {
                    guideLine("Sensor bumps facing your palm")
                    guideLine("Snug, but not tight — it should turn with a little effort")
                    guideLine("Wear it tonight; the first night starts the story")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How to wear: \(placement). Sensor bumps facing your palm, snug but not tight.")
    }

    private func guideLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: RingTheme.Metrics.spacing8) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(RingTheme.Status.optimal).padding(.top, 3)
            Text(text).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        WearGuide(hand: .left, finger: .index).ringCard()
        WearGuide(hand: .right, finger: .ring, compact: true).ringCard()
        RingIllustration(diameter: 140, showsHeartbeat: true)
    }
    .padding()
    .background(RingTheme.Background.base)
}
