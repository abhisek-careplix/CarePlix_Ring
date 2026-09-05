"""
Reference codec for the Veepoo ring BLE protocol, as used by the CarePlix ring.

Pure Python 3 (standard library only). This is the *specification in executable
form*: every byte offset here was taken from the vendor's own Android protocol
library (`vpprotocol-2.3.81.15.aar`, Apache-2.0, published at
github.com/HBandSDK/Android_Ble_SDK) and cross-checked against the iOS headers.
Port it 1:1 to Swift for the iOS app; the frame layouts are identical on every
platform because the ring firmware speaks exactly one protocol.

Nothing in this file needs the vendor SDK, a licence, or a device-number
whitelist. The ring sends the full record over the air; the vendor SDK merely
declines to parse bytes 9..19 of the oxygen record unless the device number is
licensed. Here we parse everything.

See docs/veepoo-ble-protocol.md for the narrative.
"""

from __future__ import annotations

import datetime as _dt
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

# --------------------------------------------------------------------------- GATT

#: Command channel. Write 20-byte frames to WRITE_CHAR, subscribe to NOTIFY_CHAR.
SERVICE_UUID = "F0080001-0451-4000-B000-000000000000"
NOTIFY_CHAR_UUID = "F0080002-0451-4000-B000-000000000000"
WRITE_CHAR_UUID = "F0080003-0451-4000-B000-000000000000"

#: Raw optical / accelerometer channel ("ADC" in the SDK). Notify only.
PPG_SERVICE_UUID = "F0020001-0451-4000-B000-000000000000"
PPG_NOTIFY_CHAR_UUID = "F0020002-0451-4000-B000-000000000000"

#: Client Characteristic Configuration descriptor, written to enable notifications.
CCCD_UUID = "00002902-0000-1000-8000-00805f9b34fb"

#: Service UUIDs the vendor SDKs filter on when scanning (advertisement payload).
SCAN_SERVICE_HINTS = ("0000fee7-0000-1000-8000-00805f9b34fb", "FFFF", "0001", "180D")

FRAME_LEN = 20

# --------------------------------------------------------------------------- opcodes

OP_PASSWORD = 0xA1          # handshake + time sync; also carries device number
OP_DEVICE_FUNCTION = 0xA7   # capability packets (pushed by the ring, 5 packets, id in byte 19)
OP_BATTERY = 0xA0
OP_SPO2_TEST = 0x80         # spot SpO2 test start/stop/stream
OP_BREATH_TEST = 0x82       # spot breathing-rate test (command channel)
OP_READ_SLEEP = 0xE0
OP_READ_ORIGIN_5MIN = 0xDF  # protocol 3/5 five-minute blocks (TLV)
OP_READ_ORIGIN_OLD = 0xD1   # legacy five-minute records
OP_READ_OXYGEN = 0xD2       # nightly per-minute SpO2 / apnea record
OP_READ_HRV = 0xD9          # nightly per-minute HRV record
OP_READ_RR = 0x70           # beat-to-beat RR interval blocks (3 days)
OP_APNEA_REMIND = 0x86
OP_ALL_SETTING = 0xB3       # SpO2 night auto-detect window etc.
OP_JH58_PPG = 0xEB          # JH58-only raw PPG + accel storage / streaming

# Frames arriving on the PPG channel
PPG_FRAME_GREEN_5 = 0x82    # 5 x 24-bit green samples (spot test light signal)
PPG_FRAME_GREEN = 0x80      # 3-byte samples, 20-bit signed (JH58 real-time / G08W)
PPG_FRAME_RED = 0x83        # G08W
PPG_FRAME_IR = 0x84         # G08W
PPG_FRAME_ACCEL = 0x89      # x,y,z int16 LE per sample


# --------------------------------------------------------------------------- helpers

def _u8(b: int) -> int:
    return b & 0xFF


def _le16(lo: int, hi: int) -> int:
    return (_u8(lo)) | (_u8(hi) << 8)


