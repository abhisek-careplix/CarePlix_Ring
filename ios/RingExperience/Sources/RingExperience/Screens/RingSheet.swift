//
//  RingSheet.swift
//  RingExperience
//
//  The ring as a character: battery with forecast and history, connection and sync, what it
//  measures overnight, how it is worn, notifications, power mode, and the danger zone. Demo
//  builds say "Demo data" here so nobody mistakes a demo archive for a broken ring.
//

import SwiftUI
import Charts

public struct RingSheet<DS: RingDataSource>: View {
    @ObservedObject private var dataSource: DS
    private let navigator: RingNavigator
    @Environment(\.dismiss) private var dismiss
    @State private var showsProfile = false
    @State private var confirm: DangerAction?

    @AppStorage("ring.notify.nightReady") private var notifyNightReady = true
    @AppStorage("ring.notify.chargeBeforeBed") private var notifyCharge = true
    @AppStorage("ring.notify.charged") private var notifyCharged = false
    @AppStorage("ring.notify.notWorn") private var notifyNotWorn = true
    @AppStorage("ring.notify.vitals") private var notifyVitals = true

    private enum DangerAction: Identifiable { case powerOff, forget, reset; var id: Self { self } }

    public init(dataSource: DS, navigator: RingNavigator = .inert) {
        self.dataSource = dataSource
        self.navigator = navigator
    }

