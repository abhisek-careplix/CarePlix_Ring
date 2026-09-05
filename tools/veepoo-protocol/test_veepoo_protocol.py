"""
Unit tests for the Veepoo protocol codec.

These build frames the way the ring firmware does, then parse them back, so they
verify the offsets are self-consistent and the assemblers stitch multi-packet
records correctly. They do NOT prove the offsets match the real ring: that needs
one capture from hardware (see docs/veepoo-ble-protocol.md, "Validate on
hardware"). Run: python3 -m pytest test_veepoo_protocol.py   (or: python3 test_veepoo_protocol.py)
"""

import datetime as dt

import veepoo_protocol as vp


def _frame(*vals):
    b = bytearray(vp.FRAME_LEN)
    for i, v in enumerate(vals):
        b[i] = v & 0xFF
    return bytes(b)


# --------------------------------------------------------------------------- handshake

def test_password_roundtrip():
    frame = vp.build_password(1234, now=dt.datetime(2026, 9, 5, 23, 12, 30), tz_offset_minutes=330)
    assert frame[0] == vp.OP_PASSWORD
    assert vp._le16(frame[1], frame[2]) == 1234
    assert frame[3] == 0            # verify, not set
    assert frame[6] == 9 and frame[7] == 5 and frame[8] == 23 and frame[9] == 12
    assert frame[13] == 330 // 15   # 22 quarter-hours


def test_password_response():
    b = _frame(0xA1, 0, 0, 1, 0x01, 0x43, 0x02, 0x00, 0x0A, 0x05, 1, 1)
    b = bytearray(b)
    b[18] = 1  # find phone open
    b[19] = 1  # wear detect open
    r = vp.parse_password_response(bytes(b))
    assert r.ok
    assert r.status == "CHECK_SUCCESS"
    assert r.device_number == 0x0143   # 323
    assert r.wear_detect == "SUPPORT_OPEN"


# --------------------------------------------------------------------------- capabilities

def test_capabilities_two_packets():
    p1 = bytearray(_frame(0xA7))
    p1[1] = 1        # has BP
    p1[8] = 4        # spo2 type 4 -> apnea reminder firmware
    p1[18] = 0       # has heart rate
    p1[19] = 1       # packet id 1
    p2 = bytearray(_frame(0xA7))
    p2[2] = 7        # 7 watch days
    p2[7] = 1        # breathing-rate test
    p2[8] = 8        # hrv type 8 -> hrv + app detect + all-day
    p2[10] = 3       # protocol version 3
    p2[13] = 1       # sleep tag -> precise sleep
    p2[15] = 2       # ecg type
    p2[19] = 2       # packet id 2

    caps = vp.parse_device_function(bytes(p1))
    caps = vp.parse_device_function(bytes(p2), caps)

    assert caps.spo2 is True
    assert caps.apnea_reminder is True
    assert caps.heart_rate is True
    assert caps.watch_days == 7
    assert caps.breathing_rate_test is True
    assert caps.hrv is True and caps.hrv_all_day is True
    assert caps.origin_protocol_version == 3 and caps.uses_tlv_origin is True
    assert caps.precise_sleep is True


# --------------------------------------------------------------------------- D2 oxygen / apnea

def test_oxygen_record_full():
    b = _frame(0xD2,
               0x05, 0x00,   # current packet 5
               0x20, 0x00,   # total 32
               0x01,         # yesterday
               0x02, 0x1E,   # 02:30
               95,           # spo2
               2,            # apnea result
               1,            # is hypoxia
               40,           # hypoxia time
               1,            # hypopnea
               60,           # cardiac load
               45,           # hrv
               10,           # sport
               58,           # heart
               0,            # steps
               14,           # respiration rate
               75)           # correction / Temp1
    o = vp.parse_oxygen_record(b)
    assert o.valid
    assert (o.hour, o.minute) == (2, 30)
    assert o.spo2 == 95
    assert o.apnea_result == 2
    assert o.hypoxia_time == 40
    assert o.hypopnea == 1
    assert o.cardiac_load == 60
    assert o.respiration_rate_or_none == 14
    assert o.days_ago == 1


def test_oxygen_respiration_invalid_sentinel():
    b = bytearray(_frame(0xD2, 1, 0, 1, 0, 0, 0, 0, 90))
    b[18] = 255
    b[4] = 1  # total != 0
    o = vp.parse_oxygen_record(bytes(b))
    assert o.respiration_rate == 255
    assert o.respiration_rate_or_none is None


