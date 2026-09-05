//
//  VeepooRingLink.swift
//  CarePlix Ring
//
//  The Veepoo implementation of `RingLinking` (RingDiscovery). Compiled only with `VEEPOO`, in
//  the app target, because a package target cannot see the vendor framework — see
//  VeepooRingDataSource.swift for the reasoning.
//
//  THE DIVISION OF LABOUR
//  The app owns DISCOVERY (`RingScanner`); the vendor SDK owns the LINK, through the one entry
//  point its header prescribes for self-scanned peripherals:
//
//      ///自行实现扫描连接设备时使用，适合集成多家SDK场景，连接状态使用：VPBleConnectStateChangeBlock
//      ///不可与 veepooSDKConnectDevice:deviceConnectBlock: 混用
//      - (void)veepooSDKSelfScanConnectDevice:(CBPeripheral *)peripheral
//                          deviceConnectBlock:(DeviceConnectBlock)connectBlock;
//
//  Three obligations follow, and each one is a real bug if missed:
//  1. NEVER MIX THE TWO CONNECT PATHS. `veepooSDKSelfScanConnectDevice:` for the whole app.
//  2. YOU MAINTAIN `deviceShowConfirm`: YES on first pairing, NO on a silent reconnect.
//  3. AUTHORITATIVE STATE ARRIVES ON THE PERSISTENT BLOCK (`vpBleConnectStateChangeBlock`); the
//     per-attempt block goes quiet once an attempt resolves.
//

#if VEEPOO
import Foundation
import CoreBluetooth
import VeepooBleSDK
import RingDiscovery
import os

// MARK: - Veepoo implementation


public final class VeepooRingLink: RingLinking, @unchecked Sendable {

    public static let shared = VeepooRingLink()

    private let log = Logger(subsystem: "com.careplix.ring", category: "RingLink")
    private let observerLock = NSLock()
    private var persistentObserversRegistered = false

    /// Broadcasts state from the persistent observers, which outlive any one connect attempt.
    private let stateLock = NSLock()
    private var stateListeners: [UUID: @Sendable (RingLinkState) -> Void] = [:]

    public init() {}

    // MARK: Preparation

    public func prepare() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let manager = VPBleCentralManage.sharedBleManager() else {
                self?.log.error("SDK manager unavailable during prepare()")
                return
            }
            self.suppressSystemPairingPrompts(manager)
            self.registerPersistentObservers(manager)
        }
    }

    /// Both of these default to YES in the SDK.
    ///
    /// Left alone, every connect — including the silent reconnect that runs on launch and on every
    /// foreground — re-raises iOS's classic-Bluetooth accessory dialog. Pairing the classic side
    /// for calls and notifications is a deliberate step the user takes from settings; a background
    /// reconnect must never interrupt anyone with a system modal.
    private func suppressSystemPairingPrompts(_ manager: VPBleCentralManage) {
        manager.isAutoShowPair = false
        manager.isAutoConnectBT = false
    }

    /// Registers the SDK's PERSISTENT state blocks. Idempotent.
    ///
    /// These are plain properties on the manager, not scoped to one connect attempt — see
    /// obligation 3 in the file header.
    private func registerPersistentObservers(_ manager: VPBleCentralManage) {
        observerLock.lock()
        let already = persistentObserversRegistered
        if !already { persistentObserversRegistered = true }
        observerLock.unlock()
        guard !already else { return }

        manager.vpBleConnectStateChangeBlock = { [weak self] vpState in
            guard let self else { return }
            self.log.info("persistent link cb raw=\(vpState.rawValue, privacy: .public)")
            guard let state = ringLinkState(fromVendorRawValue: Int(vpState.rawValue)) else { return }
            if case .unmodelled(let raw) = state {
                self.log.error("unmodelled VPDeviceConnectState raw=\(raw, privacy: .public)")
            }
            self.broadcast(state)
        }

        manager.vpBleCentralManageChangeBlock = { [weak self] radioState in
            guard let self else { return }
            // PoweredOff = 4. PoweredOn = 5 says nothing about the RING, only about the phone, so
            // it is deliberately not translated into a link state.
            if radioState.rawValue == 4 { self.broadcast(.radioOff) }
        }
    }

    private func broadcast(_ state: RingLinkState) {
        stateLock.lock()
        let listeners = stateListeners.values
        stateLock.unlock()
        for listener in listeners { listener(state) }
    }

    private func addListener(_ listener: @escaping @Sendable (RingLinkState) -> Void) -> UUID {
        let token = UUID()
        stateLock.lock()
        stateListeners[token] = listener
        stateLock.unlock()
        return token
    }

    private func removeListener(_ token: UUID) {
        stateLock.lock()
        stateListeners[token] = nil
        stateLock.unlock()
    }

    // MARK: Connecting

    public func connect(to candidate: RingCandidate, isFirstPairing: Bool) -> AsyncStream<RingLinkState> {
        AsyncStream(RingLinkState.self, bufferingPolicy: .unbounded) { continuation in

            let token = self.addListener { state in
                continuation.yield(state)
                if state.isTerminal { continuation.finish() }
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeListener(token)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { continuation.finish(); return }
                guard let manager = VPBleCentralManage.sharedBleManager() else {
                    self.log.error("connect aborted: SDK manager unavailable")
                    continuation.yield(.disconnected)
                    continuation.finish()
                    return
                }

                self.suppressSystemPairingPrompts(manager)
                self.registerPersistentObservers(manager)

                // Obligation 2: in self-scan mode this property is ours to maintain.
                manager.deviceShowConfirm = isFirstPairing

                continuation.yield(.connecting)

                manager.veepooSDKSelfScanConnectDevice(candidate.peripheral) { [weak self] rawState in
                    guard let self else { return }
                    // The per-attempt block. Logged for diagnosis; the persistent block above is
                    // what actually drives the stream, so a value arriving on both is harmless.
                    self.log.info("connect cb raw=\(rawState.rawValue, privacy: .public)")
                }
            }
        }
    }

    public func disconnect() {
        DispatchQueue.main.async {
            VPBleCentralManage.sharedBleManager()?.veepooSDKDisconnectDevice()
        }
        broadcast(.disconnected)
    }

    // MARK: Link verification

    /// Proves the link with a real round-trip rather than a cached flag.
    ///
    /// A state variable that says "connected" is a memory of something that was true once. After a
    /// backgrounding, a range excursion, or a ring reboot it is frequently a lie, and every screen
    /// downstream inherits it. The only honest test is to ask the ring something and get an answer.
    ///
    /// `peripheralManage` is non-nil only after the SDK's handshake completes, so it is a necessary
    /// condition — but not a sufficient one, which is why callers should follow it with a real read
    /// (battery is the cheapest) under a short timeout.
    public var handshakeCompleted: Bool {
        VPBleCentralManage.sharedBleManager()?.peripheralManage != nil
    }
}
#endif
