//
//  DayTimeline.swift
//  RingExperience
//
//  The day's actual story — sleep, syncs, spot tests, charging, drops — with clock labels.
//  It occupies the real estate the audit's empty search bar used to waste.
//

import SwiftUI

public struct DayTimeline: View {
    private let items: [DayTimelineItem]

    public init(items: [DayTimelineItem]) { self.items = items.sorted { $0.time < $1.time } }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text("Nothing yet today. Your ring's story appears here as the day goes on.")
                    .font(RingTypography.footnote).foregroundStyle(RingTheme.Content.tertiary)
                    .padding(.vertical, RingTheme.Metrics.spacing8)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: RingTheme.Metrics.spacing12) {
                    Text(RingFormat.clock(item.time))
                        .font(RingTypography.footnoteNumeric).foregroundStyle(RingTheme.Content.tertiary)
                        .frame(width: 56, alignment: .trailing)
                    VStack(spacing: 0) {
                        Image(systemName: item.kind.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color(item.kind))
                            .frame(width: 24, height: 24)
                            .background(RingTheme.Background.recessed, in: Circle())
                        if index < items.count - 1 {
                            Rectangle().fill(RingTheme.Separator.hairline).frame(width: 1).frame(maxHeight: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
                        if let detail = item.detail { Text(detail).font(RingTypography.caption).foregroundStyle(RingTheme.Content.secondary) }
                    }
                    .padding(.bottom, index < items.count - 1 ? RingTheme.Metrics.spacing16 : 0)
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(RingFormat.clock(item.time)), \(item.title)\(item.detail.map { ", \($0)" } ?? "")")
            }
        }
    }

    private func color(_ kind: DayTimelineItem.Kind) -> Color {
        switch kind {
        case .sleep: return RingTheme.Sleep.rem
        case .sync: return RingTheme.Status.good
        case .spotTest: return RingTheme.Brand.ink
        case .charging: return RingTheme.Battery.charging
        case .disconnected, .notWorn: return RingTheme.Status.fair
        case .chargeReminder: return RingTheme.Battery.low
        }
    }
}

#Preview {
    DayTimeline(items: MockRingDataSource().timeline).ringCard().padding().background(RingTheme.Background.base)
}
