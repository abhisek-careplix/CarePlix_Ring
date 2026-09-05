//
//  BatteryGauge.swift
//  RingExperience
//
//  A ring-shaped battery gauge with the percent numeral and a forecast line. Exists because a
//  ring that dies at 2 a.m. silently loses the night, which is the whole product (audit A3).
//  Modes: ok / low (< 30 %) / critical (< 15 %) / charging (animated fill) / bars (0–4) / unknown.
//

import SwiftUI

public struct BatteryGauge: View {
    public enum Size { case compact, large }

    private let battery: Battery?
    private let size: Size
    @State private var chargingPhase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(battery: Battery?, size: Size = .large) {
        self.battery = battery
        self.size = size
    }

    private var diameter: CGFloat { size == .large ? 132 : 44 }
    private var stroke: CGFloat { size == .large ? 12 : 5 }

    private var fraction: Double {
        guard let battery else { return 0 }
        if let percent = battery.percent { return Double(percent) / 100 }
        if let bars = battery.bars { return Double(bars) / 4 }
        return 0
    }

    private var color: Color {
        guard let battery else { return RingTheme.Status.abstained }
        switch battery.level {
        case .ok: return RingTheme.Battery.ok
        case .low: return RingTheme.Battery.low
        case .critical: return RingTheme.Battery.critical
        case .charging: return RingTheme.Battery.charging
        }
    }

    public var body: some View {
        VStack(spacing: RingTheme.Metrics.spacing8) {
            ZStack {
                Circle().stroke(RingTheme.Background.recessed, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .ringMotion(RingMotion.ringFill, value: fraction)
                    .opacity(battery?.isCharging == true && !reduceMotion ? (chargingPhase ? 1 : 0.55) : 1)
                    .animation(battery?.isCharging == true ? RingMotion.breathingPulse.resolved(reduceMotion: reduceMotion) : nil, value: chargingPhase)
                centre
            }
            .frame(width: diameter, height: diameter)

            if size == .large, let forecast {
                Text(forecast)
                    .font(RingTypography.subheadline)
                    .foregroundStyle(RingTheme.Content.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .onAppear { if battery?.isCharging == true { chargingPhase = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ring battery")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var centre: some View {
        if let battery {
            VStack(spacing: 0) {
                if size == .large {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        if let percent = battery.percent {
                            Text("\(percent)").ringVitalNumber(.large)
                            RingUnitSuffix("%", size: .large)
                        } else if let bars = battery.bars {
                            Text("\(bars)").ringVitalNumber(.large)
                            RingUnitSuffix("of 4", size: .large)
                        }
                    }
                    .foregroundStyle(RingTheme.Content.primary)
                    if battery.isCharging {
                        Label("Charging", systemImage: "bolt.fill").font(RingTypography.caption).foregroundStyle(RingTheme.Battery.charging).labelStyle(.titleAndIcon)
                    }
                } else {
                    Image(systemName: battery.isCharging ? "bolt.fill" : symbol(for: battery))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }
            }
        } else {
            Text("\u{2013}\u{2013}").ringVitalNumber(size == .large ? .large : .small).foregroundStyle(RingTheme.Status.abstained)
        }
    }

    private func symbol(for battery: Battery) -> String {
        switch battery.level {
        case .ok: return "battery.100percent"
        case .low: return "battery.25percent"
        case .critical: return "battery.0percent"
        case .charging: return "bolt.fill"
        }
    }

    private var forecast: String? {
        guard let battery else { return "Battery unknown" }
        if battery.isCharging { return "Charging" }
        if let f = RingFormat.forecast(nights: battery.forecastNights) { return f + (battery.isEnoughForTonight ? "" : " · charge before bed") }
        return battery.isEnoughForTonight ? "Enough for tonight" : "Charge before bed"
    }

    private var accessibilityValue: String {
        guard let battery else { return "Unknown" }
        var parts: [String] = []
        if let percent = battery.percent { parts.append("\(percent) percent") }
        if let bars = battery.bars { parts.append("\(bars) of 4 bars") }
        if battery.isCharging { parts.append("charging") }
        if let forecast { parts.append(forecast) }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    HStack(spacing: 24) {
        BatteryGauge(battery: Battery(percent: 64, forecastNights: 3.1))
        BatteryGauge(battery: Battery(percent: 12, isLow: true, forecastNights: 0.3))
        BatteryGauge(battery: Battery(percent: 71, isCharging: true), size: .compact)
        BatteryGauge(battery: Battery(percent: nil, bars: 3), size: .compact)
    }
    .padding()
    .background(RingTheme.Background.base)
}
