//
//  SleepDebtCard.swift
//  RingExperience
//
//  Sleep need vs the rolling 7-night total, as one sentence and one bar. No streaks, no guilt:
//  "1 h 10 m short this week" is a fact the user can act on tonight.
//

import SwiftUI

public struct SleepDebtCard: View {
    private let debt: SleepDebt

    public init(debt: SleepDebt) { self.debt = debt }

    private var sentence: String {
        guard debt.nights > 0 else { return "Your sleep debt appears after the first week." }
        let delta = debt.deltaMin
        if delta >= -30 { return delta > 30 ? "\(RingFormat.duration(minutes: delta)) ahead of your need this week." : "On track with your sleep need this week." }
        return "\(RingFormat.duration(minutes: -delta)) short this week."
    }

    private var color: Color {
        switch debt.level {
        case .none: return RingTheme.Status.optimal
        case .building: return RingTheme.Status.fair
        case .high: return RingTheme.Status.poor
        }
    }

    private var fraction: Double {
        let need = Double(debt.needMin * max(debt.nights, 1))
        return need > 0 ? min(Double(debt.totalMin) / need, 1) : 0
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RingEyebrow("Sleep debt")
            Text(sentence).font(RingTypography.headline).foregroundStyle(RingTheme.Content.primary).fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(RingTheme.Background.recessed)
                    Capsule().fill(color).frame(width: max(geo.size.width * CGFloat(fraction), 4))
                        .ringMotion(RingMotion.ringFill, value: fraction)
                }
            }
            .frame(height: 8)
            HStack {
                Text("Slept \(RingFormat.duration(minutes: debt.totalMin))").font(RingTypography.caption).foregroundStyle(RingTheme.Content.secondary)
                Spacer()
                Text("Need \(RingFormat.duration(minutes: debt.needMin * max(debt.nights, 1))) over \(debt.nights) nights").font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep debt. \(sentence) Slept \(RingFormat.duration(minutes: debt.totalMin)) of \(RingFormat.duration(minutes: debt.needMin * max(debt.nights, 1))) needed over \(debt.nights) nights.")
    }
}

#Preview {
    VStack(spacing: 12) {
        SleepDebtCard(debt: SleepDebt(needMin: 450, totalMin: 3080, nights: 7))
        SleepDebtCard(debt: SleepDebt(needMin: 450, totalMin: 3200, nights: 7))
        SleepDebtCard(debt: SleepDebt(needMin: 450, totalMin: 2700, nights: 7))
    }
    .padding().background(RingTheme.Background.base)
}