def test_day_complete_rule():
    assert vp.day_read_complete(_frame(0xD2, 0x20, 0, 0x20, 0))   # current == total
    assert vp.day_read_complete(_frame(0xD2, 0x03, 0, 0x00, 0))   # total 0
    assert not vp.day_read_complete(_frame(0xD2, 0x03, 0, 0x20, 0))


# --------------------------------------------------------------------------- D9 HRV / RR

def test_hrv_record_rr():
    b = bytearray(_frame(0xD9, 1, 0, 8, 0, 1, 0, 30, 40))
    rr = [80, 78, 0, 82, 79, 77, 81, 0, 76, 80]
    for i, v in enumerate(rr):
        b[9 + i] = v
    b[19] = 8  # valid count
    h = vp.parse_hrv_record(bytes(b))
    assert h.hrv == 40
    assert h.rr_ms == [v * 10 for v in rr if v]  # zeros dropped
    assert h.valid_count == 8


def test_rr_block_assembler_two_packets():
    asm = vp.RRAssembler()
    # header packet: block 1, total 1, pkg 0 of 1, day 0, date 26-09-05 02:30:00,
    # count 6, first 4 samples in bytes 16..19
    hdr = _frame(0x70,
                 0x01, 0x00,   # block 1
                 0x01, 0x00,   # total blocks 1
                 0x00,         # pkg index 0
                 0x01,         # pkg total 1
                 0x00,         # day 0
                 26,           # year 2026
                 9, 5, 2, 30, 0,   # 02:30:00
                 0x06, 0x00,   # count 6
                 50, 50, 50, 50)  # first 4 samples
    assert asm.feed(hdr) is None
    # data packet: block 1, pkg 1 of 1, samples from byte 7
    dat = _frame(0x70, 0x01, 0x00, 0, 0, 0x01, 0x01, 50, 50)
    rb = asm.feed(dat)
    assert rb is not None
    assert rb.block == 1
    assert rb.timestamp == dt.datetime(2026, 9, 5, 2, 30, 0)
    assert len(rb.samples) == 6                # trimmed to count
    assert rb.rr_ms == [50 * vp.RR_UNIT_MS] * 6  # 50 in [12,120] -> 1000 ms each


# --------------------------------------------------------------------------- DF five-minute TLV

def _tlv(*chunks):
    out = bytearray()
    for tag, val in chunks:
        out.append(tag)
        out.append(len(val))
        out.extend(val)
    return bytes(out)


def test_five_minute_block_spo2_and_hrv():
    rr50 = bytes([80] * 50)
    payload = _tlv(
        # time field: bytes 2,3 = hour,minute; bytes 0,1 must be non-zero or the
        # SDK treats the block as a lead-time / empty record and stops (see vp_ao.vp_d).
        (vp.TLV_TIME, bytes([2, 30, 2, 30])),                      # 02:30
        (vp.TLV_SPORT, bytes([0, 100, 0, 0x20, 0, 0x0A, 0, 0x1E, 3, 1])),  # steps 100, wear 1
        (vp.TLV_PPG_RATE, bytes([58, 57, 59, 58, 60])),
        (vp.TLV_BREATH, bytes([14, 13, 14, 15, 14])),
        (vp.TLV_HRV, bytes([8]) + rr50),
        (vp.TLV_SPO2, bytes([95, 96, 94, 95, 96,       # spo2
                             1, 0, 2, 0, 1,            # apnea count
                             0, 1, 0, 0, 1,            # apnea result
                             0, 30, 0, 0, 20,          # hypoxia time
                             50, 55, 60, 52, 58,       # cardiac load
                             70, 71, 72, 73, 74])),    # correction
        (vp.TLV_TEMPERATURE, bytes([0xF0, 1, 0x40, 1])),  # 496? -> base 496 invalid; use valid below
    )
    rec = vp.parse_five_minute_block(payload, read_day=1)
    assert rec is not None
    assert (rec.hour, rec.minute) == (2, 30)
    assert rec.steps == 100 and rec.wear == 1
    assert rec.ppg_rates == [58, 57, 59, 58, 60]
    assert rec.breath_rates == [14, 13, 14, 15, 14]
    assert rec.spo2 == [95, 96, 94, 95, 96]
    assert rec.apnea_count == [1, 0, 2, 0, 1]
    assert rec.apnea_result == [0, 1, 0, 0, 1]
    assert rec.hypoxia_time == [0, 30, 0, 0, 20]
    assert rec.cardiac_load == [50, 55, 60, 52, 58]
    assert len(rec.hrv_rr50) == 50 and len(rec.hrv5) == 5


