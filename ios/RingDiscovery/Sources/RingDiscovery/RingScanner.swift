//
//  RingScanner.swift
//  RingDiscovery
//
//  An app-owned CoreBluetooth scan for CarePlix rings.
//
//  WHY THIS FILE EXISTS — THE BUG IT REPLACES
//  ------------------------------------------
//  The ring app discovered nothing, ten builds running, reporting "vendor reported 0, usable 0".
//  The vendor SDK's scan entry point (`veepooSDKStartScanDeviceAndReceiveScanningDevice:`) does
//  NOT perform an open scan. Disassembly of the shipping `VeepooBleSDK` binary shows its private
//  `-[VPBleCentralManage startScanDevice]` ending in:
//
//      [self.centralManager scanForPeripheralsWithServices:@[FFFF, FEE7, 0001, 180D] options:nil]
//
//  That array is a CoreBluetooth-level filter. iOS never delivers a non-matching advertisement to
//  the SDK at all, so no app-side setting can widen it: `manufacturerIDFilter` and `rrisLimit` are
//  both applied downstream of it. And iOS matches only service UUIDs present in the 31-byte
//  ADVERTISEMENT payload — not the GATT table — so a ring that exposes 180D in GATT but spends its
//  advertising budget on a `LOOP-XXXX` name is invisible to that scan, permanently, on every
//  attempt.
//
//  So the app must own discovery. This scanner runs `scanForPeripherals(withServices: nil, …)` on
//  its own central and matches on the advertised name. The vendor SDK still owns the link — see
//  `RingLink`, which hands the resulting `CBPeripheral` to `veepooSDKSelfScanConnectDevice:`, the
//  bypass the SDK ships for precisely this case.
//
//  THREE THINGS THAT LOOK LIKE DETAILS AND ARE NOT
//  -----------------------------------------------
//  1. `withServices: nil` is the whole point. Narrowing it to "be efficient" restores the bug.
//  2. The `CBPeripheral` objects must be RETAINED. CoreBluetooth does not hold them for you; a
//     peripheral you dropped cannot be connected to, and the failure surfaces later, at connect,
//     looking like a firmware problem.
//  3. Every hit is logged before any filtering. When this fails in the field, the question is
//     always "did the radio see anything at all" — and that question must be answerable from a
//     console, not from a breadcrumb panel.
//

import Foundation

#if canImport(CoreBluetooth)
import CoreBluetooth
import os

// MARK: - Radio state

/// The phone's Bluetooth radio, as it concerns scanning.
public enum RingRadioState: Sendable, Equatable {
    /// Still resolving. Not an error; `CBCentralManager` starts here on every launch.
    case warmingUp
    /// The user has not been asked, or said no, or the device is restricted.
    case unauthorized
    /// Authorized, but the radio is switched off.
    case poweredOff
    /// No BLE hardware.
    case unsupported
    /// Authorized and powered on. Scanning is possible.
    case ready

    public var canScan: Bool { self == .ready }
}

// MARK: - A discovered ring

/// One ring seen on the air.
///
/// `@unchecked Sendable` because of the `CBPeripheral`, which is a class CoreBluetooth does not
/// mark `Sendable`. The unchecked claim is earned, not waived: this type is constructed on the
/// scanner's serial queue and the peripheral inside it is only ever (a) stored, or (b) handed
/// straight to the vendor SDK on the main queue. Nothing in this module calls a method on it from
/// two queues, and nothing mutates it at all.
public struct RingCandidate: Identifiable, @unchecked Sendable {

    /// The peripheral's CoreBluetooth identifier, as a string.
    ///
    /// THIS IS THE ONLY IDENTITY AVAILABLE. iOS never exposes a peripheral's MAC address over the
    /// air — `CBPeripheral.identifier` is an opaque UUID, and it differs on every phone. Code that
    /// requires a MAC at scan time drops every device and leaves the list empty. The ring's real
    /// MAC, if the firmware exposes it, is readable only after a connection is established, and is
    /// then good for display and support logs — never as the reconnect key.
    public let id: String

    /// The name from the advertisement (`CBAdvertisementDataLocalNameKey`), trimmed.
    ///
    /// NOT `CBPeripheral.name`, which is a cached GAP name: frequently nil during a scan, and
    /// stale after a rename — so a ring reprovisioned to `LOOP-XXXX` can still report its factory
    /// name there for days.
    public let advertisedName: String

    public let signal: RingSignal

    /// The live peripheral, retained for the connect that follows.
    public let peripheral: CBPeripheral

    public var displayName: String { advertisedName }
}

// MARK: - Scan lifecycle

