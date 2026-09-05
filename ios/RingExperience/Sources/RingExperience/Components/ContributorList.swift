//
//  ContributorList.swift
//  RingExperience
//
//  Rows of name · reading · state chip. A score without contributors is a verdict; with them it
//  is an explanation the user can act on.
//

import SwiftUI

public struct ContributorList: View {
    private let contributors: [Contributor]

    public init(contributors: [Contributor]) { self.contributors = contributors }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(contributors.enumerated()), id: \.element.id) { index, c in
                HStack(spacing: RingTheme.Metrics.spacing12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.primary)
                        Text(c.reading).font(RingTypography.footnoteNumeric).foregroundStyle(RingTheme.Content.secondary)
                    }
                    Spacer(minLength: RingTheme.Metrics.spacing8)
                    if let trend = c.trend {
                        Image(systemName: trend.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(c.state.metric.color).accessibilityHidden(true)
                    }
                    StateChip(state: c.state, compact: true)
                }
                .padding(.vertical, RingTheme.Metrics.spacing12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(c.name), \(c.reading), \(c.state.spoken)")
                if index < contributors.count - 1 {
                    Rectangle().fill(RingTheme.Separator.hairline).frame(height: RingTheme.Metrics.hairline)
                }
            }
        }
    }
}

#Preview {
    ContributorList(contributors: MockRingDataSource().nights.last!.contributors).ringCard().padding().background(RingTheme.Background.base)
}