def test_temperature_valid_range():
    payload = _tlv(
        (vp.TLV_TIME, bytes([3, 0, 3, 0])),
        (vp.TLV_TEMPERATURE, bytes([0x2C, 1, 0x40, 1])),  # 300 -> 30.0C, 320 -> 32.0C
    )
    rec = vp.parse_five_minute_block(payload, read_day=0)
    assert rec.skin_temp_c == 30.0
    assert rec.body_temp_c == 32.0


def test_tlv_stops_at_unknown_tag():
    payload = _tlv((vp.TLV_TIME, bytes([1, 0, 1, 0]))) + bytes([0x00, 0x02, 0xAA, 0xBB])
    tags = vp.parse_tlv(payload)
    assert vp.TLV_TIME in tags
    assert 0x00 not in tags


def test_df_assembler_stitches_multipacket_block():
    asm = vp.DFAssembler(protocol_version=3)
    payload = _tlv(
        (vp.TLV_TIME, bytes([4, 15, 4, 15])),
        (vp.TLV_SPO2, bytes([93] * 5 + [0] * 25)),
    )
    # data packets carry 16 payload bytes each (pkg_len 20 - 4); chunk the whole block
    chunks = [payload[i:i + 16] for i in range(0, len(payload), 16)]
    # header: block 1, byte3==0, total blocks 1, pkg total = number of data packets
    hdr = _frame(0xDF, 0x01, 0x00, 0x00, 0x01, 0x00, len(chunks), 0x01, 0, 0, len(payload))
    assert asm.feed(hdr) is None
    for idx, chunk in enumerate(chunks, start=1):
        d = bytes([0xDF, 0x01, 0x00, idx]) + chunk.ljust(16, b"\x00")
        assert asm.feed(d) is None
    # end packet flushes the block
    end = _frame(0xDF, 0xFF, 0xFF, 0x01, 0x00)
    rec = asm.feed(end)
    assert asm.finished
    assert rec is not None
    assert (rec.hour, rec.minute) == (4, 15)
    assert rec.spo2 == [93, 93, 93, 93, 93]


# --------------------------------------------------------------------------- spot test

def test_spo2_spot_test():
    b = bytearray(_frame(0x80, 1, 0, 96, 0, 0, 6, 61))
    f = vp.parse_spo2_test(bytes(b))
    assert f.function_state == "OPEN"
    assert not f.device_busy
    assert f.spo2 == 96
    assert f.heart_rate == 61


def test_spo2_wear_failed():
    f = vp.parse_spo2_test(_frame(0x80, 1, 0, 1, 0, 0))
    assert f.wear_failed


# --------------------------------------------------------------------------- PPG channel

def test_ppg_green5_frame():
    # one positive sample 0x000064 (=100), rest zero
    frame = bytes([0x82, 0x00, 0x00, 0x64] + [0] * 15)
    lf = vp.parse_ppg_frame(frame)
    assert lf.kind == "green5"
    assert lf.samples[0] == 100


def test_ppg_accel_frame():
    frame = bytes([0x89,
                   0x10, 0x00, 0xF0, 0xFF, 0x01, 0x00,   # (16, -16, 1)
                   0, 0, 0])
    lf = vp.parse_ppg_frame(frame)
    assert lf.kind == "accel"
    assert lf.accel and lf.accel[0] == (16, -16, 1)


def test_sign_helpers():
    assert vp.sign20(0x00064) == 100
    assert vp.sign20(0xFFFFF) == -1
    assert vp.sign_green5(0x000064) == 100
    assert vp.sign_green5(0xFFFFFF) == -1


if __name__ == "__main__":
    import traceback

    passed = failed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                passed += 1
                print(f"PASS {name}")
            except Exception:
                failed += 1
                print(f"FAIL {name}")
                traceback.print_exc()
    print(f"\n{passed} passed, {failed} failed")
    raise SystemExit(1 if failed else 0)
