//
//  MeasureGrid.swift
//  RingExperience
//
//  "Measure now": two-column tiles for the spot tests the ring can run. Hidden when the ring
//  lacks the sensor; disabled WITH A REASON when the ring is not connected, on the charger, or
//  below 15 % — a greyed button with no explanation is the audit's A9 all over again.
//

import SwiftUI

/// Whether a spot test can start right now, and if not, why.
public enum MeasureAvailability: Equatable {
    case available
    case notConnected
    case onCharger
    case lowBattery(percent: Int?)
    case bluetoothOff

    public init(connection: RingConnection, battery: Battery?) {
        switch connection {
        case .unpaired, .notConnected, .connecting: self = .notConnected; return
        case .bluetoothOff: self = .bluetoothOff; return
        case .connected, .syncing: break
        }
        if let battery {
            if battery.isCharging { self = .onCharger; return }
            if battery.level == .critical { self = .lowBattery(percent: battery.percent); return }
        }
        self = .available
    }

    public var reason: String? {
        switch self {
        case .available: return nil
        case .notConnected: return "Ring not connected"
        case .onCharger: return "Take the ring off the charger"
        case let .lowBattery(percent): return "Battery too low\(percent.map { " (\($0) %)" } ?? "")"
        case .bluetoothOff: return "Bluetooth is off"
        }
    }
}

public struct MeasureGrid: View {
    private let kinds: [SpotKind]
    private let capabilities: RingCapabilities
    private let availability: MeasureAvailability
    private let lastResults: [SpotKind: SpotMeasurement]
    private let onSelect: (SpotKind) -> Void

    public init(kinds: [SpotKind], capabilities: RingCapabilities, availability: MeasureAvailability, lastResults: [SpotKind: SpotMeasurement], onSelect: @escaping (SpotKind) -> Void) {
        self.kinds = kinds.filter { capabilities.supports($0) }
        self.capabilities = capabilities
        self.availability = availability
        self.lastResults = lastResults
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
            if let reason = availability.reason {
                Label(reason, systemImage: "info.circle")
                    .font(RingTypography.footnote).foregroundStyle(RingTheme.Content.secondary)
            }
            if kinds.isEmpty {
                Text("This ring has no spot tests.").font(RingTypography.footnote).foregroundStyle(RingTheme.Content.tertiary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: RingTheme.Metrics.spacing12), GridItem(.flexible(), spacing: RingTheme.Metrics.spacing12)], spacing: RingTheme.Metrics.spacing12) {
                ForEach(kinds) { kind in
                    Button { onSelect(kind) } label: { tile(kind) }
                        .buttonStyle(.plain)
                        .disabled(availability != .available)
                        .opacity(availability == .available ? 1 : 0.55)
                        .accessibilityLabel(accessibilityLabel(kind))
                        .accessibilityHint(availability.reason ?? "Starts a \(Int(kind.durationSeconds))-second measurement")
                }
            }
        }
    }

    private func tile(_ kind: SpotKind) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
            Image(systemName: kind.symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(kind == .heartRate ? RingTheme.Brand.ink : RingTheme.Content.secondary)
            Text(kind.title).font(RingTypography.subheadline).fontWeight(.semibold).foregroundStyle(RingTheme.Content.primary)
            if let last = lastResults[kind] {
                Text("\(RingFormat.spot(kind, last.value)) \(kind.unit) · \(RingFormat.relative(last.at))".trimmingCharacters(in: .whitespaces))
                    .font(RingTypography.caption).monospacedDigit().foregroundStyle(RingTheme.Content.tertiary).lineLimit(1)
            } else {
                Text("\(Int(kind.durationSeconds)) s").font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .ringCard(padding: RingTheme.Metrics.spacing12)
    }

    private func accessibilityLabel(_ kind: SpotKind) -> String {
        var text = "Measure \(kind.title.lowercased())"
        if let last = lastResults[kind] { text += ", last \(RingFormat.spot(kind, last.value)) \(kind.unit) \(RingFormat.relative(last.at))" }
        return text
    }
}

#Preview {
    VStack(spacing: 24) {
        MeasureGrid(kinds: [.heartRate, .bloodOxygen, .hrv, .stress, .skinTemperature], capabilities: .all, availability: .available, lastResults: [.heartRate: SpotMeasurement(kind: .heartRate, value: 72, at: Date().addingTimeInterval(-3600), state: .typical)], onSelect: { _ in })
        MeasureGrid(kinds: [.heartRate, .bloodOxygen], capabilities: .all, availability: .lowBattery(percent: 12), lastResults: [:], onSelect: { _ in })
    }
    .padding().background(RingTheme.Background.base)
}
