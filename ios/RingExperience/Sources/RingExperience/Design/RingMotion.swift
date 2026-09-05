//
//  RingMotion.swift
//  RingExperience
//
//  Motion and haptics for the ring app.
//
//  Every animation is a `RingMotionCurve` that carries its own Reduce Motion variant, so a curve
//  cannot exist without an accessible fallback. Waiting states BREATHE (4 s cycle) rather than
//  spin: a spinner says "wait for me", a breath says "I'm alive, come back later". Under Reduce
//  Motion the breath stops entirely and fills become short cross-fades.
//

import SwiftUI
import UIKit

// MARK: - Curve

public struct RingMotionCurve {
    public let standard: Animation
    /// `nil` means "no animation at all" — right for anything purely ornamental.
    public let reduced: Animation?

    public init(standard: Animation, reduced: Animation?) {
        self.standard = standard
        self.reduced = reduced
    }

    public func resolved(reduceMotion: Bool) -> Animation? {
        reduceMotion ? reduced : standard
    }

    public func delayed(by seconds: Double) -> RingMotionCurve {
        RingMotionCurve(standard: standard.delay(seconds), reduced: reduced?.delay(seconds))
    }
}

// MARK: - Catalogue

public enum RingMotion {

    /// Decelerating fill for scores and gauges: most of the travel in the first third, then it
    /// settles, the way a volume fills. Slower than a UI transition on purpose — watching the
    /// value arrive is what makes it feel measured rather than fetched.
    public static let ringFill = RingMotionCurve(
        standard: .timingCurve(0.22, 0.61, 0.36, 1.0, duration: 0.9),
        reduced: .easeOut(duration: 0.2)
    )

    public static let ringFillHero = RingMotionCurve(
        standard: .timingCurve(0.22, 0.61, 0.36, 1.0, duration: 1.25),
        reduced: .easeOut(duration: 0.2)
    )

    /// Half of the 4 s breathing cycle (≈ 15 breaths a minute, a calm adult rate).
    public static let breathingHalfCycle: Double = 2.0
    public static let breathingCycle: Double = breathingHalfCycle * 2

    /// The waiting-state pulse. `reduced` is `nil`: under Reduce Motion it stops, not slows.
    public static let breathingPulse = RingMotionCurve(
        standard: .easeInOut(duration: breathingHalfCycle).repeatForever(autoreverses: true),
        reduced: nil
    )

    /// Card entrance. Staggered by 40 ms per card via `staggerDelay`.
    public static let cardAppear = RingMotionCurve(
        standard: .spring(response: 0.5, dampingFraction: 0.82, blendDuration: 0),
        reduced: .easeOut(duration: 0.2)
    )

    /// A value updating in place. Nearly critically damped: the number should land, not wobble.
    public static let valueChange = RingMotionCurve(
        standard: .spring(response: 0.28, dampingFraction: 0.9, blendDuration: 0),
        reduced: .easeOut(duration: 0.15)
    )

    /// Chip / state transitions.
    public static let stateChange = RingMotionCurve(
        standard: .easeInOut(duration: 0.28),
        reduced: .easeInOut(duration: 0.15)
    )

    /// Guided-breathing circle: linear in, linear out, because the user is pacing their breath on it.
    public static func breathPhase(duration: Double) -> RingMotionCurve {
        let safe = duration.isFinite && duration > 0 ? duration : 0.001
        return RingMotionCurve(standard: .easeInOut(duration: safe), reduced: .easeInOut(duration: safe))
    }

    /// Per-card delay for a cascading entrance. Zero under Reduce Motion.
    public static func staggerDelay(index: Int, step: Double = 0.04, maxIndex: Int = 8, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        return Double(min(max(index, 0), maxIndex)) * step
    }
}

// MARK: - View helpers

private struct RingMotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let curve: RingMotionCurve
    let value: V

    func body(content: Content) -> some View {
        content.animation(curve.resolved(reduceMotion: reduceMotion), value: value)
    }
}

private struct RingNumericTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .identity : .numericText())
    }
}

/// Scales and dims gently on a 4 s cycle. Static, at full opacity, under Reduce Motion.
public struct RingBreathingPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    let scaleRange: ClosedRange<Double>
    let opacityRange: ClosedRange<Double>

    public init(scaleRange: ClosedRange<Double> = 0.985...1.015, opacityRange: ClosedRange<Double> = 0.82...1.0) {
        self.scaleRange = scaleRange
        self.opacityRange = opacityRange
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1.0 : (isExpanded ? scaleRange.upperBound : scaleRange.lowerBound))
            .opacity(reduceMotion ? opacityRange.upperBound : (isExpanded ? opacityRange.upperBound : opacityRange.lowerBound))
            .animation(RingMotion.breathingPulse.resolved(reduceMotion: reduceMotion), value: isExpanded)
            .onAppear { if !reduceMotion { isExpanded = true } }
            .onDisappear { isExpanded = false }
    }
}

public extension View {
    /// Animates `value` changes with a curve that already knows about Reduce Motion.
    func ringMotion<V: Equatable>(_ curve: RingMotionCurve, value: V) -> some View {
        modifier(RingMotionModifier(curve: curve, value: value))
    }

    /// Numeric roll for changing values; identity under Reduce Motion.
    func ringNumericTransition() -> some View {
        modifier(RingNumericTransition())
    }

    /// The waiting-state pulse. Use instead of any spinner.
    func ringBreathingPulse(scale: ClosedRange<Double> = 0.985...1.015, opacity: ClosedRange<Double> = 0.82...1.0) -> some View {
        modifier(RingBreathingPulse(scaleRange: scale, opacityRange: opacity))
    }
}

/// Exposes the Reduce Motion flag to a view builder for choreography decisions (stagger, etc.).
public struct RingMotionReader<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let build: (Bool) -> Content
    public init(@ViewBuilder _ build: @escaping (Bool) -> Content) { self.build = build }
    public var body: some View { build(reduceMotion) }
}

// MARK: - Haptics

/// `heartbeat` on first pairing, `success` on a completed measurement, `selection` on chips.
@MainActor
public enum RingHaptics {
    public static var isEnabled = true

    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    public static func prepare() {
        heavy.prepare(); light.prepare(); notification.prepare(); selectionGenerator.prepare()
    }

    /// A real double thump: the ring's first heartbeat, felt in the hand. Peak-end rule.
    public static func heartbeat(beats: Int = 2, bpm: Double = 60) {
        guard isEnabled else { return }
        let safeBpm = bpm.isFinite ? min(max(bpm, 30), 220) : 60
        let interval = 60.0 / safeBpm
        for beat in 0..<max(beats, 1) {
            let start = Double(beat) * interval
            DispatchQueue.main.asyncAfter(deadline: .now() + start) { heavy.impactOccurred(intensity: 1.0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + start + 0.16) { light.impactOccurred(intensity: 0.6) }
        }
    }

    public static func success() { guard isEnabled else { return }; notification.notificationOccurred(.success) }
    public static func warning() { guard isEnabled else { return }; notification.notificationOccurred(.warning) }
    public static func selection() { guard isEnabled else { return }; selectionGenerator.selectionChanged() }
    /// A breath cue for the guided-breathing pacer.
    public static func breathCue() { guard isEnabled else { return }; light.impactOccurred(intensity: 0.5) }
}
