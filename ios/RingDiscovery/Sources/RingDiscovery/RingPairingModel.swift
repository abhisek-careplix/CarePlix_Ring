//
//  RingPairingModel.swift
//  RingDiscovery
//
//  The pairing screen's state, as ONE state machine.
//
//  WHY ONE ENUM AND NOT SEVERAL BOOLEANS
//  -------------------------------------
//  The screenshot that started this work showed a spinner reading "Looking for your ring" AND an
//  error reading "Could not reach your ring. Try again." at the same time, above a "Search for
//  ring" button that was disabled. Three controls, three different variables, no single source of
//  truth — so the UI could and did assert two contradictory things at once, and offered no way out
//  of either.
//
//  That is not a copy problem. `isScanning` was set true when a scan began and cleared only when
//  the scan's stream finished; a scan that found nothing never finished, so it never cleared, so
//  any control gated on `!isScanning` stayed disabled for the life of the process. Force-quitting
//  was the only move the user had left — which is precisely the bare `launch` breadcrumb in the
//  diagnostics panel, and it was mistaken for a crash for ten builds.
//
//  Two rules follow, and they are enforced by construction here:
//
//    1. ONE `phase`. The view renders exactly one of its cases. A spinner and an error cannot
//       coexist because they are different cases of the same value.
//    2. THE RETRY CONTROL IS NEVER GATED ON "AM I SCANNING". Starting a scan supersedes any scan
//       already running (`RingScanner` is single-flight), so a second tap is always safe — and a
//       user looking at an error must always be able to act on it.
//

import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(Combine)
import Combine
#endif

// MARK: - Phase

#if canImport(CoreBluetooth)
import CoreBluetooth

/// What the pairing screen is doing, as one value.
public enum RingDiscoveryPhase: Sendable, Equatable {

    /// Nothing has started yet.
    case idle

    /// Scanning, nothing found so far. The ONLY case that shows a spinner.
    case searching

    /// Scanning or finished, with at least one ring to choose from.
    case found

    /// The scan ran its full window and found nothing. Distinct from `searching`: this is the
    /// case that says so plainly and invites a retry.
    case foundNothing

    /// The radio cannot be used. Carries which problem, so the copy can be specific and the
    /// action can be the right one (open Settings, or turn Bluetooth on).
    case blocked(RingRadioState)

    /// Connecting to a chosen ring.
    case connecting(RingCandidate.ID)

    /// The handshake succeeded.
    case paired(RingCandidate.ID)

    /// A connection attempt failed. Carries the state so the copy can be specific.
    case connectionFailed(RingLinkState)

    public var showsSpinner: Bool {
        switch self {
        case .searching, .connecting: return true
        case .idle, .found, .foundNothing, .blocked, .paired, .connectionFailed: return false
        }
    }

    /// True only for cases that are genuinely an error the user should be told about.
    ///
    /// `foundNothing` is deliberately NOT an error: it is a normal outcome of a short scan and
    /// reads better as a plain statement with a retry than as a failure.
    public var isFailure: Bool {
        switch self {
        case .blocked, .connectionFailed: return true
        case .idle, .searching, .found, .foundNothing, .connecting, .paired: return false
        }
    }
}

// MARK: - Model

#if canImport(Combine)

/// Drives discovery and connection for the pairing screen.
@MainActor
public final class RingPairingModel: ObservableObject {

    @Published public private(set) var phase: RingDiscoveryPhase = .idle
    @Published public private(set) var rings: [RingCandidate] = []
    @Published public private(set) var radio: RingRadioState = .warmingUp

    private let scanner: RingScanner
    private let link: RingLinking?
    private var policy: RingDiscoveryPolicy

    private var scanTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?

    public init(
        scanner: RingScanner = RingScanner(),
        link: RingLinking? = nil,
        policy: RingDiscoveryPolicy = .standard
    ) {
        self.scanner = scanner
        self.link = link
        self.policy = policy
    }

    // MARK: Lifecycle

