# Ring Provisioner

Android tool for renaming a CarePlix ring's BLE name to **LOOP**.

Scan the QR/barcode on the ring's label (or type the MAC), and the app connects over BLE,
inspects what the firmware exposes, writes the new name, and then re-scans to verify the ring
actually advertises it.

## Status: the app is complete, the rename path is not confirmed

The scan → match → connect → inspect → write → verify pipeline is implemented and the
Android-independent logic is unit tested. What is **not** settled is whether the ring firmware
supports being renamed at all.

There is no portable way to rename a BLE peripheral. Three possibilities:

| Path | Mechanism | Status here |
| --- | --- | --- |
| **A** | Write the GAP Device Name characteristic `0x2A00` | Implemented (`GapNameStrategy`). The BLE spec *permits* this to be writable; most OEM firmware ships it read-only. |
| **B** | Vendor opcode over a proprietary service | Implemented as a parameterised strategy (`VendorFrameStrategy`), but the CarePlix ring's opcode is unknown to this project. |
| **C** | Not exposed — vendor factory tool or signed OTA only | No app can do it. The ask has to go to the OEM. |

Run **Run diagnostics** against a real ring first. It dumps the full GATT table and reports
whether `0x2A00` is writable, which decides between A, B, and C in about a minute — and it only
reads, so it is safe to point at production hardware.

### Two traps that make a "successful" rename a lie

1. **A write returning `GATT_SUCCESS` proves nothing.** Firmware can accept a write to `0x2A00`
   and keep advertising the old name. The name a phone shows in its Bluetooth picker comes from
   the advertisement payload (`Complete Local Name`, AD type `0x09`), not from the
   characteristic. `RingProvisioner.rename` therefore disconnects and re-scans, and reports
   `verified = false` if the advertised name did not change.
2. **Persistence across reboot is a separate question.** If the firmware does not commit the new
   name to NVS, it reverts on power cycle — useless for provisioning. The app cannot check this
   for you: **power cycle the ring and re-scan before signing off on a batch.**

## Why Android

iOS is not a practical target for this tool. CoreBluetooth never exposes a peripheral's MAC
address — it gives an opaque `CBPeripheral.identifier` that differs on every phone. Since the
production QR encodes a MAC, there is no way to map a scanned code to a peripheral on iOS. You
would have to connect to every candidate and read its serial, which is slow and depends on the
serial being exposed at all.

Android hands back the real MAC, so the match is exact and pushed down into the Bluetooth
controller via `ScanFilter.setDeviceAddress()` — on a line with dozens of rings advertising, the
wrong one cannot be provisioned by accident.

## Naming

Default is `LOOP-<last 4 hex of MAC>`, e.g. `LOOP-E5FF`. Naming every unit the bare string
`LOOP` makes them indistinguishable in a Bluetooth picker and in support logs. The suffix can
be switched off in the UI if the spec really does demand a bare `LOOP`.

Names are clamped to 20 bytes. A BLE advertisement is 31 bytes total, shared between the name
and every other AD structure; an over-long name gets silently truncated or pushes other data
out. Truncation is done on a UTF-8 character boundary so a multi-byte character can never be
split into an invalid sequence.

## Build

```bash
cd tools/ring-provisioner
./gradlew assembleDebug
```

Requires the Android SDK (compileSdk 35). minSdk is 26.

> The CI container this was developed in cannot reach `dl.google.com`, so the Android SDK could
> not be installed and **`assembleDebug` has not been run**. The Android-free logic — MAC/serial
> parsing, name construction and clamping, command-frame encoding — was compiled and tested on
> the JVM (27 tests, all passing). The Android-dependent code is unverified by compilation and
> should be built locally before use.

Run the unit tests:

```bash
./gradlew test
```

## Layout

```
app/src/main/java/com/careplix/ringprovisioner/
├── MainActivity.kt              Permission gating, scanner ⇄ provision routing
├── ProvisionViewModel.kt        UI state, orchestration entry points
├── ble/
│   ├── DeviceId.kt              Parses scanned/typed IDs → MAC or serial
│   ├── RingNaming.kt            LOOP-XXXX construction, 31-byte ADV budget
│   ├── BleUuids.kt              SIG UUIDs + vendor-service candidates
│   ├── BleScanner.kt            Scan flow, MAC-filtered discovery
│   ├── BleGattClient.kt         Coroutine GATT wrapper, one op at a time
│   ├── GattSnapshot.kt          Flattened GATT table + shareable report
│   ├── RingProvisioner.kt       connect → inspect → rename → verify
│   └── rename/
│       ├── RenameStrategy.kt    Strategy interface + RenameOutcome
│       ├── GapNameStrategy.kt   Path A: 0x2A00 write
│       ├── VendorFrameStrategy.kt  Path B: parameterised vendor command
│       ├── CommandFrame.kt      Frame encoding (pure, unit tested)
│       └── VendorPresets.kt     Speculative presets — see the warning in the file
└── ui/
    ├── ProvisionScreen.kt       Input, actions, log, GATT report
    └── BarcodeScannerScreen.kt  CameraX + ML Kit, QR/DataMatrix/Code128/39/EAN-13
```

`BleGattClient` serialises every operation behind a mutex. The Android GATT stack allows one
outstanding operation per connection; issuing a second read or write before the previous
callback fires does not raise an error, it just drops the request and hangs the caller. Every
operation is also individually timed out so an unresponsive ring surfaces as a failure rather
than a frozen screen.

## Adding the real rename command

Once the ring's command set is known:

1. Add a `VendorFrameStrategy` entry to `VendorPresets` with the real service UUID,
   characteristic UUID, opcode, and framing.
2. Add it to the `strategies` list in `ProvisionViewModel`.
3. Delete the speculative presets — they are placeholder shapes, not documented commands.

If none of the three framings match, add a case to `Framing` and `CommandFrame.build`, and
cover it in `CommandFrameTest`.

## Questions for the ring OEM

Worth sending verbatim; the answers determine whether this tool can work at all.

1. Is GAP Device Name (`0x2A00`) writable, or read-only?
2. If there is a proprietary "set device name" command: which service and characteristic UUID,
   what opcode, what frame layout, and is there a response/ACK?
3. Does a renamed device update its **advertisement payload**, or only the GAP characteristic?
4. Does the new name persist across a power cycle? Is it stored in NVS?
5. What is the maximum accepted name length, in bytes?
6. Does renaming require unlocking, pairing, bonding, or an authentication handshake first?
7. Is renaming reversible, and is there a factory-reset command?
