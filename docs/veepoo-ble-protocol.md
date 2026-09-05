# Reading the CarePlix ring's raw data without the vendor SDK

*How the ring's Bluetooth protocol works, where the "restricted" gate actually
sits, and how to read every sleep-apnea signal ourselves. Derived by
decompiling the vendor's own Android protocol library; a runnable codec and its
tests live in [`tools/veepoo-protocol`](../tools/veepoo-protocol).*

## The one-paragraph answer

The ring speaks a single, un-encrypted BLE frame protocol. The nightly SpO₂
record it sends already contains apnea count, hypoxia time, hypopnea, cardiac
load, HRV and respiration rate in bytes 9-19 of each frame. The "restricted
function" wording in the iOS docs is **not** the firmware withholding data — it
is the vendor SDK choosing not to expose those bytes unless the ring's device
number is on a server-side licence list. If we parse the frames ourselves, the
gate does not apply. This is the same on iOS and Android because both SDKs are
just clients for the same firmware protocol; the frame layouts in the codec were
taken from the Android library and are byte-for-byte what the iOS app must send
and parse.

**This is interoperability work on an Apache-2.0 library** (`vpprotocol`, from
`github.com/HBandSDK/Android_Ble_SDK`), not a circumvention of encryption or
authentication. There is none to circumvent: the link "password" is a 4-digit
handshake that defaults to `0000` and the SDK auto-sends.

## Where the gate is, exactly

Decompiling `com.veepoo.protocol` shows the pipeline for the nightly oxygen
record:

1. `readOriginData(...)` sends command `0xD2` and the ring streams one
   20-byte notification per minute.
2. The frame carries **all** fields at fixed offsets (see below).
3. But `readOriginDataBySetting` first calls
   `FunctionCheckUtil.isReturnAllSpo2hData()`. That method:
   - reads a cached server response for the ring's device number,
   - if the licence string's field is not `"1"`, or the licence has expired,
     returns `false`,
   - and only when it returns `true` does the parser (`vp_ck.vp_c`) read bytes
     9-19. Otherwise it uses `vp_ck.vp_b`, which reads **only** the SpO₂ value
     at byte 8.

So a stock integration on an unlicensed device number gets SpO₂ and nothing
else. The bytes are on the wire regardless. `FunctionCheckUtil` also drives a
"This feature is not supported" toast; there is no cryptographic check, no
signed payload, no server round-trip required to *read* the bytes — only to make
the SDK's own parser reveal them.

The same pattern gates the Lorentz/HRV scatter helper
(`checkLorentz` → device-number list) and a few UI conveniences. None of it
touches what the ring transmits.

## The transport

| | |
|---|---|
| Command service | `F0080001-0451-4000-B000-000000000000` |
| Notify characteristic | `F0080002-…` (subscribe here for all command replies) |
| Write characteristic | `F0080003-…` (write 20-byte command frames here) |
| Raw optical channel | service `F0020001-…`, notify `F0020002-…` ("ADC") |
| Advertised scan hint | `0000fee7-0000-1000-8000-00805f9b34fb` |

Every command frame is 20 bytes: `[opcode][args…][zero padding]`. Every reply
starts with the same opcode. Multi-record reads (a night of SpO₂, a day of
five-minute blocks) stream many notifications, each carrying a
`current packet / total packets` counter; the read is done when
current == total, or total == 0.

MTU: request ~247 so the firmware can pack full frames; it falls back to 20-byte
ATT payloads otherwise.

### Connect sequence

1. Scan (open scan, match the advertised `LOOP-XXXX` name — the vendor scan is
   service-UUID filtered and misses the ring; this is the same bug already
   documented in `ios/RingDiscovery`).
2. Subscribe to the notify characteristic.
3. Write `0xA1` with password `0000` and the current time (see
   `build_password`). The ring replies `0xA1` with status, **device number**,
   and firmware version. Status 1 or 6 means paired.
4. The ring pushes five `0xA7` capability packets (packet id in byte 19). Parse
   packets 1 and 2 for the flags that matter (SpO₂ type, HRV type, protocol
   version, sleep tag, watch-days).
5. Now issue read commands.

The device number from step 3 is what the vendor licence check keys on. We read
it for capability logic (e.g. protocol version) but never gate on it.

## The sleep-apnea signals, frame by frame

Byte offsets below are exact, from the decompiled parsers. The codec implements
all of them.

### Nightly SpO₂ / apnea record — command `0xD2`

One notification per minute. Valid window is 00:00-07:00 on stock firmware
(algorithm limit; a custom "all-day" toggle exists, `0x?? veepooSDKSettingAllDayOxygenTest`).

| Byte | Field |
|---|---|
| 0 | `0xD2` |
| 1-2 | current packet (LE) |
| 3-4 | total packets (LE) |
| 5 | days ago (0 today, 1 yesterday…) |
| 6 | hour |
| 7 | minute |
| 8 | **SpO₂ %** (the only field stock SDK returns unlicensed) |
| 9 | **apnea result** (0 none / 1 present; vendor also calls it "number of apneas") |
| 10 | **is-hypoxia** |
| 11 | **hypoxia time** |
| 12 | **hypopnea** |
| 13 | **cardiac load** |
| 14 | **HRV** |
| 15 | sport (motion intensity) |
| 16 | heart rate |
| 17 | steps |
| 18 | **respiration rate** (255 = invalid) |
| 19 | correction / "Temp1" |

