//
//  RingAdvertising.swift
//  RingDiscovery
//
//  What a ring puts on the air, and how we decide a scan hit is one of ours.
//
//  This file is deliberately free of CoreBluetooth so the matching rules can be unit tested on
//  any platform. Everything here is a pure value transformation.
//

import Foundation

// MARK: - Advertised name matching

/// Decides whether an advertised local name belongs to a CarePlix ring.
///
/// WHY THIS IS A TYPE AND NOT A `hasPrefix` CALL AT THE CALL SITE
/// --------------------------------------------------------------
/// The failure this module exists to fix was a scan that matched nothing. A hard-coded prefix
/// test buried in a delegate callback is exactly how that happens again: it is invisible in
/// review, untestable, and silently wrong the day the provisioning name changes. Rings are
/// named by `tools/ring-provisioner` (`RingNaming.kt`), which writes `LOOP` or `LOOP-XXXX` —
/// so the app's matcher and the provisioner's naming scheme are one decision in two
/// repositories, and it needs to be legible in both.
///
/// UNPROVISIONED UNITS ARE THE TRAP
/// --------------------------------
/// A ring that has not been through the provisioner still advertises *something* — a factory
/// name, or nothing at all. A matcher tight enough to admit only `LOOP-XXXX` makes every
/// unprovisioned unit invisible, which reproduces the original bug on exactly the hardware most
/// likely to be in a developer's hand. Hence `additionalPrefixes` and, above all,
/// ``RingNameMatcher/permissive``: discovery filtering is a display concern, and the diagnostic
/// path must always be able to see everything the radio saw.
public struct RingNameMatcher: Sendable, Equatable {

    /// Name prefixes accepted as a ring. Compared case-insensitively.
    public let prefixes: [String]

    /// When true, any peripheral advertising a non-empty local name is accepted.
    ///
    /// This is the diagnostic mode. It is the correct setting for a "why can't the app see my
    /// ring" screen, and the wrong setting for the pairing list, where a user must not be
    /// offered their neighbour's headphones.
    public let acceptsAnyNamedDevice: Bool

    public init(prefixes: [String] = [RingNameMatcher.brand], acceptsAnyNamedDevice: Bool = false) {
        self.prefixes = prefixes
        self.acceptsAnyNamedDevice = acceptsAnyNamedDevice
    }

    /// The provisioned brand name. Mirrors `RingNaming.BRAND` in the Android provisioner.
    public static let brand = "LOOP"

    /// The pairing list's matcher: provisioned rings only.
    public static let standard = RingNameMatcher()

    /// The diagnostic matcher: everything with a name.
    public static let permissive = RingNameMatcher(acceptsAnyNamedDevice: true)

    /// True when `name` should be surfaced as a ring.
    ///
    /// A nil or blank name never matches, even in permissive mode: a nameless advertisement
    /// carries nothing a human could choose between in a list.
    public func matches(_ name: String?) -> Bool {
        guard let name = normalised(name) else { return false }
        if acceptsAnyNamedDevice { return true }
        return prefixes.contains { prefix in
            let prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty else { return false }
            return name.lowercased().hasPrefix(prefix.lowercased())
        }
    }

    /// Trims surrounding whitespace and rejects blank names.
    ///
    /// Firmware pads advertised names more often than anyone expects, and a trailing space is
    /// enough to break a naive `==`.
    func normalised(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - Signal strength

/// A received signal strength, with an explicit "not reported" case.
///
/// CoreBluetooth signals "no RSSI available" with the sentinel **127**, which is not a weak
/// signal — it is the absence of a measurement. Treating 127 as a number sorts an unmeasurable
/// device to the top of a strongest-first list, which is worse than useless during pairing.
public enum RingSignal: Sendable, Equatable {
    case dBm(Int)
    case notReported

    /// Interprets a CoreBluetooth RSSI number.
    ///
    /// Rejects the 127 sentinel and any non-negative value; a real BLE RSSI is negative.
    public init(coreBluetoothValue: NSNumber?) {
        guard let raw = coreBluetoothValue?.intValue, raw != 127, raw < 0 else {
            self = .notReported
            return
        }
        self = .dBm(raw)
    }

    public var dBmValue: Int? {
        if case .dBm(let value) = self { return value }
        return nil
    }

    /// Sort key for a strongest-first list. Unmeasured devices sort last, not first.
    public var sortKey: Int { dBmValue ?? Int.min }
}

// MARK: - Discovery policy

/// The tunable parts of a scan, in one place a reviewer can read in ten seconds.
public struct RingDiscoveryPolicy: Sendable, Equatable {

    /// Names accepted into the pairing list.
    public var matcher: RingNameMatcher

    /// How long a scan runs before it gives up and says so.
    ///
    /// THIS FIELD IS THE FIX FOR A SPECIFIC SHIPPED BUG. Without a deadline, a scan that finds
    /// nothing runs forever, an `isScanning` flag stays true forever, and any control gated on
    /// `!isScanning` is disabled forever — leaving force-quit as the user's only move. See
    /// `README.md`, root cause #3.
    public var deadline: TimeInterval

    /// Discoveries weaker than this are ignored. Deliberately generous.
    ///
    /// A ring is a small antenna worn on a finger; it is not a phone. The vendor SDK's own
    /// default gate is −85 dBm, which is tight enough to hide a ring resting on the desk next to
    /// the phone once a hand or a body is in the path. −100 admits essentially anything the
    /// radio can decode, and the user picks from a list sorted by strength.
    public var minimumSignal: Int

    /// How long to wait for the radio to reach `poweredOn` before failing.
    ///
    /// `CBCentralManager` reaches `poweredOn` a run loop or two after creation. Scanning before
    /// then is not an error — it is silently ignored, which is the single most common cause of
    /// "searching, nothing shows up". We wait, and if the radio never arrives we fail loudly.
    public var radioWarmUp: TimeInterval

    public init(
        matcher: RingNameMatcher = .standard,
        deadline: TimeInterval = 15,
        minimumSignal: Int = -100,
        radioWarmUp: TimeInterval = 8
    ) {
        self.matcher = matcher
        self.deadline = deadline
        self.minimumSignal = minimumSignal
        self.radioWarmUp = radioWarmUp
    }

    public static let standard = RingDiscoveryPolicy()

    /// Everything with a name, no signal floor, longer window — for a diagnostics screen.
    public static let diagnostic = RingDiscoveryPolicy(
        matcher: .permissive,
        deadline: 30,
        minimumSignal: -127
    )

    /// True when a signal passes the floor. Unreported strength is admitted: the absence of a
    /// measurement is not evidence of a weak one, and dropping it would hide a present device.
    public func admits(_ signal: RingSignal) -> Bool {
        guard let dBm = signal.dBmValue else { return true }
        return dBm >= minimumSignal
    }
}
