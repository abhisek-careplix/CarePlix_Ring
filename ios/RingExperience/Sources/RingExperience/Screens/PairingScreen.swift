//
//  PairingScreen.swift
//  RingExperience
//
//  Renders EXACTLY ONE thing per `RingDiscoveryPhase`, per RingDiscovery/README.md:
//
//    searching        breathing ring, no error text, no disabled retry
//    found            list, strongest first
//    foundNothing     "No ring found" + an ENABLED retry
//    blocked(state)   the specific problem + Settings / turn Bluetooth on
//    connecting       breathing ring
//    paired           the first heartbeat, haptic
//    connectionFailed specific copy; needsPasscode is a prompt, not an error
//
//  The retry control is never gated on "am I scanning" — `RingScanner` is single-flight.
//

import SwiftUI
import UIKit
import RingDiscovery

public struct PairingScreen: View {
    @ObservedObject private var model: RingPairingModel
    private let demoPairing: (() -> Void)?
    private let onSkip: (() -> Void)?
    private let onPaired: (RingCandidate) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var passcode = ""
    @State private var reportedPaired = false

    /// - Parameters:
    ///   - demoPairing: when present (demo builds), a "Use demo ring" button pairs a fixture ring.
    ///   - onSkip: onboarding lets the user pair later; nil hides the control.
    public init(model: RingPairingModel, demoPairing: (() -> Void)? = nil, onSkip: (() -> Void)? = nil, onPaired: @escaping (RingCandidate) -> Void) {
        self.model = model
        self.demoPairing = demoPairing
        self.onSkip = onSkip
        self.onPaired = onPaired
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing24) {
                    Text("Pair your ring").font(RingTypography.largeTitle).foregroundStyle(RingTheme.Content.primary)
                    Text("Take the ring off the charger and hold it near your phone.").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary)
                    phaseView
                }
                .padding(RingTheme.Metrics.spacing24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .background(RingTheme.Background.base)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.onForeground() } }
        .ringMotion(RingMotion.stateChange, value: model.phase)
    }

    // MARK: One view per phase

    @ViewBuilder
    private var phaseView: some View {
        switch model.phase {
        case .idle, .searching:
            waiting("Looking for your ring")
        case .found:
            ringList
        case .foundNothing:
            statement(symbol: "magnifyingglass", title: "No ring found", body: "Is it on the charger? Take it off, keep it within arm's reach, and try again.")
        case let .blocked(state):
            blocked(state)
        case .connecting:
            waiting("Connecting")
        case .paired:
            paired
        case let .connectionFailed(state):
            failed(state)
        }
    }

    private func waiting(_ title: String) -> some View {
        VStack(spacing: RingTheme.Metrics.spacing16) {
            RingIllustration(diameter: 140).ringBreathingPulse(scale: 0.96...1.04, opacity: 0.7...1.0)
            Text(title).font(RingTypography.title3).foregroundStyle(RingTheme.Content.primary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var ringList: some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing8) {
            RingEyebrow("Rings nearby · nearest first")
            ForEach(model.rings) { ring in
                Button { model.connect(to: ring, isFirstPairing: true) } label: {
                    HStack {
                        RingIllustration(diameter: 36)
                        Text(ring.displayName).font(RingTypography.headline).foregroundStyle(RingTheme.Content.primary)
                        Spacer()
                        Text(ring.signal.dBmValue.map { "\($0) dBm" } ?? "").font(RingTypography.caption).monospacedDigit().foregroundStyle(RingTheme.Content.tertiary)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(RingTheme.Content.tertiary)
                    }
                    .frame(minHeight: RingTheme.Metrics.minTouchTarget)
                    .ringCard(padding: RingTheme.Metrics.spacing12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(ring.displayName)\(ring.signal.dBmValue.map { ", signal \($0) dBm" } ?? "")")
                .accessibilityHint("Connects to this ring")
            }
        }
    }

    private func statement(symbol: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(RingTheme.Status.abstained)
            Text(title).font(RingTypography.title3).foregroundStyle(RingTheme.Content.primary)
            Text(body).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
    }

    @ViewBuilder
    private func blocked(_ state: RingRadioState) -> some View {
        switch state {
        case .poweredOff:
            statement(symbol: "antenna.radiowaves.left.and.right.slash", title: "Bluetooth is off", body: "Turn Bluetooth on in Control Centre or Settings, then come back — scanning resumes on its own.")
        case .unauthorized:
            VStack(spacing: RingTheme.Metrics.spacing12) {
                statement(symbol: "lock", title: "Bluetooth access needed", body: "Allow Bluetooth for CarePlix Ring in Settings. It is used only to talk to your ring.")
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }.buttonStyle(RingSecondaryButtonStyle())
            }
        case .unsupported:
            statement(symbol: "xmark.octagon", title: "This device has no Bluetooth LE", body: "The ring needs a phone with Bluetooth Low Energy.")
        case .warmingUp, .ready:
            waiting("Starting Bluetooth")
        }
    }

    private var paired: some View {
        VStack(spacing: RingTheme.Metrics.spacing16) {
            RingIllustration(diameter: 140, showsHeartbeat: true)
            Text("Paired").font(RingTypography.title).foregroundStyle(RingTheme.Content.primary)
            Text("Your ring's first heartbeat. Battery reads in a moment.").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reportedPaired, case let .paired(id) = model.phase, let ring = model.rings.first(where: { $0.id == id }) else { return }
            reportedPaired = true
            RingHaptics.heartbeat()
            onPaired(ring)
        }
    }

    @ViewBuilder
    private func failed(_ state: RingLinkState) -> some View {
        switch state {
        case .needsPasscode:
            VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
                Text("Enter the ring's code").font(RingTypography.title3).foregroundStyle(RingTheme.Content.primary)
                Text("This ring carries a 4-digit code. It is printed on the charger or in the box.").font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary)
                TextField("0000", text: $passcode).keyboardType(.numberPad).font(RingTypography.title2).multilineTextAlignment(.center).padding().background(RingTheme.Background.recessed, in: RoundedRectangle(cornerRadius: RingTheme.Metrics.cornerSmall))
                    .accessibilityLabel("Ring code")
                // VERIFY on device: RingPairingModel has no passcode entry point yet; the code is
                // collected here so the flow is complete and can be wired when the link exposes it.
                Text("Passcode pairing is wired once the link layer accepts a code.").font(RingTypography.caption).foregroundStyle(RingTheme.Content.tertiary)
            }
            .ringCard()
        case .timedOut:
            statement(symbol: "clock.badge.exclamationmark", title: "Couldn't reach your ring", body: "It may have gone back to sleep. Take it off the charger again and retry.")
        case .disconnected:
            statement(symbol: "antenna.radiowaves.left.and.right.slash", title: "The ring disconnected", body: "Keep it close to your phone and try again.")
        case .radioOff:
            statement(symbol: "antenna.radiowaves.left.and.right.slash", title: "Bluetooth turned off", body: "Turn it back on and retry.")
        case let .unmodelled(raw):
            statement(symbol: "questionmark.circle", title: "Unexpected reply from the ring", body: "Code \(raw). Retry; if it persists, restart the ring on its charger.")
        case .connecting, .connected, .verified, .awaitingConfirmationOnRing:
            waiting("Connecting")
        }
    }

    // MARK: Footer — retry is never disabled

    private var footer: some View {
        VStack(spacing: RingTheme.Metrics.spacing8) {
            switch model.phase {
            case .paired:
                EmptyView()
            case .found:
                Button("Search again") { model.retry() }.buttonStyle(RingSecondaryButtonStyle())
            default:
                Button(model.phase.showsSpinner ? "Restart search" : "Try again") { model.retry() }.buttonStyle(RingPrimaryButtonStyle())
            }
            if let demoPairing { Button("Use demo ring", action: demoPairing).buttonStyle(RingSecondaryButtonStyle()) }
            if let onSkip { Button("Pair later", action: onSkip).font(RingTypography.footnote).foregroundStyle(RingTheme.Content.secondary).frame(minHeight: 40) }
        }
        .padding(RingTheme.Metrics.spacing24)
        .background(RingTheme.Background.elevated)
    }
}

#Preview("Searching") {
    NavigationStack { PairingScreen(model: RingPairingModel(), demoPairing: {}, onSkip: {}, onPaired: { _ in }) }
}