    /// Call from the pairing screen's `onAppear`.
    ///
    /// `prepare()` runs first and separately from the scan: it forces the vendor SDK's lazily
    /// created singleton — and the `CBCentralManager` it owns — into existence early, so that
    /// stack has settled by the time a connection is attempted. Skipping this is how a connect
    /// lands on a manager that is still `.unknown`.
    public func onAppear() {
        link?.prepare()
        startScan()
    }

    /// Call from `onDisappear`. Stops the radio and abandons any in-flight work.
    public func onDisappear() {
        scanTask?.cancel()
        scanTask = nil
        connectTask?.cancel()
        connectTask = nil
        scanner.stop()
    }

    /// Call when the app returns to the foreground, so a permission granted in Settings takes
    /// effect without the user having to find a retry button.
    public func onForeground() {
        guard !phase.showsSpinner else { return }
        if case .paired = phase { return }
        startScan()
    }

    // MARK: Scanning

    /// Starts (or restarts) a scan.
    ///
    /// Deliberately takes no "am I already scanning" guard: `RingScanner` supersedes a running
    /// scan, so this is idempotent from the caller's side. See rule 2 in the file header.
    public func startScan() {
        scanTask?.cancel()
        rings.removeAll()
        phase = .searching

        let stream = scanner.scan(policy: policy)
        scanTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    /// What the retry button calls. Never disabled while a scan runs.
    public func retry() { startScan() }

    private func handle(_ event: RingScanEvent) {
        switch event {
        case .radioStateChanged(let state):
            radio = state
            if !state.canScan, state != .warmingUp {
                phase = .blocked(state)
            }

        case .discovered(let ring):
            insertOrRefresh(ring)
            if case .connecting = phase { return }
            if case .paired = phase { return }
            phase = .found

        case .ended(let outcome):
            switch outcome {
            case .cancelled:
                break   // a supersede or a teardown; the next scan owns the phase
            case .deadlineReached:
                if case .connecting = phase { return }
                if case .paired = phase { return }
                phase = rings.isEmpty ? .foundNothing : .found
            case .radioUnavailable(let state):
                radio = state
                phase = .blocked(state)
            }
        }
    }

    /// Inserts a ring, or refreshes the one already listed, then re-sorts strongest-first.
    ///
    /// Devices whose signal strength was not reported sort LAST. Sorting them first — which is
    /// what happens if the 127 sentinel is treated as a number — puts the one device nobody can
    /// measure at the top of a list whose whole purpose is "the nearest ring is yours".
    private func insertOrRefresh(_ ring: RingCandidate) {
        if let index = rings.firstIndex(where: { $0.id == ring.id }) {
            rings[index] = ring
        } else {
            rings.append(ring)
        }
        rings.sort { $0.signal.sortKey > $1.signal.sortKey }
    }

    // MARK: Connecting

    public func connect(to ring: RingCandidate, isFirstPairing: Bool = true) {
        guard let link else { return }

        // A live scan starves the connection attempt — the radio cannot do both well.
        scanTask?.cancel()
        scanTask = nil
        scanner.stop()

        phase = .connecting(ring.id)

        let stream = link.connect(to: ring, isFirstPairing: isFirstPairing)
        connectTask = Task { [weak self] in
            for await state in stream {
                guard let self else { return }
                await self.handle(linkState: state, for: ring)
            }
        }
    }

    private func handle(linkState state: RingLinkState, for ring: RingCandidate) {
        switch state {
        case .connecting, .connected, .awaitingConfirmationOnRing:
            phase = .connecting(ring.id)

        case .verified:
            // The handshake, not the BLE connection, is what "paired" means.
            phase = .paired(ring.id)

        case .needsPasscode:
            // Not an error: this ring carries a non-default code and the user must supply it.
            // The host app presents its passcode entry from here.
            phase = .connectionFailed(.needsPasscode)

        case .timedOut, .disconnected, .radioOff, .unmodelled:
            phase = .connectionFailed(state)
        }
    }
}

#endif

#endif
