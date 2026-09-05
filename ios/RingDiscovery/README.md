# RingDiscovery

An app-owned BLE discovery layer for the CarePlix ring, and the root-cause analysis that produced it.

## Why this exists

The iOS ring app failed to find a ring ten builds in a row. Its diagnostics panel showed:

```
link: preflight ok
scan: configuring
scan: vendor reported 0, usable 0
launch
link: preflight ok
scan: configuring
```

`vendor reported 0` means the vendor SDK's scan callback delivered **zero** peripherals. Every
filter the app applies downstream of that is irrelevant — zero in, zero out. The failure is in the
scan itself, and it is not a tuning problem.

---

## Root cause #1 — the vendor SDK's scan is service-UUID filtered, and the ring almost certainly does not match

`veepooSDKStartScanDeviceAndReceiveScanningDevice:` does **not** perform an open scan. Disassembling
the shipping `VeepooBleSDK` binary (a thin arm64 `ar` archive; extract `VPBleCentralManage.o` and
resolve the string operands through the relocation tables) shows its private
`-[VPBleCentralManage startScanDevice]` ending in:

```objc
[self.centralManager scanForPeripheralsWithServices:@[FFFF, FEE7, 0001, 180D] options:nil]
```

That array is a **CoreBluetooth-level** filter. iOS never delivers a non-matching advertisement to
the SDK's `didDiscoverPeripheral:` at all. The two public knobs that look like they should help —
`manufacturerIDFilter` and `rrisLimit` — are applied *downstream* of it and cannot widen it. There
is no property that can.

**The trap that makes this hard to see:** iOS matches only service UUIDs present in the 31-byte
**advertisement payload** (AD types `0x02`/`0x03`/`0x06`/`0x07`) — *not* the GATT table. A ring can
expose `180D` in GATT and advertise no service UUIDs whatsoever. CarePlix rings are provisioned with
a Complete Local Name of the form `LOOP-XXXX` (see `tools/ring-provisioner`), and a name-carrying
advertisement frequently has no room left for a 128-bit service UUID inside 31 bytes.

So the ring is invisible to that scan — permanently, on every attempt, on every build.

**Fix:** the app owns discovery. `RingScanner` runs `scanForPeripherals(withServices: nil, …)` on
its own `CBCentralManager` and matches on the advertised name. The SDK still owns the link:
`RingLink` hands the resulting `CBPeripheral` to `veepooSDKSelfScanConnectDevice:`, which the vendor
header documents for exactly this case —

> `///自行实现扫描连接设备时使用，适合集成多家SDK场景，连接状态使用：VPBleConnectStateChangeBlock`
> `///不可与 veepooSDKConnectDevice:deviceConnectBlock: 混用`