def _be16(hi: int, lo: int) -> int:
    return (_u8(hi) << 8) | _u8(lo)


def _s16(v: int) -> int:
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def _pad(frame: bytes, n: int = FRAME_LEN) -> bytes:
    return bytes(frame) + bytes(n - len(frame)) if len(frame) < n else bytes(frame)


def _check(frame: bytes, opcode: int, min_len: int = FRAME_LEN) -> None:
    if len(frame) < min_len:
        raise ValueError(f"frame too short: {len(frame)} < {min_len}")
    if frame[0] != opcode:
        raise ValueError(f"opcode 0x{frame[0]:02X} != expected 0x{opcode:02X}")


def sign20(n: int) -> int:
    """20-bit two's complement used by the 0x80/0x83/0x84 PPG frames."""
    n &= 0xFFFFF
    return n - (1 << 20) if n & (1 << 19) else n


def sign_green5(n: int) -> int:
    """
    Sign rule the SDK applies to 0x82 frames: bits 23..21 are a flag field.
    0 -> positive 21-bit value, 7 -> negative (sign-extend from 24 bits),
    1 or 6 -> saturated (0x200000), anything else -> 0.
    """
    n &= 0xFFFFFF
    top = (n >> 21) & 7
    if top == 0:
        return n & 0x1FFFFF
    if top == 7:
        return n - (1 << 24)
    if top in (1, 6):
        return 0x200000
    return 0


# --------------------------------------------------------------------------- A1 handshake

PASSWORD_STATUS = {
    0: "CHECK_FAIL",
    1: "CHECK_SUCCESS",
    2: "SETTING_FAIL",
    3: "SETTING_SUCCESS",
    4: "READ_FAIL",
    5: "READ_SUCCESS",
    6: "CHECK_AND_TIME_SUCCESS",
}


