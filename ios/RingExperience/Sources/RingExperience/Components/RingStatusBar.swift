//
//  RingStatusBar.swift
//  RingExperience
//
//  The 44 pt accessory above the tab bar: the ring's ambient presence on every tab.
//  Left: ring glyph with a state dot. Middle: name · battery. Right: sync state. Tap → Ring
//  sheet, long-press → Sync now. It replaces the audit's three missing things at once — battery,
//  "last synced", and a way to tell "no data" from "not fetched" (A3, A4).
//

import SwiftUI

public struct RingStatusBar: View {
    private let connection: RingConnection
    private let battery: Battery?
    private let ringName: String?
    private let now: Date
    private let onTap: () -> Void
    private let onSyncNow: () -> Void

    public init(connection: RingConnection, battery: Battery?, ringName: String?, now: Date = Date(), onTap: @escaping () -> Void, onSyncNow: @escaping () -> Void) {
        self.connection = connection
        self.battery = battery
        self.ringName = ringName
        self.now = now
        self.onTap = onTap
        self.onSyncNow = onSyncNow
    }

    private var dotColor: Color {
        switch connection {
        case .connected, .syncing: return RingTheme.Status.optimal
        case .connecting: return RingTheme.Status.good
        case .notConnected, .unpaired: return RingTheme.Status.abstained
        case .bluetoothOff: return RingTheme.Status.fair
        }
    }

    private var syncText: String {
        switch connection {
        case .unpaired: return "Not paired"
        case .connecting: return "Connecting…"
        case .connected:
            if let battery, battery.isCharging { return "Charging \(battery.percent.map { "\($0) %" } ?? "")".trimmingCharacters(in: .whitespaces) }
            return "Connected"
        case let .notConnected(lastSync): return lastSync.map { "Not connected · synced \(RingFormat.relative($0, now: now))" } ?? "Not connected"
        case .bluetoothOff: return "Bluetooth is off"
        case .syncing: return "Syncing…"
        }
    }

    private var batteryText: String? {
        guard let battery else { return nil }
        if let percent = battery.percent { return "\(percent) %" }
        if let bars = battery.bars { return "\(bars)/4" }
        return nil
    }

    private var batterySymbol: String {
        guard let battery else { return "battery.0percent" }
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.level {
        case .ok: return "battery.100percent"
        case .low: return "battery.25percent"
        case .critical, .charging: return "battery.0percent"
        }
    }

    private var batteryColor: Color {
        guard let battery else { return RingTheme.Content.tertiary }
        switch battery.level {
        case .ok: return RingTheme.Content.secondary
        case .low: return RingTheme.Battery.low
        case .critical: return RingTheme.Battery.critical
        case .charging: return RingTheme.Battery.charging
        }
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: RingTheme.Metrics.spacing12) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "circle.circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(RingTheme.Content.secondary)
                        Circle().fill(dotColor).frame(width: 8, height: 8)
                            .overlay(Circle().stroke(RingTheme.Background.elevated, lineWidth: 1.5))
                    }
                    .frame(width: 24, height: 24)

                    HStack(spacing: RingTheme.Metrics.spacing8) {
                        Text(ringName ?? "Ring")
                            .font(RingTypography.subheadline).fontWeight(.semibold)
                            .foregroundStyle(RingTheme.Content.primary)
                        if let batteryText {
                            HStack(spacing: 3) {
                                Image(systemName: batterySymbol).font(.system(size: 12))
                                Text(batteryText).font(RingTypography.footnoteNumeric)
                            }
                            .foregroundStyle(batteryColor)
                        }
                    }
                    .lineLimit(1)

                    Spacer(minLength: RingTheme.Metrics.spacing8)

                    Text(syncText)
                        .font(RingTypography.footnote)
                        .foregroundStyle(connection == .bluetoothOff ? RingTheme.Status.fair : RingTheme.Content.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, RingTheme.Metrics.spacing16)
                .frame(height: RingTheme.Metrics.statusBarHeight)

                // A hairline of progress while syncing — no spinner anywhere in the app.
                if case let .syncing(progress) = connection {
                    GeometryReader { geo in
                        Rectangle().fill(RingTheme.Status.good)
                            .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                            .ringMotion(RingMotion.valueChange, value: progress)
                    }
                    .frame(height: 2)
                } else {
                    Rectangle().fill(RingTheme.Separator.hairline).frame(height: RingTheme.Metrics.hairline)
                }
            }
            .background(RingTheme.Background.elevated)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onSyncNow() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ring status")
        .accessibilityValue("\(ringName ?? "Ring"), \(batteryText.map { "battery \($0), " } ?? "")\(syncText)")
        .accessibilityHint("Opens ring details. Long press to sync now.")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("States") {
    VStack(spacing: 8) {
        RingStatusBar(connection: .connected, battery: Battery(percent: 64), ringName: "LOOP-E5FF", onTap: {}, onSyncNow: {})
        RingStatusBar(connection: .syncing(progress: 0.4), battery: Battery(percent: 64), ringName: "LOOP-E5FF", onTap: {}, onSyncNow: {})
        RingStatusBar(connection: .notConnected(lastSync: Date().addingTimeInterval(-900)), battery: Battery(percent: 22), ringName: "LOOP-E5FF", onTap: {}, onSyncNow: {})
        RingStatusBar(connection: .connected, battery: Battery(percent: 71, isCharging: true), ringName: "LOOP-E5FF", onTap: {}, onSyncNow: {})
        RingStatusBar(connection: .bluetoothOff, battery: Battery(percent: 58), ringName: "LOOP-E5FF", onTap: {}, onSyncNow: {})
        RingStatusBar(connection: .unpaired, battery: nil, ringName: nil, onTap: {}, onSyncNow: {})
    }
    .background(RingTheme.Background.base)
}