("Use when you implement scanning and connecting yourself… **must not be mixed with**
`veepooSDKConnectDevice:`.")

## Root cause #2 — the SDK drops a scan requested before its own radio is ready, and never re-arms

`startScanDevice` gates its **entire body** on `self.centralManager.state == CBManagerStatePoweredOn`
and returns silently otherwise — never issuing the scan, and never arming its own 1-second retry
timer, which is created *after* that check. `centralManagerDidUpdateState:` restarts the scan on
`.poweredOn` **only when `getLastConnectDeviceMessage` is non-nil**, i.e. only when reconnecting to
an already-paired device. On a first-time pairing, a scan dropped this way is dead for the life of
the process.

This is almost certainly why `link: preflight ok` is immediately followed by nothing. A preflight
that checks `CBManager.authorization` and/or **the app's own** `CBCentralManager` is asking a
different object than the one that matters: the SDK's singleton is created later and reaches
`.poweredOn` a run loop or two after. The preflight is a true statement about the wrong radio.

**Never treat the app's own central as a proxy for the SDK's.**

**Fix:** `RingScanner` starts scanning from `centralManagerDidUpdateState` when the radio actually
arrives, and a warm-up timer turns a radio that *never* arrives into a loud, reported failure rather
than a spinner that runs forever.

## Root cause #3 — the restart was probably not a crash

The bare `launch` breadcrumb was read as a crash for ten builds. The trail does not support that.
Run 1 ended on `scan: vendor reported 0, usable 0` — an orderly end-of-scan-window summary, with no
work in flight. Crashes happen in the middle of work, not after a summary line.

The screenshot shows the real mechanism. The **"Search for ring" button was disabled** while the
spinner ran. If `isScanning` is set true when a scan starts and cleared only when the scan's stream
finishes, and the scan has no deadline, then a scan that finds nothing never finishes, `isScanning`
is never cleared, and every control gated on `!isScanning` stays disabled for the life of the
process. Force-quitting is the only move the user has left — and that produces `launch`, with no
crash report.

Corroborating evidence in the same screenshot: a spinner (*"Looking for your ring"*) and an error
(*"Could not reach your ring. Try again."*) were displayed **at the same time**. Those are two
variables where there should be one state machine.

**Check this before anything else** (60 seconds, no build): Xcode Organizer → Crashes, or on the
device, Settings → Privacy & Security → Analytics & Improvements → Analytics Data. **If there is no
crash report, the entire process-death line of inquiry is dead** and all effort belongs on "why
zero".

**Fix:** `RingDiscoveryPolicy.deadline` (15 s default) bounds every scan; `RingDiscoveryPhase` is a
single enum so a spinner and an error cannot coexist; and `RingPairingModel.retry()` is **never**
gated on `isScanning` — `RingScanner` is single-flight, so a second tap is always safe.

## Ruled out — do not spend attempt 11 here

- **Location permission.** The Veepoo binary contains no `CLLocationManager` reference at all
  (`strings` returns zero for it, while `CBCentralManager` and `CBUUID` *are* present, so that is
  real absence rather than a blind method). iOS BLE scanning has never required Location. Do not add
  `NSLocationAlwaysAndWhenInUseUsageDescription` — it causes iOS to post recurring background-location
  notifications and buys nothing.
- **Entitlements.** No entitlement gates CoreBluetooth central scanning; it is TCC-only, plus
  `UIBackgroundModes` for background operation.
- **Framework embedding / signing / armv7 slices.** Load-time properties. The trail shows two full
  process lifetimes reaching the app's own UI, so dyld resolved the graph twice.

## Still worth checking in the ring app (cheap, and each is a real failure mode)

| Check | Why |
|---|---|
| `NSBluetoothAlwaysUsageDescription` in the ring target's `Info.plist` | Its absence terminates the process on first `CBCentralManager` use. `NSBluetoothPeripheralUsageDescription` is the deprecated iOS-12 key and does **not** substitute on iOS 13+. Verify against the shipped build: `plutil -p Payload/<Ring>.app/Info.plist \| grep -i bluetooth` |
| `-ObjC` in `OTHER_LDFLAGS`, **both** Debug and Release | Without it, ObjC classes and categories in a *static* archive can be dead-stripped, failing at first use as a nil class — which would land right after `scan: configuring` |
| A `#if DEBUG` mock or fallback scanner | Compiled out of TestFlight builds; the classic "works on my device" |
| Whether the scan path waits on `sharedBleManager()?.centralManager?.state` | Root cause #2 |

## The bench check that settles #1 outright

Nothing in this repository proves what the ring actually advertises. **Sixty seconds with nRF
Connect or LightBlue next to a powered ring** settles it, with no build and no source. Record:

1. Complete/Shortened Local Name (AD `0x09`/`0x08`)
2. **The service-UUID list in the ADVERTISEMENT** — not the GATT table
3. Presence, length and first two bytes of manufacturer data (AD `0xFF`)
4. RSSI at 30 cm
5. Whether it advertises continuously, or only briefly after coming off the charger

If that UUID list contains none of `FFFF` / `FEE7` / `0001` / `180D`, root cause #1 is confirmed and
no amount of CoreBluetooth state-fixing would ever have worked.

Point 5 matters independently: a ring that advertises only for a short window after being taken off
the charger produces `vendor reported 0` for a reason no iOS code can fix. The pairing copy already
says *"Take it off the charger and keep it close"*, which suggests someone suspected this — but
nothing here confirms the ring's advertising duty cycle.

---

## Using it

```swift
@StateObject private var model = RingPairingModel(link: VeepooRingLink.shared)

var body: some View {
    RingPairingScreen(model: model)
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
        .onChange(of: scenePhase) { if $0 == .active { model.onForeground() } }
}
```

Render exactly one thing per `model.phase`:

| Phase | UI |
|---|---|
| `.searching` | Spinner. **No error text, no disabled retry.** |
| `.found` | The list, strongest signal first |
| `.foundNothing` | "No ring found" + an **enabled** retry |
| `.blocked(state)` | The specific problem + Settings deep link or "turn Bluetooth on" |
| `.connecting` | Spinner |
| `.paired` | Success |
| `.connectionFailed(state)` | Specific copy per state; `.needsPasscode` is a prompt, not an error |

For a "why can't the app see my ring" screen, pass `RingDiscoveryPolicy.diagnostic` — permissive
matcher, no signal floor, 30-second window. Note that `RingScanner` logs **every** advertisement it
receives before any filtering, under subsystem `com.careplix.ring`, so the console answers "did the
radio see anything at all" directly.

## Integration constraints that are easy to violate

1. **Never mix `veepooSDKSelfScanConnectDevice:` with `veepooSDKConnectDevice:`.** Pick one path for
   the whole app; the header forbids mixing them. A single surviving call on a reconnect or settings
   path is enough.
2. **You maintain `deviceShowConfirm` yourself** in self-scan mode — the SDK only manages it when it
   did its own scanning. `true` on first pairing, `false` on reconnect.
3. **Register the persistent `vpBleConnectStateChangeBlock`.** The per-attempt callback goes quiet
   once an attempt resolves, so involuntary disconnects (out of range, ring off, backgrounded) are
   reported *only* there. Raw `0` on that enum is the disconnect signal, and it has no equivalent on
   the per-attempt enum.
4. **`verifyPasswordSuccess`, not `connected`, means paired.** The 4-digit code is the SDK's
   link-layer handshake, not a user credential; it defaults to `0000` and the SDK auto-sends it.
5. **Prove the link with a round-trip**, never a cached flag. A state variable saying "connected" is
   a memory of something that was true once.

---

## Build status — read this before trusting anything above

**No Swift in this module has been compiled.** It was written in a Linux CI container with no Swift
toolchain and no Xcode, so `swift build` and `swift test` have not been run, and the unit tests in
`Tests/` have never executed. Build it locally before use:

```bash
cd ios/RingDiscovery
swift build && swift test          # the vendor SDK is not required; RingLink compiles out
```

`RingLink`'s Veepoo implementation is behind `#if canImport(VeepooBleSDK)`, so the package builds
and its tests run without the vendor framework present — but that also means **the vendor-facing
code path is the part least protected by these tests.** Compile it inside the ring app, against the
real framework, before relying on it.

What *is* established independently of any build: the disassembly findings in root causes #1 and #2,
which came from the shipping binary and were reproduced by several independent passes, and root
cause #3, which is visible in the screenshot itself.