This single record is the backbone of an apnea analysis: desaturation curve,
pulse, respiration, movement, and the firmware's own per-minute apnea and
hypoxia flags on one minute grid.

### Per-minute HRV with RR list — command `0xD9`

One notification per minute: bytes 6-7 time, byte 8 HRV, **bytes 9-18 = ten RR
values, each ×10 = one RR interval in ms**, byte 19 valid-count. Concatenate all
minutes for a Poincaré/Lorentz plot or an HRV-based apnea classifier.

### Beat-to-beat RR blocks — command `0x70`

Higher fidelity than `0xD9`: one block per minute, 1440 blocks a day, the ring
keeps **3 days**. Header packet carries a full timestamp and a sample count;
data packets carry the raw stream (one byte per beat, unit ≈ 20 ms — the vendor
demo converts with `60000 / (v·20)` bpm). Read incrementally by block number to
avoid re-pulling. `RRAssembler` in the codec stitches the packets.

### Five-minute "origin" TLV blocks — command `0xDF` (protocol 3/5)

The richest record. Each five-minute block is a run of tag-length-value fields
(tags `0xB1`-`0xC6`). The apnea-relevant tags:

| Tag | Field |
|---|---|
| `0xB1` | time (bytes 2,3 = hour,minute; 0,1 must be non-zero or the block is treated as empty) |
| `0xB4` | five per-minute pulse rates (green PPG) |
| `0xB6` | five per-minute respiration rates |
| `0xB7` | HRV: type byte + 50 RR values (10 per minute, ×10 ms) |
| `0xB9` | SpO₂ minute block: 5 SpO₂, 5 apnea-count, 5 apnea-result, 5 hypoxia-time, 5 cardiac-load, 5 correction |
| `0xC3` | skin & body temperature (÷10 °C, valid 12.0-48.0) |
| `0xB2` | steps/sport/distance/kcal/pose/**wear** |

`DFAssembler` reassembles the fragmented packets and `parse_five_minute_block`
splits the TLV. Whether the ring uses `0xDF` (protocol 3/5) or the legacy
`0xD1` layout is told by `origin_protocol_version` in the `0xA7` capabilities.

### Raw optical + accelerometer — PPG channel

The real physiological signal, if the firmware is a JH58/G08W-class build:

- **Spot-test green light**: start an SpO₂ test (`0x80` on the command channel)
  and the ring streams `0x82` frames on the PPG channel — five 24-bit green
  samples each.
- **JH58 stored / real-time**: `0xEB` commands enable 100 Hz green PPG + 50 Hz
  3-axis accelerometer, either buffered (10 s per 15 min, or 1 min per 5 min) or
  streamed live per second. Green frames are `0x80` (20-bit signed, 3 bytes per
  sample), accelerometer frames are `0x89` (int16 LE x/y/z).

`parse_ppg_frame` decodes all of these. **Whether the CarePlix ring answers the
JH58 commands is the one thing that cannot be known without the hardware** — it
depends on the firmware build.

## Porting to iOS (the actual target)

The iOS app already has a working discovery + connect layer
(`ios/RingDiscovery`, which bypasses the vendor's filtered scan). Add a raw
data path beside it:

1. After `RingLink` reaches `verified`, discover the command service and
   subscribe to `F0080002-…`.
2. Translate `veepoo_protocol.py` to Swift — it is deliberately dependency-free
   and every function is a pure byte transform, so it is a mechanical port. Keep
   the same function names so the two stay in sync.
3. Drive the read state machine: send `0xD2`, collect notifications into
   `OxygenMinute` records until `day_read_complete`, repeat for `0xD9`, `0x70`,
   `0xDF`.
4. You do **not** need `veepoo_read_all` orchestration from the SDK; issue the
   reads directly. You also do not need `FunctionCheckUtil` — that is the gate,
   and skipping it is the entire point.

Because the frames are identical across platforms, a capture taken on Android
validates the iOS parser and vice-versa.

## Validate on hardware before trusting a single byte

The codec is self-consistent and unit-tested, but the offsets are read from a
decompiler, not confirmed against your ring. Do one capture first:

1. On an Android phone, enable **HCI snoop log** (Developer options → "Enable
   Bluetooth HCI snoop log"), pair the ring with the Veepoo demo app, run one
   nightly sync, pull `btsnoop_hci.log`.
2. Find the `0xD2` / `0xD9` / `0xDF` notifications and feed their bytes to the
   codec. If `OxygenMinute.spo2` and `.heart_rate` land in physiological ranges
   and timestamps march by one minute, the offsets are right.
3. Only field 9-19 semantics (apnea vs hypopnea units) need the vendor to
   confirm — the positions will already be proven.

Two open questions for the OEM remain, both about meaning not access:
- units of `hypoxia_time` and `cardiac_load`,
- exact definition of `apnea_result` (per-minute flag vs count).

## What this does and does not enable

- **Does**: read every sensor stream the ring records, on iOS, without a licence
  or the vendor's device-number allowlist, and run our own apnea scoring.
- **Does not**: change what the ring physically measures (PPG + accelerometer +
  thermistor), make the nightly SpO₂ window longer than the firmware allows
  without the custom command, or turn a wellness estimate into a diagnosis. Keep
  the labelling honest — "breathing disturbances", not "AHI".