def build_password(
    password: int = 0,
    *,
    set_new: bool = False,
    now: Optional[_dt.datetime] = None,
    is_24h: bool = True,
    tz_offset_minutes: Optional[int] = None,
    flag14: bool = False,
) -> bytes:
    """
    0xA1: verify (or set) the 4-digit link password and sync the ring clock.
    The ring answers with 0xA1 carrying status + device number + firmware.
    Default password on every ring is 0000.
    """
    if not 0 <= password <= 9999:
        raise ValueError("password is a 4-digit number")
    b = bytearray(FRAME_LEN)
    b[0] = OP_PASSWORD
    b[1] = password & 0xFF
    b[2] = (password >> 8) & 0xFF
    b[3] = 1 if set_new else 0
    if set_new:
        return bytes(b)
    now = now or _dt.datetime.now()
    b[4] = (now.year >> 8) & 0xFF
    b[5] = now.year & 0xFF
    b[6] = now.month
    b[7] = now.day
    b[8] = now.hour
    b[9] = now.minute
    b[10] = now.second
    b[11] = 1 if is_24h else 0
    b[12] = 1
    if tz_offset_minutes is None:
        off = now.astimezone().utcoffset() if now.tzinfo is None else now.utcoffset()
        tz_offset_minutes = int(off.total_seconds() // 60) if off is not None else 0
    b[13] = (tz_offset_minutes // 15) & 0xFF   # quarter-hours, signed byte
    b[14] = 1 if flag14 else 0
    return bytes(b)


@dataclass
class PasswordResponse:
    status: str
    device_number: int
    firmware: str
    firmware_test: str
    has_drink_data: Optional[bool]
    night_turn_wrist: Optional[str]
    find_phone: Optional[str]
    wear_detect: Optional[str]

    @property
    def ok(self) -> bool:
        return self.status in ("CHECK_SUCCESS", "CHECK_AND_TIME_SUCCESS")


_TRISTATE = {0: "UNSUPPORT", 1: "SUPPORT_OPEN", 2: "SUPPORT_CLOSE"}


def parse_password_response(frame: bytes) -> PasswordResponse:
    _check(frame, OP_PASSWORD)
    b = frame
    return PasswordResponse(
        status=PASSWORD_STATUS.get(b[3], "UNKNOWN"),
        device_number=_be16(b[4], b[5]),
        firmware=f"{b[6]:02x}.{b[7]:02x}.{b[8]:02x}",
        firmware_test=f"{b[6]:02x}.{b[7]:02x}.{b[8]:02x}.{b[9]:02x}",
        has_drink_data={0: False, 1: True}.get(b[10]),
        night_turn_wrist={0: "SUPPORT_CLOSE", 1: "SUPPORT_OPEN", 2: "UNSUPPORT"}.get(b[11]),
        find_phone=_TRISTATE.get(b[18]),
        wear_detect=_TRISTATE.get(b[19]),
    )


# --------------------------------------------------------------------------- A7 capabilities

SPO2_TYPES_SUPPORTED = {1, 2, 3, 4, 5, 6, 7, 8, 9, 0xFE, 0xFD, 0xE0}


@dataclass
class Capabilities:
    """Fields we care about from the five 0xA7 packets (packet id = byte 19)."""
    spo2_type: Optional[int] = None
    heart_rate: Optional[bool] = None
    blood_pressure: Optional[bool] = None
    watch_days: Optional[int] = None
    breathing_rate_test: Optional[bool] = None
    hrv_type: Optional[int] = None
    origin_protocol_version: Optional[int] = None
    sleep_tag: Optional[int] = None
    ecg_type: Optional[int] = None

    @property
    def spo2(self) -> Optional[bool]:
        return None if self.spo2_type is None else self.spo2_type in SPO2_TYPES_SUPPORTED

    @property
    def apnea_reminder(self) -> Optional[bool]:
        return None if self.spo2_type is None else self.spo2_type == 4

    @property
    def hrv(self) -> Optional[bool]:
        return None if self.hrv_type is None else self.hrv_type not in (0, 5)

    @property
    def hrv_all_day(self) -> Optional[bool]:
        return None if self.hrv_type is None else self.hrv_type in (3, 4, 6, 7, 8)

    @property
    def precise_sleep(self) -> Optional[bool]:
        return None if self.sleep_tag is None else self.sleep_tag != 0

    @property
    def uses_tlv_origin(self) -> Optional[bool]:
        """Protocol 3 or 5 -> 0xDF TLV blocks; otherwise legacy 0xD1 records."""
        v = self.origin_protocol_version
        return None if v is None else v in (3, 5)


def parse_device_function(frame: bytes, caps: Optional[Capabilities] = None) -> Capabilities:
    _check(frame, OP_DEVICE_FUNCTION)
    caps = caps or Capabilities()
    pkt = frame[19]
    if pkt == 1:
        caps.blood_pressure = frame[1] != 0
        caps.spo2_type = frame[8]
        # byte 18: 1 means "no heart-rate function" on this firmware family
        caps.heart_rate = frame[18] != 1
    elif pkt == 2:
        if frame[2] != 0:
            caps.watch_days = frame[2]
        caps.breathing_rate_test = frame[7] != 0
        caps.hrv_type = frame[8]
        caps.origin_protocol_version = frame[10]
        caps.sleep_tag = frame[13]
        caps.ecg_type = frame[15]
    return caps


# --------------------------------------------------------------------------- D2 nightly SpO2 / apnea

def build_read_oxygen(position: int = 1, days_ago: int = 0) -> bytes:
    """0xD2: stream the per-minute oxygen records of one day, starting at packet `position`."""
    if position < 1:
        position = 1
    return bytes([OP_READ_OXYGEN, position & 0xFF, (position >> 8) & 0xFF, days_ago & 0xFF])


@dataclass
class OxygenMinute:
    current_packet: int
    total_packets: int
    days_ago: int
    hour: int
    minute: int
    spo2: int
    apnea_result: int        # vendor: "0 none, 1 present" / "number of apneas"
    is_hypoxia: int
    hypoxia_time: int
    hypopnea: int
    cardiac_load: int
    hrv: int
    sport: int
    heart_rate: int
    steps: int
    respiration_rate: int    # 255 = invalid
    correction: int          # "Temp1": SpO2 correction / debug value

    @property
    def valid(self) -> bool:
        return self.hour < 24 and self.minute < 60 and self.total_packets != 0

    @property
    def respiration_rate_or_none(self) -> Optional[int]:
        return None if self.respiration_rate == 255 else self.respiration_rate


def parse_oxygen_record(frame: bytes) -> OxygenMinute:
    """
    One 0xD2 notification = one minute. Bytes 9..19 are exactly the fields the
    vendor SDK withholds in "restricted mode"; the ring sends them regardless.
    """
    _check(frame, OP_READ_OXYGEN)
    b = frame
    return OxygenMinute(
        current_packet=_le16(b[1], b[2]),
        total_packets=_le16(b[3], b[4]),
        days_ago=b[5],
        hour=b[6],
        minute=b[7],
        spo2=b[8],
        apnea_result=b[9],
        is_hypoxia=b[10],
        hypoxia_time=b[11],
        hypopnea=b[12],
        cardiac_load=b[13],
        hrv=b[14],
        sport=b[15],
        heart_rate=b[16],
        steps=b[17],
        respiration_rate=b[18],
        correction=b[19],
    )


def day_read_complete(frame: bytes) -> bool:
    """
    The vendor's end-of-day rule for the D2 / D9 streams: current == total,
    or total == 0 (nothing stored), or current == 0.
    """
    b = frame
    cur, tot = _le16(b[1], b[2]), _le16(b[3], b[4])
    return cur == tot or tot == 0 or cur == 0


# --------------------------------------------------------------------------- D9 nightly HRV

def build_read_hrv(position: int = 1, days_ago: int = 0) -> bytes:
    if position < 1:
        position = 1
    return bytes([OP_READ_HRV, position & 0xFF, (position >> 8) & 0xFF, days_ago & 0xFF])


@dataclass
class HrvMinute:
    current_packet: int
    total_packets: int
    days_ago: int
    hour: int
    minute: int
    hrv: int
    rr_raw: List[int]        # 10 values; x10 = RR interval in ms (vendor doc)
    valid_count: int

    @property
    def rr_ms(self) -> List[int]:
        return [v * 10 for v in self.rr_raw if v]


def parse_hrv_record(frame: bytes) -> HrvMinute:
    _check(frame, OP_READ_HRV)
    b = frame
    return HrvMinute(
        current_packet=_le16(b[1], b[2]),
        total_packets=_le16(b[3], b[4]),
        days_ago=b[5],
        hour=b[6],
        minute=b[7],
        hrv=b[8],
        rr_raw=list(b[9:19]),
        valid_count=b[19],
    )


# --------------------------------------------------------------------------- 0x70 beat-to-beat RR

RR_UNIT_MS = 20  # the vendor demo converts a sample with 60000 / (v * 20) bpm


def build_read_rr(days_ago: int = 0, from_block: int = 1) -> bytes:
    """0x70: stream RR blocks (one block per minute) for today(0)/yesterday(1)/day before(2)."""
    if from_block < 1:
        from_block = 1
    return _pad(bytes([OP_READ_RR, days_ago & 0xFF, from_block & 0xFF, (from_block >> 8) & 0xFF]))


@dataclass
class RRBlock:
    block: int
    total_blocks: int
    days_ago: int
    timestamp: _dt.datetime
    count: int
    samples: List[int] = field(default_factory=list)   # raw units of RR_UNIT_MS
    packets_seen: int = 0
    packets_total: int = 0

    @property
    def complete(self) -> bool:
        return self.packets_total > 0 and self.packets_seen >= self.packets_total

    @property
    def rr_ms(self) -> List[int]:
        return [v * RR_UNIT_MS for v in self.samples[: self.count] if 12 <= v <= 120]


class RRAssembler:
    """Feed every 0x70 notification; get an RRBlock back when a block completes."""

    def __init__(self) -> None:
        self._blocks: Dict[int, RRBlock] = {}

    def feed(self, frame: bytes) -> Optional[RRBlock]:
        _check(frame, OP_READ_RR)
        b = frame
        block = _le16(b[1], b[2])
        if block == 0:
            return None
        total_blocks = _le16(b[3], b[4])
        pkg, pkg_total = b[5], b[6]
        if pkg == 0:
            ts = _dt.datetime(2000 + b[8], max(1, b[9]), max(1, b[10]), b[11] % 24, b[12] % 60, b[13] % 60)
            rb = RRBlock(block=block, total_blocks=total_blocks, days_ago=b[7], timestamp=ts,
                         count=_le16(b[14], b[15]), packets_total=pkg_total)
            rb.samples.extend(b[16:20])
            self._blocks[block] = rb
        else:
            rb = self._blocks.get(block)
            if rb is None:
                return None
            rb.samples.extend(b[7:20])
        rb.packets_seen = pkg + 1
        rb.packets_total = pkg_total
        if pkg == pkg_total:
            del rb.samples[rb.count:]
            return self._blocks.pop(block)
        return None


# --------------------------------------------------------------------------- DF five-minute TLV blocks

def build_read_origin(position: int = 1, days_ago: int = 0) -> bytes:
    """0xDF: stream the five-minute blocks of one day (protocol 3/5 rings)."""
    if position < 1:
        position = 1
    return _pad(bytes([OP_READ_ORIGIN_5MIN, position & 0xFF, (position >> 8) & 0xFF, days_ago & 0xFF]))


@dataclass
class DFHeader:
    block: int
    total_blocks: int
    pkg_index: int
    pkg_total: int
    read_day: int
    read_type: int
    data_type: int
    valid_bytes: int
    check: int
    pkg_len: int


def parse_df_header(frame: bytes, protocol_version: int = 3) -> DFHeader:
    b = frame
    return DFHeader(
        block=_le16(b[1], b[2]),
        total_blocks=_le16(b[4], b[5]),
        pkg_index=b[3],
        pkg_total=b[6],
        read_day=b[7],
        read_type=b[8],
        data_type=b[9],
        valid_bytes=b[10],
        check=_le16(b[11], b[12]),
        pkg_len=b[13] if protocol_version == 5 else FRAME_LEN,
    )


TLV_TIME = 0xB1
TLV_SPORT = 0xB2
TLV_SLEEP = 0xB3
TLV_PPG_RATE = 0xB4
TLV_ECG_RATE = 0xB5
TLV_BREATH = 0xB6
TLV_HRV = 0xB7
TLV_BP = 0xB8
TLV_SPO2 = 0xB9
TLV_SLEEP_SPORT = 0xBA
TLV_SLEEP_STATUS = 0xBB
TLV_RESET_TAG = 0xBC
TLV_UNUSED_BD = 0xBD
TLV_GLUCOSE = 0xBE
TLV_MET = 0xBF
TLV_PRESSURE = 0xC1
TLV_BLOOD_COMP = 0xC2
TLV_TEMPERATURE = 0xC3
TLV_SKIP_C4 = 0xC4
TLV_SKIP_C5 = 0xC5
TLV_SPORT_STATUS = 0xC6

_KNOWN_TAGS = {
    TLV_TIME, TLV_SPORT, TLV_SLEEP, TLV_PPG_RATE, TLV_ECG_RATE, TLV_BREATH, TLV_HRV, TLV_BP,
    TLV_SPO2, TLV_SLEEP_SPORT, TLV_SLEEP_STATUS, TLV_RESET_TAG, TLV_UNUSED_BD, TLV_GLUCOSE,
    TLV_MET, TLV_PRESSURE, TLV_BLOOD_COMP, TLV_TEMPERATURE, TLV_SKIP_C4, TLV_SKIP_C5, TLV_SPORT_STATUS,
}


def parse_tlv(payload: bytes) -> Dict[int, bytes]:
    """Split a reassembled block payload into {tag: value}. Stops at the first unknown tag."""
    out: Dict[int, bytes] = {}
    i, n = 0, len(payload)
    while i + 1 < n:
        tag, ln = payload[i], payload[i + 1]
        i += 2
        if tag not in _KNOWN_TAGS:
            break
        if i + ln > n:
            break
        val = payload[i:i + ln]
        i += ln
        if tag == TLV_TIME and (ln != 4 or (val[0] == 0 and val[1] == 0)):
            break
        out[tag] = val
    return out


@dataclass
class FiveMinuteRecord:
    hour: int
    minute: int
    read_day: int                      # days ago; the date is today - read_day
    steps: int = 0
    sport: int = 0
    distance_km: float = 0.0
    kcal: float = 0.0
    pose: int = 0
    wear: int = 0
    sleep_states: List[int] = field(default_factory=list)       # 5 per-minute values
    ppg_rates: List[int] = field(default_factory=list)          # 5 per-minute pulse rates (green PPG)
    ecg_rates: List[int] = field(default_factory=list)          # 5 per-minute HR from electrodes (empty on a ring)
    breath_rates: List[int] = field(default_factory=list)       # 5 per-minute respiration rates
    bp: Tuple[int, int] = (0, 0)
    hrv_type: int = 0
    hrv_rr50: List[int] = field(default_factory=list)           # 50 values, 10 per minute (x10 ms)
    hrv5: List[int] = field(default_factory=list)               # vendor per-minute HRV derived from rr50
    spo2: List[int] = field(default_factory=list)               # 5 per-minute SpO2
    apnea_count: List[int] = field(default_factory=list)
    apnea_result: List[int] = field(default_factory=list)       # SDK exposes this as "isHypoxias"
    hypoxia_time: List[int] = field(default_factory=list)
    cardiac_load: List[int] = field(default_factory=list)
    spo2_correction: List[int] = field(default_factory=list)    # "checkFlag" / "corrects"
    sleep_sport: List[int] = field(default_factory=list)
    sleep_status: List[int] = field(default_factory=list)
    reset_tag: List[int] = field(default_factory=list)
    glucose_raw: Optional[int] = None
    met: float = 0.0
    pressure: int = 0
    skin_temp_c: float = 0.0
    body_temp_c: float = 0.0
    sport_status: List[int] = field(default_factory=list)
    raw_tags: Dict[int, bytes] = field(default_factory=dict)


def _hrv5_from_rr50(rr50: List[int]) -> List[int]:
    """Vendor rule: per minute, mean absolute successive difference of the 10 RR values
    within 30..210, x10, modulo 211."""
    out = []
    for m in range(5):
        prev, acc, cnt = -1, 0, 0
        for v in rr50[m * 10:(m + 1) * 10]:
            if v < 30 or v > 210:
                continue
            if prev != -1:
                acc += abs(prev - v)
                cnt += 1
            prev = v
        out.append(round(acc * 10 / cnt) % 211 if cnt else 0)
    return out


def parse_five_minute_block(payload: bytes, read_day: int) -> Optional[FiveMinuteRecord]:
    tags = parse_tlv(payload)
    t = tags.get(TLV_TIME)
    if t is None or len(t) < 4:
        return None
    rec = FiveMinuteRecord(hour=t[2], minute=t[3], read_day=read_day, raw_tags=tags)
    if rec.hour > 23 or rec.minute > 59:
        return None
    s = tags.get(TLV_SPORT)
    if s and len(s) >= 10:
        rec.steps = _be16(s[0], s[1])
        rec.sport = _be16(s[2], s[3])
        rec.distance_km = round(_be16(s[4], s[5]) / 1000.0, 3)
        rec.kcal = round(_be16(s[6], s[7]) / 10.0, 1)
        rec.pose, rec.wear = s[8], s[9]
    rec.sleep_states = list(tags.get(TLV_SLEEP, b""))
    rec.ppg_rates = list(tags.get(TLV_PPG_RATE, b""))
    rec.ecg_rates = list(tags.get(TLV_ECG_RATE, b""))
    rec.breath_rates = list(tags.get(TLV_BREATH, b""))
    bp = tags.get(TLV_BP)
    if bp and len(bp) >= 2:
        rec.bp = (bp[0], bp[1])
    h = tags.get(TLV_HRV)
    if h and len(h) >= 51:
        rec.hrv_type = h[0]
        rec.hrv_rr50 = list(h[1:51])
        rec.hrv5 = _hrv5_from_rr50(rec.hrv_rr50)
    o = tags.get(TLV_SPO2)
    if o:
        def seg(k: int) -> List[int]:
            return list(o[k * 5:(k + 1) * 5]) if len(o) >= (k + 1) * 5 else []
        rec.spo2, rec.apnea_count, rec.apnea_result = seg(0), seg(1), seg(2)
        rec.hypoxia_time, rec.cardiac_load, rec.spo2_correction = seg(3), seg(4), seg(5)
    rec.sleep_sport = list(tags.get(TLV_SLEEP_SPORT, b""))
    rec.sleep_status = list(tags.get(TLV_SLEEP_STATUS, b""))
    rec.reset_tag = list(tags.get(TLV_RESET_TAG, b""))
    g = tags.get(TLV_GLUCOSE)
    if g and len(g) >= 2:
        rec.glucose_raw = _le16(g[0], g[1])
    m = tags.get(TLV_MET)
    if m:
        rec.met = m[0] / 10.0
    p = tags.get(TLV_PRESSURE)
    if p:
        rec.pressure = p[0]
    tp = tags.get(TLV_TEMPERATURE)
    if tp and len(tp) >= 4:
        base, body = _le16(tp[0], tp[1]), _le16(tp[2], tp[3])
        if 120 <= base <= 480 and 120 <= body <= 480:
            rec.skin_temp_c, rec.body_temp_c = round(base / 10.0, 1), round(body / 10.0, 1)
    rec.sport_status = list(tags.get(TLV_SPORT_STATUS, b""))
    return rec


class DFAssembler:
    """
    Reassemble 0xDF notifications into five-minute blocks.

    Packet shapes (all start with 0xDF):
      header  : bytes 1..2 = block (LE), byte 3 == 0, bytes 4..5 = total blocks, byte 6 = packets
                in block, 7 = read day, 8 = read type, 9 = data type, 10 = valid bytes,
                11..12 = check, 13 = packet length (protocol 5) else 20.
      data    : bytes 1..2 = block, byte 3 = packet index >= 1, payload from byte 4.
      end     : bytes 1 and 2 both 0xFF, bytes 3..4 = total blocks.
    """

    def __init__(self, protocol_version: int = 3) -> None:
        self.protocol_version = protocol_version
        self._header: Optional[DFHeader] = None
        self._payload = bytearray()
        self.finished = False

    def _flush(self) -> Optional[FiveMinuteRecord]:
        if self._header is None or not self._payload:
            self._header, self._payload = None, bytearray()
            return None
        rec = parse_five_minute_block(bytes(self._payload), self._header.read_day)
        self._header, self._payload = None, bytearray()
        return rec

    def feed(self, frame: bytes) -> Optional[FiveMinuteRecord]:
        _check(frame, OP_READ_ORIGIN_5MIN)
        b = frame
        if b[1] == 0xFF and b[2] == 0xFF:
            self.finished = True
            return self._flush()
        if b[3] == 0:
            done = self._flush()
            self._header = parse_df_header(frame, self.protocol_version)
            return done
        if self._header is None or _le16(b[1], b[2]) != self._header.block:
            return None
        n = self._header.pkg_len - 4
        self._payload.extend(b[4:4 + n])
        return None


# --------------------------------------------------------------------------- sleep, spot tests, settings

def build_read_sleep(days_ago: int = 1) -> bytes:
    """0xE0: sleep segments of one day (use 1 = last night). Response layout not yet decoded."""
    return bytes([OP_READ_SLEEP, days_ago & 0xFF])


SPO2_TEST_START = bytes([OP_SPO2_TEST, 1, 2])
SPO2_TEST_STOP = bytes([OP_SPO2_TEST, 2, 2])


@dataclass
class Spo2TestFrame:
    function_state: str          # NOT_SUPPORT / OPEN / CLOSE / UNKNOWN
    device_busy: bool
    spo2: int
    calibrating: bool
    progress: int
    heart_rate: Optional[int]
    wear_failed: bool


def parse_spo2_test(frame: bytes) -> Spo2TestFrame:
    _check(frame, OP_SPO2_TEST, min_len=6)
    b = frame
    hr = b[7] if len(b) >= 20 and b[6] == 6 else None
    return Spo2TestFrame(
        function_state={0: "NOT_SUPPORT", 1: "OPEN", 2: "CLOSE"}.get(b[1], "UNKNOWN"),
        device_busy=b[2] not in (0, 4),
        spo2=b[3],
        calibrating=b[4] in (1, 2),
        progress=b[5],
        heart_rate=hr,
        wear_failed=b[3] == 1,
    )


def build_spo2_night_window(start_h: int = 22, start_m: int = 0, end_h: int = 8, end_m: int = 0,
                            enable: bool = True, read_only: bool = False) -> bytes:
    """
    0xB3 all-setting frame for the nightly automatic SpO2 window (type 0x00).
    Layout follows the SDK's AllSetSetting(type, startH, startM, endH, endM, operate, open):
    operate 0 = set, 1 = read.  Verify against a live ring before relying on it.
    """
    return _pad(bytes([OP_ALL_SETTING, 0x00, 1 if read_only else 0, start_h, start_m, end_h, end_m,
                       1 if enable else 0]))


# --------------------------------------------------------------------------- PPG channel frames

@dataclass
class LightFrame:
    kind: str                     # green5 / green / red / ir / accel / unknown
    samples: List[int] = field(default_factory=list)
    accel: List[Tuple[int, int, int]] = field(default_factory=list)


_FILLER_24 = 0x080808


def parse_ppg_frame(frame: bytes) -> LightFrame:
    """Decode a notification from PPG_NOTIFY_CHAR_UUID."""
    if not frame:
        return LightFrame("unknown")
    op = frame[0]
    if op == PPG_FRAME_GREEN_5:
        vals = []
        for i in range(5):
            j = 1 + i * 3
            if j + 3 > len(frame):
                break
            vals.append(sign_green5((frame[j] << 16) | (frame[j + 1] << 8) | frame[j + 2]))
        return LightFrame("green5", vals)
    if op in (PPG_FRAME_GREEN, PPG_FRAME_RED, PPG_FRAME_IR):
        kind = {PPG_FRAME_GREEN: "green", PPG_FRAME_RED: "red", PPG_FRAME_IR: "ir"}[op]
        vals = []
        j = 1
        while j + 3 <= len(frame):
            n = (frame[j] << 16) | (frame[j + 1] << 8) | frame[j + 2]
            if n != _FILLER_24:
                vals.append(sign20(n))
            j += 3
        return LightFrame(kind, vals)
    if op == PPG_FRAME_ACCEL:
        acc = []
        j = 1
        while j + 6 <= len(frame) - 3:   # the SDK stops 4 bytes before the end
            acc.append((_s16(_le16(frame[j], frame[j + 1])),
                        _s16(_le16(frame[j + 2], frame[j + 3])),
                        _s16(_le16(frame[j + 4], frame[j + 5]))))
            j += 6
        return LightFrame("accel", accel=acc)
    return LightFrame("unknown")


# --------------------------------------------------------------------------- convenience

def hexdump(frame: bytes) -> str:
    return " ".join(f"{x:02X}" for x in frame)
