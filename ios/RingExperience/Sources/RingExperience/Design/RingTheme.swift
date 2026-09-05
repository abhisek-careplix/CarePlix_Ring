//
//  RingTheme.swift
//  RingExperience
//
//  Colour and layout tokens for the CarePlix ring app.
//
//  This file is THE ONLY place in the package that may contain a hex colour. Every token is
//  adaptive: an independently authored light value and dark value (never derived from each other
//  by inversion), plus an optional Increase Contrast variant. The values are the resolved values
//  from `docs/ux/06-design-system.md`, which in turn extends the band app's design system so the
//  two products read as one family.
//
//  COLOUR IS NEVER THE ONLY CHANNEL. `RingMetricState` ships a label and an SF Symbol alongside
//  its colour, and every component renders all three (WCAG 1.4.1).
//

import SwiftUI
import UIKit

// MARK: - Hex helpers

extension UIColor {
    convenience init(rgbHex hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

extension Color {
    /// A colour that resolves independently per interface style and per contrast setting.
    ///
    /// Module-internal on purpose: the band app defines an identically shaped helper, and an app
    /// that links both packages must not see two public `Color.adaptive` overloads.
    static func adaptive(
        light: UInt32,
        dark: UInt32,
        lightHighContrast: UInt32? = nil,
        darkHighContrast: UInt32? = nil
    ) -> Color {
        let resolved = UIColor { traits in
            let wantsHighContrast = traits.accessibilityContrast == .high
            switch (traits.userInterfaceStyle, wantsHighContrast) {
            case (.dark, true): return UIColor(rgbHex: darkHighContrast ?? dark)
            case (.dark, false): return UIColor(rgbHex: dark)
            case (_, true): return UIColor(rgbHex: lightHighContrast ?? light)
            case (_, false): return UIColor(rgbHex: light)
            }
        }
        return Color(uiColor: resolved)
    }

    /// Non-adaptive sRGB colour, for surfaces whose background is itself fixed.
    static func fixed(_ hex: UInt32) -> Color {
        Color(uiColor: UIColor(rgbHex: hex))
    }
}

// MARK: - RingTheme

/// Namespace for every colour and layout constant in the ring app.
public enum RingTheme {

    // MARK: Backgrounds

    public enum Background {
        /// The canvas behind everything.
        public static let base = Color.adaptive(light: 0xF5F7FA, dark: 0x08090C)
        /// Sheets and bars, including the ring status accessory.
        public static let elevated = Color.adaptive(light: 0xFFFFFF, dark: 0x101319)
        /// Cards.
        public static let card = Color.adaptive(light: 0xFFFFFF, dark: 0x171B22)
        /// Chart wells, ring tracks, the typical-range band.
        public static let recessed = Color.adaptive(light: 0xEDF1F6, dark: 0x0D1015)
    }

    // MARK: Content

    public enum Content {
        /// Numerals, titles — what the user reads first.
        public static let primary = Color.adaptive(light: 0x101319, dark: 0xF2F4F8)
        /// Supporting copy, axis labels, units.
        public static let secondary = Color.adaptive(
            light: 0x535C6B, dark: 0xA7B0BF,
            lightHighContrast: 0x333A46, darkHighContrast: 0xD5DBE5
        )
        /// Provenance lines and timestamps. Still >= 4.5:1 on every surface.
        public static let tertiary = Color.adaptive(
            light: 0x5F6875, dark: 0x868F9C,
            lightHighContrast: 0x444C59, darkHighContrast: 0xAEB7C4
        )
        /// Text on a filled brand gradient.
        public static let onBrand = Color.fixed(0xFFFFFF)
    }

    // MARK: Separators

    public enum Separator {
        /// Decorative hairline. The boundary it suggests is always also carried by a tone step.
        public static let hairline = Color.adaptive(light: 0xE1E6ED, dark: 0x282E38)
        /// A divider or control border that carries meaning on its own.
        public static let strong = Color.adaptive(
            light: 0x8F95A3, dark: 0x616977,
            lightHighContrast: 0x6B7280, darkHighContrast: 0x8A93A2
        )
    }

    // MARK: Brand — reserved for heart moments

    public enum Brand {
        public static let crimson = Color.adaptive(light: 0xC41239, dark: 0xE01B47)
        public static let coral = Color.adaptive(light: 0xE85A3C, dark: 0xFF6B57)
        /// Brand-coloured text.
        public static let ink = Color.adaptive(light: 0xA8102F, dark: 0xFF8A6B)

        /// The crimson → coral gradient. Spend it only on the pairing heartbeat, the live
        /// heart-rate ring and the heart-rate spot test; everywhere else it devalues the peak.
        public static func gradient(start: UnitPoint = .topLeading, end: UnitPoint = .bottomTrailing) -> LinearGradient {
            LinearGradient(colors: [crimson, coral], startPoint: start, endPoint: end)
        }

        public static func ringGradient(startAngle: Angle = .degrees(0), endAngle: Angle = .degrees(360)) -> AngularGradient {
            AngularGradient(colors: [crimson, coral], center: .center, startAngle: startAngle, endAngle: endAngle)
        }
    }

    // MARK: Status

    public enum Status {
        public static let optimal = Color.adaptive(light: 0x037F5A, dark: 0x06E19F)
        /// Also the colour of **Typical**.
        public static let good = Color.adaptive(light: 0x166D99, dark: 0x64BDE9)
        /// **Outside typical** — attention, never alarm.
        public static let fair = Color.adaptive(light: 0x7F5205, dark: 0xDF9109)
        /// Low.
        public static let poor = Color.adaptive(light: 0x932504, dark: 0xF95725)
        /// Learning / not measured / abstained.
        public static let abstained = Color.adaptive(light: 0x5A606B, dark: 0x969BA7)
    }

    // MARK: Sleep stages

    /// Luminance-monotone (deep darkest → awake lightest) so the hypnogram survives greyscale.
    /// Dark values are the spec values; light values are darkened so each stage clears 3:1 as a
    /// graphical object on a white card.
    public enum Sleep {
        public static let deep = Color.adaptive(light: 0x2F4BB8, dark: 0x3A5BD9)
        public static let light = Color.adaptive(light: 0x4F73C9, dark: 0x7C9BEA)
        public static let rem = Color.adaptive(light: 0x8A5BD6, dark: 0xB48CF2)
        public static let awake = Color.adaptive(light: 0xC4741F, dark: 0xF0A35E)
        /// A minute the ring did not record. Deliberately the recessed tone, not a stage colour.
        public static let gap = Background.recessed
    }

    // MARK: Battery

    public enum Battery {
        public static let ok = Status.optimal
        /// Below 30 %.
        public static let low = Status.fair
        /// Below 15 %.
        public static let critical = Status.poor
        public static let charging = Status.good
    }

    // MARK: Charts

    public enum Chart {
        /// The 10th–90th percentile "your usual" band behind a continuous line.
        public static let typicalBand = Background.recessed
        public static let valueLine = Content.primary
        public static let outlier = Status.fair
        public static let gridline = Separator.hairline
        public static let axisLabel = Content.tertiary
        public static let noData = Color.adaptive(light: 0xE7EBF1, dark: 0x1D222B)
    }

    // MARK: Layout metrics

    public enum Metrics {
        public static let minTouchTarget: CGFloat = 48

        public static let spacing2: CGFloat = 2
        public static let spacing4: CGFloat = 4
        public static let spacing8: CGFloat = 8
        public static let spacing12: CGFloat = 12
        public static let spacing16: CGFloat = 16
        public static let spacing24: CGFloat = 24
        public static let spacing32: CGFloat = 32
        public static let spacing48: CGFloat = 48

        public static let cornerSmall: CGFloat = 10
        public static let cornerCard: CGFloat = 20
        public static let cornerSheet: CGFloat = 28

        public static let hairline: CGFloat = 0.5

        /// Hero ring stroke.
        public static let ringStroke: CGFloat = 14
        /// Compact ring stroke.
        public static let ringStrokeCompact: CGFloat = 8

        /// The ring status accessory's height.
        public static let statusBarHeight: CGFloat = 44
    }
}

// MARK: - RingMetricState

/// A score's grade, with colour, label and symbol travelling together.
///
/// Labels are the ones shared with the band app: Optimal · Good · Fair · Low · Not enough signal.
/// (Vitals against a personal range use `RangeState`, whose chips read Typical · Outside typical
/// · Learning · Not measured — different vocabulary because they answer a different question.)
public enum RingMetricState: String, CaseIterable, Hashable, Sendable {
    case optimal
    case good
    case fair
    case poor
    case abstained

    public var color: Color {
        switch self {
        case .optimal: return RingTheme.Status.optimal
        case .good: return RingTheme.Status.good
        case .fair: return RingTheme.Status.fair
        case .poor: return RingTheme.Status.poor
        case .abstained: return RingTheme.Status.abstained
        }
    }

    public var symbol: String {
        switch self {
        case .optimal: return "checkmark.circle.fill"
        case .good: return "circle.fill"
        case .fair: return "minus.circle.fill"
        case .poor: return "exclamationmark.circle.fill"
        case .abstained: return "questionmark.circle"
        }
    }

    public var label: String {
        switch self {
        case .optimal: return "Optimal"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Low"
        case .abstained: return "Not enough signal"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .optimal: return "Optimal"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Low"
        case .abstained: return "Not enough signal to score"
        }
    }

    public var isAbstention: Bool { self == .abstained }

    /// The grade for a 0–100 score.
    public static func grade(score: Int) -> RingMetricState {
        switch score {
        case 85...: return .optimal
        case 70..<85: return .good
        case 50..<70: return .fair
        default: return .poor
        }
    }
}

// MARK: - Card surface

public extension View {
    /// The house card: card tone, 20 pt continuous corners, hairline edge.
    func ringCard(padding: CGFloat = RingTheme.Metrics.spacing16) -> some View {
        self
            .padding(padding)
            .background(RingTheme.Background.card, in: RoundedRectangle(cornerRadius: RingTheme.Metrics.cornerCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RingTheme.Metrics.cornerCard, style: .continuous)
                    .strokeBorder(RingTheme.Separator.hairline, lineWidth: RingTheme.Metrics.hairline)
            )
    }
}