/// Why a scan ended. Every case is a distinct thing to tell the user.
public enum RingScanOutcome: Sendable, Equatable {
    /// Stopped by us — the screen closed, or a connect began.
    case cancelled
    /// The deadline passed. Zero or more rings were found; the caller knows which.
    case deadlineReached
    /// The radio was never usable. Carries the state so the UI can say which problem it is.
    case radioUnavailable(RingRadioState)
}

public enum RingScanEvent: Sendable {
    case radioStateChanged(RingRadioState)
    case discovered(RingCandidate)
    case ended(RingScanOutcome)
}

// MARK: - Scanner

/// Scans for rings and streams what it finds.
///
/// CONCURRENCY. One private serial queue owns the `CBCentralManager` and every piece of mutable
/// state. `CBCentralManager` delivers its delegate callbacks on the queue it was constructed with,
/// so callbacks land already on that queue and need no further hopping. `@unchecked Sendable` is
/// justified by that confinement, not waived.
public final class RingScanner: NSObject, @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.careplix.ring.scanner")
    private let log = Logger(subsystem: "com.careplix.ring", category: "RingScanner")

    private var central: CBCentralManager?
    private var policy: RingDiscoveryPolicy = .standard

    private var continuation: AsyncStream<RingScanEvent>.Continuation?
    private var seenIdentifiers = Set<String>()

    /// Retains discovered peripherals for the lifetime of the scan.
    ///
    /// See the file header, point 2: CoreBluetooth holds only a weak interest in peripherals it
    /// hands you. Dropping them makes a later connect fail for reasons that look like hardware.
    private var retainedPeripherals: [String: CBPeripheral] = [:]

    private var deadlineTimer: DispatchSourceTimer?
    private var warmUpTimer: DispatchSourceTimer?
    private var isScanning = false

    /// Increments on every `scan(policy:)`, so a superseded stream can tell whether it is still the
    /// current one.
    ///
    /// WITHOUT THIS, SUPERSEDING A SCAN CANCELS ITS OWN REPLACEMENT. Finishing the outgoing stream
    /// fires its `onTermination`, which asks the scanner to stop — and by the time that request is
    /// serviced on the queue, the *new* scan is the one it would stop. The symptom would be a
    /// pairing screen that goes permanently quiet whenever a scan is restarted, which is
    /// uncomfortably close to the bug this whole module exists to fix.
    private var generation: UInt64 = 0

    public override init() {
        super.init()
    }

    // MARK: Public API

    /// The radio's state right now, for a readiness gate that runs before any scan.
    public var radioState: RingRadioState {
        queue.sync { currentRadioState() }
    }

    /// Starts a scan and streams everything it produces.
    ///
    /// Single-flight: starting a scan supersedes any scan already running, so the three SwiftUI
    /// hooks that typically drive a pairing screen (`onAppear`, an authorization change, and a
    /// `scenePhase` change) cannot stack scans on top of each other.
    ///
    /// Cancelling the consuming task stops the radio.
    public func scan(policy: RingDiscoveryPolicy = .standard) -> AsyncStream<RingScanEvent> {
        AsyncStream(RingScanEvent.self, bufferingPolicy: .bufferingNewest(64)) { continuation in
            queue.async { [weak self] in
                guard let self else { continuation.finish(); return }

                // Stop whatever was running BEFORE claiming the new generation, so the outgoing
                // stream's termination handler resolves against its own generation and not this one.
                self.finishCurrentStream(with: .cancelled)

                self.generation &+= 1
                let generation = self.generation

                self.policy = policy
                self.continuation = continuation
                self.seenIdentifiers.removeAll()
                self.retainedPeripherals.removeAll()

                continuation.onTermination = { [weak self] _ in
                    self?.stop(ifGeneration: generation)
                }

                if self.central == nil {
                    // Creating the manager is what raises the system Bluetooth permission prompt,
                    // so it happens here — at a moment the app chose, on a screen that explains
                    // why — rather than invisibly from a vendor library on some later code path.
                    self.central = CBCentralManager(delegate: self, queue: self.queue)
                }

                continuation.yield(.radioStateChanged(self.currentRadioState()))
                // Arm the warm-up first: if the radio is already usable, `startScanningIfReady`
                // cancels it in the same breath.
                self.armWarmUpTimer()
                self.startScanningIfReady()
            }
        }
    }

    /// Stops the scan. Safe to call repeatedly, and safe to call when no scan is running.
    public func stop() {
        queue.async { [weak self] in
            self?.finishCurrentStream(with: .cancelled)
        }
    }

    /// Stops the scan only if `generation` is still the current one.
    private func stop(ifGeneration generation: UInt64) {
        queue.async { [weak self] in
            guard let self, self.generation == generation else { return }
            self.finishCurrentStream(with: .cancelled)
        }
    }

    /// Hands back a retained peripheral by id, for the connect step.
    public func peripheral(for id: String) -> CBPeripheral? {
        queue.sync { retainedPeripherals[id] }
    }

    // MARK: Scan control (queue-confined)

    private func startScanningIfReady() {
        guard !isScanning, let central, central.state == .poweredOn else { return }

        isScanning = true
        cancelWarmUpTimer()

        // withServices: nil — see the file header. This is the fix.
        //
        // allowDuplicates: false keeps the callback rate and the battery cost down. We de-duplicate
        // by identifier anyway, and nothing here needs a refreshed RSSI badly enough to pay for a
        // continuous callback storm.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        log.info("ring scan started (open scan, no service filter)")
        armDeadlineTimer()
    }

    private func armDeadlineTimer() {
        cancelDeadlineTimer()
        guard policy.deadline > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + policy.deadline)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.log.info("ring scan deadline reached after \(self.policy.deadline, privacy: .public)s")
            self.finishCurrentStream(with: .deadlineReached)
        }
        timer.resume()
        deadlineTimer = timer
    }

    /// Fails a scan that never got a usable radio, instead of leaving it pending forever.
    ///
    /// The silent version of this is the bug: a scan waiting on a radio that will never arrive
    /// looks exactly like a scan that is working, for as long as anyone is willing to watch it.
    private func armWarmUpTimer() {
        cancelWarmUpTimer()
        guard policy.radioWarmUp > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + policy.radioWarmUp)
        timer.setEventHandler { [weak self] in
            guard let self, !self.isScanning else { return }
            let state = self.currentRadioState()
            self.log.error("radio never became usable (state=\(String(describing: state), privacy: .public))")
            self.finishCurrentStream(with: .radioUnavailable(state))
        }
        timer.resume()
        warmUpTimer = timer
    }

    private func cancelDeadlineTimer() {
        deadlineTimer?.cancel()
        deadlineTimer = nil
    }

    private func cancelWarmUpTimer() {
        warmUpTimer?.cancel()
        warmUpTimer = nil
    }

    private func finishCurrentStream(with outcome: RingScanOutcome) {
        cancelDeadlineTimer()
        cancelWarmUpTimer()

        if isScanning {
            central?.stopScan()
            isScanning = false
        }

        guard let continuation else { return }
        self.continuation = nil
        continuation.yield(.ended(outcome))
        continuation.finish()
    }

    private func currentRadioState() -> RingRadioState {
        guard let central else { return .warmingUp }
        switch central.state {
        case .poweredOn:    return .ready
        case .poweredOff:   return .poweredOff
        case .unauthorized: return .unauthorized
        case .unsupported:  return .unsupported
        // `resetting` and `unknown` are both transient: the radio has not told us anything yet.
        // Neither is an error, and reporting either as one produces a "Bluetooth is off" screen on
        // a phone whose Bluetooth is fine. The warm-up timer is what turns a state that never
        // resolves into a real, reported failure.
        case .resetting:    return .warmingUp
        case .unknown:      return .warmingUp
        @unknown default:   return .warmingUp
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension RingScanner: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = currentRadioState()
        log.info("radio state=\(String(describing: state), privacy: .public)")
        continuation?.yield(.radioStateChanged(state))

        switch central.state {
        case .poweredOn:
            // The radio arriving late is the normal case, not the exceptional one. Start now.
            startScanningIfReady()
        case .poweredOff, .unauthorized, .unsupported:
            // `finishCurrentStream` stops the radio and clears `isScanning` itself.
            finishCurrentStream(with: .radioUnavailable(state))
        case .resetting, .unknown:
            isScanning = false
        @unknown default:
            break
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // The advertised name, NOT peripheral.name. See RingCandidate.advertisedName.
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let signal = RingSignal(coreBluetoothValue: RSSI)
        let identifier = peripheral.identifier.uuidString

        // Logged BEFORE any filtering, unconditionally. This line is what makes the next field
        // failure a two-minute console read instead of a fortnight. The name is hashed rather than
        // printed: it is a stable identifier for someone's device.
        log.info("""
            scan hit: name=\(advertisedName ?? "nil", privacy: .private(mask: .hash)) \
            rssi=\(signal.dBmValue ?? 127, privacy: .public) \
            id=\(identifier, privacy: .private(mask: .hash))
            """)

        guard policy.matcher.matches(advertisedName),
              let name = policy.matcher.normalised(advertisedName),
              policy.admits(signal) else { return }

        guard seenIdentifiers.insert(identifier).inserted else { return }

        // Retain it — see the file header, point 2.
        retainedPeripherals[identifier] = peripheral

        continuation?.yield(.discovered(
            RingCandidate(
                id: identifier,
                advertisedName: name,
                signal: signal,
                peripheral: peripheral
            )
        ))
    }
}

#endif
