//
//  WellnessTag.swift
//  RingExperience
//
//  "Information only · not medical advice." Present on every score and vital detail. A wellness
//  ring that names no disease still has to say, plainly, what its numbers are for.
//

import SwiftUI

public struct WellnessTag: View {
    public init() {}

    public var body: some View {
        HStack(spacing: RingTheme.Metrics.spacing4) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .regular))
            Text("Information only · not medical advice")
                .font(RingTypography.caption)
        }
        .foregroundStyle(RingTheme.Content.tertiary)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WellnessTag().padding().background(RingTheme.Background.base)
}
