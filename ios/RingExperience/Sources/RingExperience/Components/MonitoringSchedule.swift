//
//  MonitoringSchedule.swift
//  RingExperience
//
//  "What your ring measures overnight": one toggle per passive monitor, its interval, its window
//  and a plain-language battery cost — so the trade-off between a richer night and a ring that
//  lasts the night is the user's to make, with the facts in front of them.
//

import SwiftUI

public struct MonitoringSchedule: View {
    private let settings: [MonitoringSetting]
    private let onChange: (MonitoringKind, Bool, Int) -> Void

    public init(settings: [MonitoringSetting], onChange: @escaping (MonitoringKind, Bool, Int) -> Void) {
        self.settings = settings
        self.onChange = onChange
    }

    public var body: some View {
        VStack(spacing: 0) {
            if settings.isEmpty {
                Text("Monitoring settings appear once the ring is connected.").font(RingTypography.footnote).foregroundStyle(RingTheme.Content.tertiary).padding(.vertical, RingTheme.Metrics.spacing8)
            }
            ForEach(Array(settings.enumerated()), id: \.element.id) { index, setting in
                row(setting)
                if index < settings.count - 1 { Rectangle().fill(RingTheme.Separator.hairline).frame(height: RingTheme.Metrics.hairline) }
            }
        }
    }

    private func intervals(for setting: MonitoringSetting) -> [Int] {
        [5, 10, 15, 30, 60].filter { $0 >= setting.minIntervalMin }
    }

    private func row(_ setting: MonitoringSetting) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
            Toggle(isOn: Binding(get: { setting.isOn }, set: { on in RingHaptics.selection(); onChange(setting.kind, on, setting.intervalMin) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(setting.kind.title).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
                    Text(hint(setting)).font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary)
                }
            }
            .tint(RingTheme.Status.optimal)
            if setting.isOn {
                Picker("Every", selection: Binding(get: { setting.intervalMin }, set: { onChange(setting.kind, true, $0) })) {
                    ForEach(intervals(for: setting), id: \.self) { m in Text("\(m) min").tag(m) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("\(setting.kind.title) interval")
            }
        }
        .padding(.vertical, RingTheme.Metrics.spacing12)
    }

    private func hint(_ setting: MonitoringSetting) -> String {
        var parts = [setting.kind.batteryCostHint]
        if let window = setting.window { parts.append("\(RingFormat.clock(window.lowerBound))–\(RingFormat.clock(window.upperBound))") }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    MonitoringSchedule(settings: MockRingDataSource().monitoring, onChange: { _, _, _ in }).ringCard().padding().background(RingTheme.Background.base)
}
