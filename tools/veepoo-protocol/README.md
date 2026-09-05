# veepoo-protocol

A dependency-free reference codec for the CarePlix ring's Bluetooth protocol, so
the app can read the ring's raw sensor records itself instead of relying on the
vendor SDK (whose parser withholds the sleep-apnea fields on unlicensed device
numbers).

- `veepoo_protocol.py` — the codec: command builders and frame parsers for the
  handshake, capabilities, nightly SpO₂/apnea record, per-minute HRV, beat-to-beat
  RR blocks, five-minute TLV blocks, spot tests, and the raw PPG/accelerometer
  channel. Standard library only.
- `test_veepoo_protocol.py` — round-trip tests (17, all passing).

```bash
python3 test_veepoo_protocol.py        # or: python3 -m pytest
```

## Where it comes from

Every byte offset was taken from the vendor's own **Apache-2.0** Android
protocol library (`vpprotocol-2.3.81.15.aar`, from
`github.com/HBandSDK/Android_Ble_SDK`) and cross-checked against the iOS SDK
headers. The frame layouts are identical on iOS and Android because the ring
firmware speaks one protocol; port this file to Swift for the iOS app.

## Status

Self-consistent and unit-tested, **not yet validated against a physical ring.**
The tests prove the parsers and multi-packet assemblers are internally correct,
not that the offsets match your hardware. Take one Android HCI snoop capture and
confirm the `0xD2`/`0xD9`/`0xDF` records decode into physiological values before
building on it — see [`docs/veepoo-ble-protocol.md`](../../docs/veepoo-ble-protocol.md),
section "Validate on hardware".

## Scope

This is interoperability with a licensed library. It does not defeat encryption
or authentication (there is none — the link "password" defaults to `0000` and is
auto-sent), and it does not change what the ring physically measures. Keep the
clinical labelling honest: "breathing disturbances", never "AHI".
