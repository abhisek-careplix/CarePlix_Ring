//
//  RingLink.swift
//  RingDiscovery
//
//  Connecting to a ring the app discovered itself: the link STATE and the link ABSTRACTION.
//
//  The vendor implementation (`VeepooRingLink`) is not in this package. A SwiftPM target cannot
//  see an app's framework search paths, so it lives in the app target
//  (ios/RingApp/CarePlixRing/Vendor/VeepooRingLink.swift) behind the `VEEPOO` compile flag.
//  This file stays vendor-free so the pairing model builds and tests anywhere.
//
//  THE DIVISION OF LABOUR
//  ----------------------
//  The app owns DISCOVERY (`RingScanner`); the vendor SDK owns the LINK. That split is not a
//  preference, it is what the SDK's own header prescribes for this situation:
//
//      ///自行实现扫描连接设备时使用，适合集成多家SDK场景，连接状态使用：VPBleConnectStateChangeBlock
//      ///不可与 veepooSDKConnectDevice:deviceConnectBlock: 混用
//      - (void)veepooSDKSelfScanConnectDevice:(CBPeripheral *)peripheral
//                          deviceConnectBlock:(DeviceConnectBlock)connectBlock;
//
//  "Use when you implement scanning and connecting yourself, suited to integrating several SDKs.
//   For connection state use VPBleConnectStateChangeBlock. MUST NOT be mixed with
//   veepooSDKConnectDevice:deviceConnectBlock:."
//
//  Three obligations follow from that header, and each one is a real bug if missed:
//
//  1. NEVER MIX THE TWO CONNECT PATHS. Pick `veepooSDKSelfScanConnectDevice:` for the whole app.
//     A single surviving call to `veepooSDKConnectDevice:` — a reconnect path, a settings screen —
//     puts the SDK into a state the header explicitly forbids.
//
//  2. YOU MAINTAIN `deviceShowConfirm`. The SDK sets it automatically only when it did its own
//     scanning. In self-scan mode it is yours: YES for a first pairing (the ring asks the wearer to
//     confirm), NO for a reconnect (a silent reconnect must never demand a gesture).
//
//  3. AUTHORITATIVE STATE ARRIVES ON THE PERSISTENT BLOCK, not the per-attempt one. The
//     per-attempt callback goes quiet once an attempt resolves, so an involuntary disconnect —
//     out of range, ring powered off, backgrounded — is reported only by
//     `vpBleConnectStateChangeBlock`. Without it, state latches at "connected" forever.
//

import Foundation

// MARK: - Link state

/// Every state the link can be in, modelled explicitly.
///
/// There is deliberately no `unknown` case and no `default:` branch anywhere that switches over
/// this. An unmodelled vendor state must be a loud, named failure — a silent one strands the user
/// on a spinner, which is the single most common way a pairing flow dies.
public enum RingLinkState: Sendable, Equatable {
    case connecting
    /// A BLE connection exists. NOT yet a paired ring — the handshake has not happened.
    case connected
    /// The handshake succeeded. THIS is "paired".
    case verified
    /// The ring carries a non-default code; the user must supply it. Not an error.
    case needsPasscode
    /// The ring is waiting for the wearer to confirm on the device itself.
    case awaitingConfirmationOnRing
    case timedOut
    case disconnected
    case radioOff
    /// The SDK reported a value this app does not model. Carries the raw value, so the console
    /// tells you what to add rather than leaving you to guess.
    case unmodelled(Int)

    public var isTerminal: Bool {
        switch self {
        case .verified, .timedOut, .disconnected, .radioOff, .unmodelled:
            return true
        case .connecting, .connected, .needsPasscode, .awaitingConfirmationOnRing:
            return false
        }
    }

    public var isFailure: Bool {
        switch self {
        case .timedOut, .disconnected, .radioOff, .unmodelled:
            return true
        case .connecting, .connected, .verified, .needsPasscode, .awaitingConfirmationOnRing:
            return false
        }
    }
}

/// Maps the vendor's persistent connection enum onto ``RingLinkState``.
///
/// `VPDeviceConnectState` (VPPublicDefine.h):
///
///     DisConnect = 0, Connecting = 1, Connect = 2, VerifyPasswordSuccess = 3,
///     VerifyPasswordFailure = 4, DiscoverNewUpdateFirm = 5, Timeout = 6, ConfirmTimeout = 7
///
/// Raw 0 is the involuntary-disconnect signal, and it exists ONLY on this persistent enum — the
/// per-attempt enum has no equivalent, which is why a link that dies out of range reports nothing
/// unless the persistent block is registered.
///
/// Raw 5 is firmware discovery, not a link state: it is deliberately mapped to `nil` (ignore)
/// rather than to a state, because emitting it would move a pairing flow off its current stage.
public func ringLinkState(fromVendorRawValue raw: Int) -> RingLinkState? {
    switch raw {
    case 0: return .disconnected
    case 1: return .connecting
    case 2: return .connected
    case 3: return .verified
    case 4: return .needsPasscode
    case 5: return nil                      // DiscoverNewUpdateFirm — not a link state
    case 6: return .timedOut
    case 7: return .awaitingConfirmationOnRing
    default: return .unmodelled(raw)
    }
}

// MARK: - Abstraction

#if canImport(CoreBluetooth)

/// What the pairing flow needs from a link, with no vendor SDK in the signature.
///
/// The pairing model depends on this and not on `VeepooBleSDK`, so it builds and is testable on a
/// machine that has never seen the vendor framework.
public protocol RingLinking: AnyObject, Sendable {
    /// Prepares the vendor stack. Call once, on entering the pairing screen — before the user asks
    /// to scan — so the SDK's lazily-created singleton and its own `CBCentralManager` have settled
    /// by the time a connection is attempted.
    func prepare()

    /// Connects, streaming every transition until a terminal one.
    ///
    /// A stream and not a single `async` result because one attempt legitimately reports
    /// connecting → connected → verified, and the UI should show each step.
    func connect(to candidate: RingCandidate, isFirstPairing: Bool) -> AsyncStream<RingLinkState>

    /// Explicit, user-initiated disconnect. No auto-reconnect afterwards.
    func disconnect()
}

#endif