    private var connectionText: String {
        switch dataSource.connection {
        case .unpaired: return "Not paired"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .notConnected: return "Not connected"
        case .bluetoothOff: return "Bluetooth off"
        case .syncing: return "Syncing"
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: RingTheme.Metrics.spacing16) {
                    header
                    batteryCard
                    syncCard
                    section("What your ring measures overnight") {
                        MonitoringSchedule(settings: dataSource.monitoring) { kind, on, interval in Task { await dataSource.setMonitoring(kind, on: on, intervalMin: interval) } }
                    }
                    section("Wear") {
                        WearGuide(hand: dataSource.profile?.wearHand ?? .left, finger: dataSource.profile?.wearFinger ?? .index, compact: true)
                        Button("Edit profile") { showsProfile = true }.buttonStyle(RingSecondaryButtonStyle())
                    }
                    section("Notifications") { notifications }
                    section("Power mode") {
                        Toggle(isOn: Binding(get: { dataSource.isLowPowerMode }, set: { on in Task { await dataSource.setLowPowerMode(on) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Low power").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
                                Text("Fewer overnight samples, about a night more per charge").font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary)
                            }
                        }
                        .tint(RingTheme.Status.optimal)
                    }
                    dangerZone
                }
                .padding(.horizontal, RingTheme.Metrics.spacing16)
                .padding(.bottom, RingTheme.Metrics.spacing24)
            }
            .background(RingTheme.Background.base)
            .navigationTitle(dataSource.ringName ?? "Ring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showsProfile) { ProfileSheet(dataSource: dataSource) }
            .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
                Button(confirmButton, role: .destructive) { perform() }
                Button("Cancel", role: .cancel) { confirm = nil }
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: RingTheme.Metrics.spacing16) {
            RingIllustration(diameter: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(dataSource.ringName ?? "No ring").font(RingTypography.title3).foregroundStyle(RingTheme.Content.primary)
                HStack(spacing: 6) {
                    Circle().fill(dataSource.connection.isConnected ? RingTheme.Status.optimal : RingTheme.Status.abstained).frame(width: 8, height: 8)
                    Text(connectionText).font(RingTypography.footnote).foregroundStyle(RingTheme.Content.secondary)
                }
                if let firmware = dataSource.firmwareVersion { Text("Firmware \(firmware)").font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary) }
                if dataSource.isDemo { Label("Demo data", systemImage: "sparkles").font(RingTypography.caption).foregroundStyle(RingTheme.Brand.ink) }
            }
            Spacer()
        }
        .ringCard()
        .accessibilityElement(children: .combine)
    }

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing16) {
            RingEyebrow("Battery")
            HStack(spacing: RingTheme.Metrics.spacing24) {
                BatteryGauge(battery: dataSource.battery, size: .large)
                VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
                    if let battery = dataSource.battery {
                        if battery.isCharging { Label("Charging", systemImage: "bolt.fill").foregroundStyle(RingTheme.Battery.charging) }
                        else if !battery.isEnoughForTonight { Label("Charge for about 40 minutes before bed", systemImage: "moon.zzz").foregroundStyle(RingTheme.Battery.low) }
                        else { Label("Enough for tonight", systemImage: "checkmark.circle").foregroundStyle(RingTheme.Status.optimal) }
                    } else {
                        Text("Battery reads once the ring is connected.").foregroundStyle(RingTheme.Content.tertiary)
                    }
                }
                .font(RingTypography.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            }
            if dataSource.batteryHistory.count >= 2 {
                Chart {
                    ForEach(dataSource.batteryHistory) { s in
                        AreaMark(x: .value("Time", s.time), y: .value("Battery", s.value)).foregroundStyle(RingTheme.Battery.ok.opacity(0.18)).interpolationMethod(.monotone)
                        LineMark(x: .value("Time", s.time), y: .value("Battery", s.value)).foregroundStyle(RingTheme.Battery.ok).interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)).foregroundStyle(RingTheme.Chart.axisLabel) } }
                .chartYAxis { AxisMarks(position: .trailing, values: [0, 50, 100]) { _ in AxisGridLine().foregroundStyle(RingTheme.Chart.gridline); AxisValueLabel().foregroundStyle(RingTheme.Chart.axisLabel) } }
                .frame(height: 80)
                .accessibilityLabel("Battery over the last seven days")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RingEyebrow("Sync")
            Text(dataSource.lastSync.map { "Last synced \(RingFormat.relative($0))" } ?? "Not synced yet").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
            Text("Your ring keeps \(max(dataSource.capabilities.saveDays, 1)) days of data when away from your phone.").font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary)
            Button("Sync now") { Task { await dataSource.sync() } }.buttonStyle(RingPrimaryButtonStyle()).disabled(!dataSource.connection.isConnected && dataSource.connection != .notConnected(lastSync: dataSource.lastSync))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
    }

    private var notifications: some View {
        VStack(spacing: RingTheme.Metrics.spacing8) {
            toggle("Night ready", "Your night is ready · Sleep 82", $notifyNightReady)
            toggle("Charge before bed", "About 2.5 h before bedtime when below 30 %", $notifyCharge)
            toggle("Charged", "Ring charged · ready for tonight", $notifyCharged)
            toggle("Not worn", "An hour after bedtime if the ring is on the charger", $notifyNotWorn)
            toggle("Vitals outside typical", "Only when two or more are out of range", $notifyVitals)
        }
    }

    private func toggle(_ title: String, _ detail: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
                Text(detail).font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary)
            }
        }
        .tint(RingTheme.Status.optimal)
    }

    private var dangerZone: some View {
        section("Danger zone") {
            Button("Power off ring") { confirm = .powerOff }.buttonStyle(RingSecondaryButtonStyle())
            Button("Forget ring") { confirm = .forget }.buttonStyle(RingSecondaryButtonStyle())
            Button("Reset ring data") { confirm = .reset }.buttonStyle(RingSecondaryButtonStyle()).foregroundStyle(RingTheme.Status.poor)
            Button("Pair a different ring") { dismiss(); navigator.open(.pairing) }.font(RingTypography.footnote).foregroundStyle(RingTheme.Content.secondary)
        }
    }

    private var confirmTitle: String {
        switch confirm {
        case .powerOff: return "Power off the ring? Put it on the charger to turn it back on."
        case .forget: return "Forget this ring? Its data stays on your phone."
        case .reset: return "Erase everything stored on the ring? This cannot be undone."
        case nil: return ""
        }
    }

    private var confirmButton: String {
        switch confirm {
        case .powerOff: return "Power off"
        case .forget: return "Forget ring"
        case .reset: return "Erase"
        case nil: return ""
        }
    }

    private func perform() {
        let action = confirm
        confirm = nil
        Task {
            switch action {
            case .powerOff: await dataSource.powerOffRing()
            case .forget: await dataSource.forgetRing(); dismiss()
            case .reset: await dataSource.resetRingData()
            case nil: break
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RingEyebrow(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
    }
}

#Preview("Dark") { RingSheet(dataSource: MockRingDataSource()).preferredColorScheme(.dark) }
#Preview("Light · low battery") { RingSheet(dataSource: MockRingDataSource(scenario: .batteryDied)).preferredColorScheme(.light) }
