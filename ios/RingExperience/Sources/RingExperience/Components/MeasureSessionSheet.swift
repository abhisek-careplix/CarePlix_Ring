//
//  MeasureSessionSheet.swift
//  RingExperience
//
//  One sheet for every spot test. Preparing → Measuring (progress ring, live value for HR) →
//  Result (state chip, typical band, Save / Discard) — with four honest exits, each with its own
//  copy and a retry: Not on finger · Ring busy · Battery too low · Timed out. Dismissing the
//  sheet cancels the test on the ring.
//

import SwiftUI

public struct MeasureSessionSheet<DS: RingDataSource>: View {
    @ObservedObject private var dataSource: DS
    private let kind: SpotKind
    private let onSaved: ((SpotMeasurement) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var state: MeasureSessionState = .preparing
    @State private var attempt = 0

    public init(dataSource: DS, kind: SpotKind, onSaved: ((SpotMeasurement) -> Void)? = nil) {
        self.dataSource = dataSource
        self.kind = kind
        self.onSaved = onSaved
    }

    private var typicalRange: ClosedRange<Double>? {
        dataSource.today.vitals.first { $0.kind == kind.vital }?.typicalRange
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: RingTheme.Metrics.spacing24) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ringMotion(RingMotion.stateChange, value: state)
                WellnessTag()
            }
            .padding(RingTheme.Metrics.spacing24)
            .background(RingTheme.Background.elevated)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(state.isTerminal ? "Close" : "Cancel") { dataSource.cancelSpot(); dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task(id: attempt) { await run() }
    }

    private func run() async {
        state = .preparing
        for await next in dataSource.startSpot(kind) {
            state = next
            if case .result = next { RingHaptics.success() }
            if case .notWorn = next { RingHaptics.warning() }
        }
        // A stream that ends without a terminal state is a bug on the data source's side, but
        // the user must never be left on a spinner: say so.
        if !state.isTerminal { state = .failed("The ring stopped without a result") }
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        switch state {
        case .preparing:
            waiting(title: "Getting ready", subtitle: kind.instruction, progress: 0, live: nil)
        case let .measuring(progress, live):
            waiting(title: "Hold still", subtitle: kind.instruction, progress: progress, live: live)
        case let .result(measurement):
            result(measurement)
        case .notWorn:
            exit(symbol: "hand.raised.slash", title: "Not on your finger", body: "Put the ring on, sensor bumps facing your palm, and hold still.", retry: "Try again")
        case .busy:
            exit(symbol: "hourglass", title: "Ring is busy", body: "The ring is finishing another measurement. Wait a moment and try again.", retry: "Try again")
        case let .lowBattery(percent):
            exit(symbol: "battery.0percent", title: "Battery too low", body: "This test needs more charge\(percent.map { " (\($0) %)" } ?? ""). Charge the ring and try again.", retry: nil)
        case .timedOut:
            exit(symbol: "clock.badge.exclamationmark", title: "Timed out", body: "The ring did not answer in time. Keep it close to your phone and try again.", retry: "Try again")
        case let .failed(reason):
            exit(symbol: "xmark.circle", title: "No result", body: reason, retry: "Try again")
        }
    }

    private func waiting(title: String, subtitle: String, progress: Double, live: Double?) -> some View {
        VStack(spacing: RingTheme.Metrics.spacing24) {
            ZStack {
                Circle().stroke(RingTheme.Background.recessed, style: StrokeStyle(lineWidth: RingTheme.Metrics.ringStroke, lineCap: .round))
                Circle().trim(from: 0, to: progress)
                    .stroke(kind == .heartRate ? AnyShapeStyle(RingTheme.Brand.ringGradient()) : AnyShapeStyle(RingTheme.Status.good), style: StrokeStyle(lineWidth: RingTheme.Metrics.ringStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .ringMotion(RingMotion.valueChange, value: progress)
                VStack(spacing: 2) {
                    if let live {
                        RingVitalValue(value: RingFormat.spot(kind, live), unit: kind.unit, size: .hero).ringNumericTransition()
                    } else {
                        Text("\(Int((1 - progress) * kind.durationSeconds).clamped(0, Int(kind.durationSeconds))) s")
                            .ringVitalNumber(.large).foregroundStyle(RingTheme.Content.secondary)
                    }
                }
            }
            .frame(width: 176, height: 176)
            .ringBreathingPulse()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue("\(Int(progress * 100)) percent\(live.map { ", live \(RingFormat.spot(kind, $0)) \(kind.unit)" } ?? "")")

            Text(title).font(RingTypography.title2).foregroundStyle(RingTheme.Content.primary)
            Text(subtitle).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).multilineTextAlignment(.center)
        }
    }

    private func result(_ m: SpotMeasurement) -> some View {
        VStack(spacing: RingTheme.Metrics.spacing24) {
            RingVitalValue(value: RingFormat.spot(kind, m.value), unit: kind.unit, size: .hero)
            StateChip(state: m.state)
            if let band = kind.vital.flatMap({ RingFormat.range(typicalRange, kind: $0) }) {
                Text("Your usual \(band)").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary)
            } else if kind == .heartRate {
                Text("Daytime reading · compare with your resting rate on Measure").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).multilineTextAlignment(.center)
            }
            RingProvenance("Measured just now · \(kind == .skinTemperature ? "finger skin sensor" : "optical sensor")")
            VStack(spacing: RingTheme.Metrics.spacing8) {
                Button("Save") { dataSource.saveSpot(m); onSaved?(m); dismiss() }.buttonStyle(RingPrimaryButtonStyle())
                Button("Discard") { dismiss() }.buttonStyle(RingSecondaryButtonStyle())
            }
        }
    }

    private func exit(symbol: String, title: String, body: String, retry: String?) -> some View {
        VStack(spacing: RingTheme.Metrics.spacing16) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(RingTheme.Status.fair).accessibilityHidden(true)
            Text(title).font(RingTypography.title2).foregroundStyle(RingTheme.Content.primary)
            Text(body).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button(retry) { attempt += 1 }.buttonStyle(RingPrimaryButtonStyle())
            }
            Button("Close") { dismiss() }.buttonStyle(RingSecondaryButtonStyle())
        }
    }
}

extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.min(Swift.max(self, lo), hi) }
}

#Preview("Heart rate") {
    MeasureSessionSheet(dataSource: MockRingDataSource(), kind: .heartRate)
}

#Preview("Not worn") {
    MeasureSessionSheet(dataSource: MockRingDataSource(scenario: .notWorn), kind: .bloodOxygen)
}
