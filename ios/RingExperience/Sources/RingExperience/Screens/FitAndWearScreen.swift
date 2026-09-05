//
//  FitAndWearScreen.swift
//  RingExperience
//
//  J1 step 5. Sensor bumps facing the palm, snug but not tight, wear it tonight — and the first
//  battery read as round-trip proof: "64 % · enough for about 3 nights".
//

import SwiftUI

public struct FitAndWearScreen: View {
    private let profile: UserProfile
    private let battery: Battery?
    private let onDone: () -> Void

    public init(profile: UserProfile, battery: Battery?, onDone: @escaping () -> Void) {
        self.profile = profile
        self.battery = battery
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing24) {
                    Text("Fit and wear").font(RingTypography.largeTitle).foregroundStyle(RingTheme.Content.primary)
                    WearGuide(hand: profile.wearHand, finger: profile.wearFinger).ringCard()
                    VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
                        RingEyebrow("Battery")
                        HStack(spacing: RingTheme.Metrics.spacing16) {
                            BatteryGauge(battery: battery, size: .compact)
                            Text(batteryLine).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ringCard()
                    VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
                        RingEyebrow("What happens next")
                        Text("Tonight · sleep with the ring on").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
                        Text("Tomorrow \(RingFormat.clock(profile.wakeTime)) · your first Sleep page").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
                        Text("Night 7 · your typical ranges and Readiness").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ringCard()
                }
                .padding(RingTheme.Metrics.spacing24)
            }
            Button("Wear it tonight", action: onDone).buttonStyle(RingPrimaryButtonStyle()).padding(RingTheme.Metrics.spacing24).background(RingTheme.Background.elevated)
        }
        .background(RingTheme.Background.base)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var batteryLine: String {
        guard let battery else { return "Battery reads once the ring is connected." }
        let level = battery.percent.map { "\($0) %" } ?? battery.bars.map { "\($0) of 4 bars" } ?? "Unknown"
        if let forecast = RingFormat.forecast(nights: battery.forecastNights) { return "\(level) · enough for \(forecast.lowercased())" }
        return battery.isEnoughForTonight ? "\(level) · enough for tonight" : "\(level) · charge before bed"
    }
}

#Preview { NavigationStack { FitAndWearScreen(profile: .draft(), battery: Battery(percent: 64, forecastNights: 3.1), onDone: {}) } }
