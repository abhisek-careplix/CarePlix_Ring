//
//  EmptyStates.swift
//  RingExperience
//
//  "Silence is a bug." Every empty state says WHY (not worn, not synced, battery flat, ring off,
//  still learning) and offers exactly one verb. Plus the shimmer skeleton shown while syncing,
//  so stale numbers never masquerade as fresh ones.
//

import SwiftUI

public enum EmptyStateKind: Equatable {
    case notWorn(from: Date?, to: Date?)
    case notSynced
    case batteryRanOut(at: Date)
    case unpaired
    case bluetoothOff
    case learning(nights: Int, needed: Int)
    case notMeasured(String)
    case nothingYet(String)

    var symbol: String {
        switch self {
        case .notWorn: return "hand.raised.slash"
        case .notSynced: return "arrow.triangle.2.circlepath"
        case .batteryRanOut: return "battery.0percent"
        case .unpaired: return "circle.circle"
        case .bluetoothOff: return "antenna.radiowaves.left.and.right.slash"
        case .learning: return "circle.dotted"
        case .notMeasured, .nothingYet: return "minus.circle"
        }
    }

    var title: String {
        switch self {
        case .notWorn: return "Ring not worn"
        case .notSynced: return "Last night is still on your ring"
        case .batteryRanOut: return "Your ring ran out"
        case .unpaired: return "Pair your ring"
        case .bluetoothOff: return "Bluetooth is off"
        case let .learning(n, needed): return "Learning your usual · night \(n) of \(needed)"
        case let .notMeasured(what): return "\(what) not measured"
        case let .nothingYet(what): return what
        }
    }

    var body: String {
        switch self {
        case .notWorn(let from?, let to?): return "Your ring wasn't on your finger between \(RingFormat.clock(from)) and \(RingFormat.clock(to))."
        case .notWorn: return "Your ring wasn't on your finger during the night."
        case .notSynced: return "Bring your phone near the ring to bring it over. The ring keeps several days of history."
        case let .batteryRanOut(at): return "Recording stopped at \(RingFormat.clock(at)). Charge it now and tonight is covered."
        case .unpaired: return "Take the ring off the charger and hold it near your phone."
        case .bluetoothOff: return "Your ring keeps recording. Turn Bluetooth on to sync."
        case .learning: return "Your typical ranges appear after seven nights. Until then, values show without a verdict."
        case .notMeasured: return "The ring did not record this last night."
        case .nothingYet: return ""
        }
    }

    var action: String? {
        switch self {
        case .notWorn: return "See how to wear it"
        case .notSynced: return "Sync now"
        case .batteryRanOut: return "See battery"
        case .unpaired: return "Pair ring"
        case .bluetoothOff: return "Open Settings"
        case .learning, .notMeasured, .nothingYet: return nil
        }
    }
}

/// A full-width card with a reason and one action.
public struct EmptyStateCard: View {
    private let kind: EmptyStateKind
    private let action: (() -> Void)?

    public init(_ kind: EmptyStateKind, action: (() -> Void)? = nil) {
        self.kind = kind
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(RingTheme.Status.abstained)
                .accessibilityHidden(true)
            Text(kind.title)
                .font(RingTypography.headline)
                .foregroundStyle(RingTheme.Content.primary)
            if !kind.body.isEmpty {
                Text(kind.body)
                    .font(RingTypography.subheadline)
                    .foregroundStyle(RingTheme.Content.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let title = kind.action, let action {
                Button(title, action: action)
                    .buttonStyle(RingPrimaryButtonStyle())
                    .padding(.top, RingTheme.Metrics.spacing4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard(padding: RingTheme.Metrics.spacing24)
        .accessibilityElement(children: .contain)
    }
}

/// The house primary button: 48 pt tall, filled.
public struct RingPrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RingTypography.bodyEmphasised)
            .foregroundStyle(RingTheme.Content.onBrand)
            .frame(maxWidth: .infinity, minHeight: RingTheme.Metrics.minTouchTarget)
            .background(RingTheme.Brand.crimson.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: RingTheme.Metrics.cornerSmall + 4, style: .continuous))
    }
}

/// Quiet secondary button.
public struct RingSecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RingTypography.bodyEmphasised)
            .foregroundStyle(RingTheme.Content.primary)
            .frame(maxWidth: .infinity, minHeight: RingTheme.Metrics.minTouchTarget)
            .background(RingTheme.Background.recessed.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: RingTheme.Metrics.cornerSmall + 4, style: .continuous))
    }
}

/// Shimmer placeholder for a card while a sync is in flight. Breathes; never spins.
public struct SkeletonCard: View {
    private let height: CGFloat
    public init(height: CGFloat = 120) { self.height = height }

    public var body: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            RoundedRectangle(cornerRadius: 6).fill(RingTheme.Background.recessed).frame(width: 120, height: 12)
            RoundedRectangle(cornerRadius: 6).fill(RingTheme.Background.recessed).frame(height: 28)
            RoundedRectangle(cornerRadius: 6).fill(RingTheme.Background.recessed).frame(width: 200, height: 12)
        }
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        .ringCard()
        .ringBreathingPulse(scale: 1.0...1.0, opacity: 0.55...1.0)
        .accessibilityLabel("Syncing")
    }
}

#Preview("Empty states") {
    ScrollView {
        VStack(spacing: 12) {
            EmptyStateCard(.notWorn(from: Date().addingTimeInterval(-8 * 3600), to: Date()), action: {})
            EmptyStateCard(.batteryRanOut(at: Date().addingTimeInterval(-5 * 3600)), action: {})
            EmptyStateCard(.notSynced, action: {})
            EmptyStateCard(.learning(nights: 3, needed: 7))
            SkeletonCard()
        }
        .padding()
    }
    .background(RingTheme.Background.base)
}
