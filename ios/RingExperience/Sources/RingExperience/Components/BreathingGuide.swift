//
//  BreathingGuide.swift
//  RingExperience
//
//  Guided box breathing (4 s in · 4 hold · 4 out · 4 hold) for 1, 3 or 5 minutes: an expanding
//  circle with a haptic at each phase change. App-side, no sensor needed. If the ring is worn,
//  heart rate before and after is shown as "settled from 78 to 66" — a small, honest effect
//  the user can feel, not a score.
//

import SwiftUI

public struct BreathingGuide: View {
    public enum Phase: String { case inhale = "Breathe in", holdIn = "Hold", exhale = "Breathe out", holdOut = "Hold " }

    private let currentHeartRate: () -> Double?
    private let initialMinutes: Int

    @State private var minutes: Int
    @State private var isRunning = false
    @State private var phase: Phase = .inhale
    @State private var remaining: Int = 0
    @State private var before: Double?
    @State private var after: Double?
    @State private var task: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let phaseSeconds = 4.0

    /// - Parameter currentHeartRate: latest heart rate from the ring if worn, else nil.
    public init(minutes: Int = 3, currentHeartRate: @escaping () -> Double? = { nil }) {
        self.initialMinutes = minutes
        self.currentHeartRate = currentHeartRate
        _minutes = State(initialValue: minutes)
    }

    private var expanded: Bool { phase == .inhale || phase == .holdIn }

    public var body: some View {
        VStack(spacing: RingTheme.Metrics.spacing24) {
            HStack(spacing: RingTheme.Metrics.spacing8) {
                ForEach([1, 3, 5], id: \.self) { m in
                    Button("\(m) min") { RingHaptics.selection(); minutes = m }
                        .font(RingTypography.subheadline).fontWeight(.semibold)
                        .foregroundStyle(minutes == m ? RingTheme.Content.onBrand : RingTheme.Content.primary)
                        .padding(.horizontal, RingTheme.Metrics.spacing16).frame(minHeight: 40)
                        .background(minutes == m ? RingTheme.Brand.crimson : RingTheme.Background.recessed, in: Capsule())
                        .disabled(isRunning)
                        .accessibilityAddTraits(minutes == m ? .isSelected : [])
                }
            }

            ZStack {
                Circle().fill(RingTheme.Status.good.opacity(0.12)).frame(width: 200, height: 200)
                Circle().fill(RingTheme.Status.good.opacity(0.35))
                    .frame(width: 200, height: 200)
                    .scaleEffect(isRunning ? (expanded ? 1.0 : 0.55) : 0.7)
                    .animation(isRunning ? RingMotion.breathPhase(duration: phaseSeconds).resolved(reduceMotion: reduceMotion) : nil, value: expanded)
                VStack(spacing: 4) {
                    Text(isRunning ? phase.rawValue.trimmingCharacters(in: .whitespaces) : "Ready")
                        .font(RingTypography.title2).foregroundStyle(RingTheme.Content.primary)
                    if isRunning { Text(timeLeft).font(RingTypography.footnoteNumeric).foregroundStyle(RingTheme.Content.secondary) }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isRunning ? "\(phase.rawValue), \(timeLeft) left" : "Breathing guide, \(minutes) minutes")

            if let before, let after, !isRunning {
                Text(after < before ? "Heart rate settled from \(Int(before)) to \(Int(after))" : "Heart rate \(Int(before)) → \(Int(after))")
                    .font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary)
            } else if !isRunning, before != nil, after == nil {
                Text("Heart rate is tracked while you breathe when the ring is worn").font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary)
            }

            Button(isRunning ? "Stop" : "Start") { isRunning ? stop() : start() }
                .buttonStyle(RingPrimaryButtonStyle())
        }
        .onDisappear { stop() }
    }

    private var timeLeft: String {
        let m = remaining / 60, s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }

    private func start() {
        before = currentHeartRate()
        after = nil
        remaining = minutes * 60
        phase = .inhale
        isRunning = true
        RingHaptics.breathCue()
        task = Task { @MainActor in
            let order: [Phase] = [.inhale, .holdIn, .exhale, .holdOut]
            var index = 0
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                remaining -= 1
                if remaining % Int(phaseSeconds) == 0 {
                    index = (index + 1) % order.count
                    phase = order[index]
                    RingHaptics.breathCue()
                }
            }
            if !Task.isCancelled { finish() }
        }
    }

    private func finish() {
        after = currentHeartRate()
        isRunning = false
        RingHaptics.success()
    }

    private func stop() {
        task?.cancel()
        task = nil
        if isRunning { after = currentHeartRate() }
        isRunning = false
    }
}

#Preview {
    BreathingGuide(currentHeartRate: { 72 }).ringCard().padding().background(RingTheme.Background.base)
}
