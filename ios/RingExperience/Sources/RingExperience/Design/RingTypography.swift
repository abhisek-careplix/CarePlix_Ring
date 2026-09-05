//
//  RingTypography.swift
//  RingExperience
//
//  Type system for the ring app. SF Pro throughout, Dynamic Type throughout.
//
//  Prose maps 1:1 onto the system text styles, so it scales for free. Measured values use fixed
//  optical sizes (hero 64 / large 44 / medium 30 / small 20) that scale through `@ScaledMetric`,
//  and ALWAYS use monospaced digits: a live heart rate stepping 68 → 71 → 100 must not reflow its
//  container. Nothing here is size-locked; clamping is a deliberate, local decision.
//

import SwiftUI

// MARK: - Prose scale

public enum RingTypography {
    public static let largeTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    public static let title = Font.system(.title, design: .default, weight: .semibold)
    public static let title2 = Font.system(.title2, design: .default, weight: .semibold)
    public static let title3 = Font.system(.title3, design: .default, weight: .semibold)
    public static let headline = Font.system(.headline, design: .default, weight: .semibold)
    public static let body = Font.system(.body, design: .default, weight: .regular)
    public static let bodyEmphasised = Font.system(.body, design: .default, weight: .semibold)
    public static let subheadline = Font.system(.subheadline, design: .default, weight: .regular)
    public static let footnote = Font.system(.footnote, design: .default, weight: .regular)
    public static let caption = Font.system(.caption, design: .default, weight: .regular)
    public static let caption2 = Font.system(.caption2, design: .default, weight: .regular)

    /// Provenance: "measured last night · vs your 14-night usual". Footnote, tertiary.
    public static let provenance = Font.system(.footnote, design: .default, weight: .regular)
    /// Eyebrow: caption semibold, uppercase, +1 tracking (applied by `RingEyebrow`).
    public static let eyebrow = Font.system(.caption, design: .default, weight: .semibold)
    /// Body-sized numbers inside prose, with tabular figures.
    public static let bodyNumeric = Font.system(.body, design: .default, weight: .regular).monospacedDigit()
    public static let footnoteNumeric = Font.system(.footnote, design: .default, weight: .regular).monospacedDigit()
}

// MARK: - Vital sizes

/// Optical sizes for measured values. If a screen has two heroes it has no hero.
public enum RingVitalSize: CaseIterable, Sendable {
    case hero
    case large
    case medium
    case small

    public var pointSize: CGFloat {
        switch self {
        case .hero: return 64
        case .large: return 44
        case .medium: return 30
        case .small: return 20
        }
    }

    public var textStyle: Font.TextStyle {
        switch self {
        case .hero: return .largeTitle
        case .large: return .title
        case .medium: return .title2
        case .small: return .title3
        }
    }

    /// Larger sizes take less weight: at 64 pt semibold already reads as heavy.
    public var weight: Font.Weight {
        switch self {
        case .hero: return .medium
        case .large, .medium, .small: return .semibold
        }
    }

    public var unitPointSize: CGFloat {
        switch self {
        case .hero: return 22
        case .large: return 17
        case .medium: return 14
        case .small: return 12
        }
    }
}

// MARK: - Vital number modifier

/// Monospaced-digit SF Pro at a Dynamic Type–scaled optical size.
public struct RingVitalNumberModifier: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let weight: Font.Weight
    private let maxPointSize: CGFloat?

    public init(size: RingVitalSize, weight: Font.Weight? = nil, maxPointSize: CGFloat? = nil) {
        self._scaledSize = ScaledMetric(wrappedValue: size.pointSize, relativeTo: size.textStyle)
        self.weight = weight ?? size.weight
        self.maxPointSize = maxPointSize
    }

    private var resolvedSize: CGFloat {
        guard let maxPointSize else { return scaledSize }
        return min(scaledSize, maxPointSize)
    }

    public func body(content: Content) -> some View {
        content
            .font(.system(size: resolvedSize, weight: weight, design: .default).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

public extension View {
    /// The house style for every measured value.
    func ringVitalNumber(_ size: RingVitalSize = .large, weight: Font.Weight? = nil, maxPointSize: CGFloat? = nil) -> some View {
        modifier(RingVitalNumberModifier(size: size, weight: weight, maxPointSize: maxPointSize))
    }
}

// MARK: - Unit suffix

/// The unit that trails a number: smaller, lighter, and a tone step down, so the eye stays on the value.
public struct RingUnitSuffix: View {
    @ScaledMetric private var scaledSize: CGFloat
    private let text: String

    public init(_ text: String, size: RingVitalSize) {
        self.text = text
        self._scaledSize = ScaledMetric(wrappedValue: size.unitPointSize, relativeTo: size.textStyle)
    }

    public var body: some View {
        Text(text)
            .font(.system(size: scaledSize, weight: .regular, design: .default))
            .foregroundStyle(RingTheme.Content.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - Vital value

/// A formatted number with its unit — or an honest placeholder.
///
/// `value` is optional on purpose. When the engine abstains, callers pass `nil` and this renders
/// an en dash in the abstained tone. There is no code path here that invents a number.
public struct RingVitalValue: View {
    private let value: String?
    private let unit: String?
    private let size: RingVitalSize
    private let abstentionNote: String

    public init(value: String?, unit: String? = nil, size: RingVitalSize = .large, abstentionNote: String = "Not measured") {
        self.value = value
        self.unit = unit
        self.size = size
        self.abstentionNote = abstentionNote
    }

    private static let placeholder = "\u{2013}\u{2013}"

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: RingTheme.Metrics.spacing4) {
            Text(value ?? Self.placeholder)
                .ringVitalNumber(size)
                .foregroundStyle(value == nil ? RingTheme.Status.abstained : RingTheme.Content.primary)
            if let unit, value != nil {
                RingUnitSuffix(unit, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let value else { return abstentionNote }
        guard let unit else { return value }
        return "\(value) \(unit)"
    }
}

// MARK: - Eyebrow & provenance

/// Uppercase caption with tracking, used to label a card section.
public struct RingEyebrow: View {
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .font(RingTypography.eyebrow)
            .tracking(0.6)
            .foregroundStyle(RingTheme.Content.tertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Where a number came from and when. Always present under a vital detail.
public struct RingProvenance: View {
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(RingTypography.provenance)
            .foregroundStyle(RingTheme.Content.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
