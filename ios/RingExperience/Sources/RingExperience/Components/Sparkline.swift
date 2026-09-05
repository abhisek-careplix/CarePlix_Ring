//
//  Sparkline.swift
//  RingExperience
//
//  A 7-point trend line for a tile, with the typical band drawn behind it in the recessed tone.
//  Pure `Path`, no axes, no chart junk: it answers "which way is this going" and nothing else.
//  The tile's VoiceOver label carries the numbers, so the sparkline itself is decorative.
//

import SwiftUI

public struct Sparkline: View {
    private let values: [Double]
    private let band: ClosedRange<Double>?
    private let lineColor: Color

    public init(values: [Double], band: ClosedRange<Double>? = nil, lineColor: Color = RingTheme.Content.secondary) {
        self.values = values.filter { $0.isFinite }
        self.band = band
        self.lineColor = lineColor
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let domain = domain()
            ZStack {
                if let band, let bandRect = rect(for: band, in: size, domain: domain) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(RingTheme.Chart.typicalBand)
                        .frame(width: size.width, height: bandRect.height)
                        .position(x: size.width / 2, y: bandRect.midY)
                }
                if values.count >= 2 {
                    path(in: size, domain: domain)
                        .stroke(lineColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    if let last = values.last, let point = point(index: values.count - 1, value: last, in: size, domain: domain) {
                        Circle()
                            .fill(lineColor)
                            .frame(width: 5, height: 5)
                            .position(point)
                    }
                } else if values.count == 1, let only = values.first, let point = point(index: 0, value: only, in: size, domain: domain) {
                    Circle().fill(lineColor).frame(width: 5, height: 5).position(point)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func domain() -> ClosedRange<Double> {
        var lo = values.min() ?? 0, hi = values.max() ?? 1
        if let band { lo = min(lo, band.lowerBound); hi = max(hi, band.upperBound) }
        if hi - lo < 0.001 { hi = lo + 1 }
        let pad = (hi - lo) * 0.15
        return (lo - pad)...(hi + pad)
    }

    private func y(_ value: Double, in size: CGSize, domain: ClosedRange<Double>) -> CGFloat {
        let fraction = (value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
        return size.height - CGFloat(fraction) * size.height
    }

    private func point(index: Int, value: Double, in size: CGSize, domain: ClosedRange<Double>) -> CGPoint? {
        guard size.width > 0 else { return nil }
        let count = max(values.count - 1, 1)
        let x = values.count == 1 ? size.width / 2 : CGFloat(index) / CGFloat(count) * size.width
        return CGPoint(x: x, y: y(value, in: size, domain: domain))
    }

    private func rect(for band: ClosedRange<Double>, in size: CGSize, domain: ClosedRange<Double>) -> CGRect? {
        let top = y(band.upperBound, in: size, domain: domain), bottom = y(band.lowerBound, in: size, domain: domain)
        return CGRect(x: 0, y: top, width: size.width, height: max(bottom - top, 2))
    }

    private func path(in size: CGSize, domain: ClosedRange<Double>) -> Path {
        var path = Path()
        for (index, value) in values.enumerated() {
            guard let p = point(index: index, value: value, in: size, domain: domain) else { continue }
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

#Preview {
    Sparkline(values: [56, 58, 55, 57, 60, 54, 57], band: 54...59)
        .frame(width: 120, height: 32)
        .padding()
        .background(RingTheme.Background.card)
}
