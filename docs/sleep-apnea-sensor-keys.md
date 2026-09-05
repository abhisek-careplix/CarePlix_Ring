# Sleep apnea: every sensor key the Veepoo SDK exposes for the CarePlix ring

*What the ring can give us for a sleep-apnea analysis, key by key, taken from the vendor SDK
headers and docs rather than from memory. This is the "analyse first" step; nothing here is
implemented yet.*

## 1 · Where the SDK actually is

This repository does not contain the vendor SDK. It contains an Android provisioner
(`tools/ring-provisioner`) and, on the `claude/ios-sdk-ux-redesign-3j208q` branch, an iOS
discovery layer plus a UX sensor map (`docs/ux/03-sensor-data-map.md`) that was written from the
SDK headers but does not list the apnea fields.

The SDK itself is public, published by Veepoo under the **HBandSDK** GitHub organisation:

| Platform | Repo | Where the truth lives |
|---|---|---|
| iOS | `HBandSDK/iOS_Ble_SDK` (checked 2026-08-28) | `iOS_sdk_source/Demo/VeepooBleSDKDemo/VeepooBleSDKDemo/VeepooBleSDK.framework/Headers/*.h` (124 headers) and `iOS_sdk_source/doc/VeepooSDK iOS Api_en.md` |
| Android | `HBandSDK/Android_Ble_SDK` (checked 2026-08-27) | `android_sdk_source/apidoc/com/veepoo/protocol/**` (Javadoc) and `android_sdk_source/sdkdoc/VeepooSDK Android Api - English.md` |

Headers that matter for apnea: `VPDataBaseOperation.h`, `VPOxygenAnalysisModel.h`,
`VPOxygenApneaRemindModel.h`, `VPRRIntervalDataModel.h`, `VPRRIntervalDataHRVHandle.h`,
`VPAccurateSleepModel.h`, `VPAutoMonitTestModel.h`, `VPPeripheralModel.h`,
`VPPeripheralBaseManage.h`, `VPPublicDefine.h`, `VPJH58PPGAccelerationModel.h`,
`VPAccelerationModel.h`. Android equivalents: `Spo2hOriginData`, `OriginData3`,
`HRVOriginData`, `Spo2hOriginUtil`, `ESpo2hDataType`, `BreathBreakRemindData`,
`IOriginData3Listener`, `PPGSecondData`.

## 2 · What the ring physically measures

PPG (green for pulse, red + infrared for SpO₂), a 3-axis accelerometer, and a skin thermistor.
Everything below is derived from those three signals on the ring's own firmware. There is no
airflow, chest-effort, snore, or ECG channel. So "apnea" from this ring is always
**oxygen-desaturation + pulse-rate + movement inference**, never a measured respiratory event.

## 3 · Before reading anything: capability flags

All of these populate on `VPPeripheralModel` (iOS) only after the connection state reaches
`VPDeviceConnectStateVerifyPasswordSuccess`. They are 0 during scanning.

| iOS (`VPPeripheralModel`) | Android (`FunctionDeviceSupportData`) | Meaning for apnea |
|---|---|---|
| `oxygenType` ≠ 0, `bloodOxygenType` | `spoH` | Ring has SpO₂ at all |
| `oxygenAutoDetectType` | `EAllSetType.SPO2H_NIGHT_AUTO_DETECT` | Nightly automatic SpO₂ is available |
| `hrvType` ≠ 0, `hrvSupportAllDay`, `isSupportHRVTest` | `hrvFunction`, `isSupportHRV`, `isSupportHrvAppDetect` | Per-minute HRV and RR intervals overnight (00:00–08:00 unless all-day) |
| `resRateType` = 1 | `beathFunction` / `breathFunction` | Breathing-rate spot test |
| `sleepType` (0 normal, 1/3 precise) | `precisionSleep`, `sleepTag` | Per-minute sleep stages vs 5-minute |
| `wearMonitoringState` (0 none, 1 on, 2 off) | `wearDetectFunction` | Off-finger detection |
| `temperatureType` (2/4/5 have auto) | `isSupportReadTempture` | 5-minute skin temperature |
| `saveDays` | `watchDataDayNumber` / `WathcDay` | Days of history kept on the ring |
| `fiveProtocolType` | `originProtocolVersion` (3 or 5 ⇒ use `IOriginData3Listener`) | Which 5-minute record layout the ring speaks |
| `isSupportMotionState`, `motionState` | — | `motionState[]` present in 5-minute records |
| — | `spoHBreathBreak` | Apnea-reminder (vibration) function exists |

`deviceFuctionData` byte 7 (index from 1) is the legacy "has SpO₂" bit; prefer `oxygenType`.

## 4 · How data gets off the ring

Nothing is streamed live overnight. The ring records to its own flash; the phone syncs after
waking and then reads from the SDK's local database by date + MAC.

iOS, in order:

1. `veepooSdkStartReadDeviceAllDataWithReadStateChangeBlock:` (sleep, steps, 5-minute origin,
   SpO₂, HRV; temperature too when `temperatureType == 5`). Progress arrives as
   `VPReadDeviceBaseDataState` start → reading → complete.
2. Or individually: `veepooSdkStartReadDeviceOxygenData:`, `veepooSdkStartReadDeviceHrvData:`,
   `veepooSdkStartReadDeviceTemperatureData:`.
3. Then query `VPDataBaseOperation` with `queryDate` = `yyyy-MM-dd` and `tableID` = ring MAC.

Android: `readOriginData(...)` / `readOriginDataSingleDay(day, position, watchday)` with an
`IOriginData3Listener`. After each day's read completes the listener fires
`onOriginSpo2OriginListDataChange(List<Spo2hOriginData>)`,
`onOriginHRVOriginListDataChange(List<HRVOriginData>)`, and
`onOriginFiveMinuteListDataChange(List<OriginData3>)`. Remember `currentPackage` from
`onReadOriginProgressDetail` to avoid re-reading.

## 5 · Tier 1: the nightly SpO₂ record (the apnea record)

`+[VPDataBaseOperation veepooSDKGetDeviceOxygenDataWithDate:andTableID:]` returns one
dictionary **per minute**. The Android twin is `Spo2hOriginData`. The vendor states the SpO₂
data is only valid **00:00–07:00** (the ring's algorithm window), and that on firmware with
"blood oxygen type 4" the apnea reminder replaces the plain low-oxygen switch.

| iOS constant | iOS string key | Android field | Meaning (from headers) | Notes |
|---|---|---|---|---|
| `VPOxygenTimeKey` | `Time` | `mTime` (`TimeData`) | Minute, `"HH:mm"` | |
| `VPOxygenValueKey` | `OxygenValue` | `oxygenValue` | SpO₂ % | 0 = no reading. **In "restricted mode" this is the only field returned** (see §11) |
| `VPApneaResultKey` | `ApneaResult` | `apneaResult` | Header: "apnea result, 0 none, 1 present"; API doc: "number of apneas" | Firmware's own per-minute apnea flag/count |
| `VPIsHypoxiaKey` | `IsHypoxia` | `isHypoxia` | Whether hypoxic this minute | Android util reads it as "D2 bit 10, used to grade the apnea level" |
| `VPHypoxiaTimeKey` | `HypoxiaTime` | `hypoxiaTime` | Low-oxygen duration | Units not documented; treat as minutes/seconds after bench check |
| `VPHypopneaKey` | `Hypopnea` | `hypopnea` | Hypopnea (reduced breathing) indicator | |
| `VPCardiacLoadKey` | `CardiacLoad` | `cardiacLoad` | Vendor "cardiac load" index | |
| `VPHRVKey` | `HRV` | `hRVariation` | HRV this minute | |
| `VPHeartValueKey` | `HeartValue` | `heartValue` | Pulse rate bpm | |
| `VPRespirationRateKey` | `RespirationRate` | `respirationRate` | Breaths per minute | **255 = invalid**, must be filtered |
| `VPSportValueKey` | `SportValue` | `sportValue` | Motion intensity 0–65535 | Movement proxy for arousal / off-finger |
| `VPStepValueKey` | `StepValue` | `stepValue` | Steps this minute | |
| `VPTemp1Key` | `Temp1` | `temp1` | "Debugging parameter" / SpO₂ correction value | Android `OriginData3.corrects` says it is the SpO₂ correction value |
| `VPTemp2Key` | `Temp2` | — | Reserved | |
| — | `protocolType` | — | Record layout version | |

This one array is the backbone of any apnea report: SpO₂ curve, pulse curve, respiration curve,
movement, and the firmware's own apnea/hypoxia flags, all on a shared minute grid.

## 6 · Tier 2: HRV and beat-to-beat RR intervals

### Per-minute HRV with RR list (in the database)

`+[VPDataBaseOperation veepooSDKGetDeviceHrvDataWithDate:andTableID:]`, one dictionary per minute.

| iOS constant | String key | Android (`HRVOriginData`) | Meaning |
|---|---|---|---|
| `VPHRVTimeKey` | `time` | `mTime` | Minute |
| `VPHRVValueKey` | `hrvValue` | `hrvValue` | HRV value (ms) |
| `VPHRVTempKey` | `temp1` | `tempOne` | Android: "number of valid HRV samples" |
| `VPHRVHeartsKey` | `hearts` | `rate` (CSV string) / `rrValue[]` | Array of strings; **each × 10 = one RR interval in ms**. Concatenate all minutes for the Lorentz plot |
| — | — | `hrvType` | HRV type |

Only 00:00–08:00 unless `hrvSupportAllDay`. `VPHRVPublicTool` gives a 0–100 HRV score and
10-minute rollups; `VPRRIntervalDataHRVHandle` builds Lorentz/Poincaré coordinates but needs
≥ 2000 RR points and a commercially unlocked SDK.

### Raw beat-by-beat RR stream (separate command)

`-[VPPeripheralBaseManage veepooSDK_readRRIntervalDataWithDayNumber:blockNumber:result:]`
returns `VPRRIntervalDataModel` objects, **one block per minute**, 1440 blocks a day, and the
ring keeps only **3 days**. Read incrementally by `blockNumber` to avoid re-pulling.

| Field | Meaning |
|---|---|
| `blockNumber` | Minute index within the day, from 1 |
| `date`, `time` | `yyyy-MM-dd`, `HH:mm:ss` |
| `dataStream` | 1 byte per beat. The demo converts with `60000 / (value × 20)` bpm, so the unit is **20 ms per count**; the demo treats 12…120 (240 ms…2.4 s) as valid |
| `dataConvertStream` | Same data, 2 bytes little-endian per beat (e.g. `0x6400` = 100) |

This is the closest thing to a raw physiological signal the standard SDK gives; it is what an
HRV-based apnea classifier (cyclic variation of heart rate) would consume.

## 7 · Tier 3: the 5-minute "origin" record

`+[VPDataBaseOperation veepooSDKGetOriginalDataWithDate:andTableID:]` returns a dictionary
keyed by `"HH:mm"` on a 5-minute grid (a gap means the ring recorded nothing or was off the
finger; never interpolate). Android: `OriginData` / `OriginData3` (288 per day max).

| iOS key | Android field | Meaning |
|---|---|---|
| `heartValue` | `rateValue` | Pulse rate for the 5 minutes (30–200) |
| `ppgs` | `ppgs` (IntArray[5]) | **Per-minute pulse rates** within the 5-minute bucket, from the green PPG. Not a waveform |
| `ecgs` | `ecgs` | Per-minute HR from electrodes; empty on a ring |
| `sportValue` | `sportValue` | Motion intensity 0–65535, 5 vendor bands |
| `stepValue`, `calValue`, `disValue` | same | Steps, kcal, km |
| `motionState` | `gesture` | Motion/wearing posture; needs `isSupportMotionState` |
| `stress`, `met` | `pressure`, `met` | Vendor stress index, MET |
| `diastolic`, `systolic` | `lowValue`, `highValue` | PPG BP estimate (not for apnea) |
| — | `wear` | Wear flag for the bucket |
| — | `resRates` (IntArray[5]) | **Per-minute respiration rate** |
| — | `sleepStates` (IntArray[6]) | Per-minute sleep state |
| — | `oxygens` | Per-minute SpO₂ |
| — | `apneaResults` | Per-minute apnea count |
| — | `hypoxiaTimes` | Per-minute hypoxia time |
| — | `cardiacLoads` | Per-minute cardiac load |
| — | `isHypoxias` | Per-minute apnea/hypoxia result |
| — | `corrects` | SpO₂ correction value (= iOS `Temp1`) |
| — | `tempOne`, `tempTwo` | Reserved |
| — | `baseTemperature`, `temperature` | Skin and estimated body temperature |

The Android `OriginData3` layout shows the protocol-3/5 record carries the whole apnea set
inside the 5-minute frame; on iOS the same bytes are split into the oxygen table (§5) by the
SDK. `veepooSDKGetOriginalChangeHalfHourDataWithDate:` is a 30-minute rollup and adds nothing.

## 8 · Tier 4: sleep staging to bound the analysis window

Precise sleep (`sleepType` 1 or 3): `veepooSDKGetAccurateSleepDataWithDate:` → `VPAccurateSleepModel`
per sleep segment.

| Field | Meaning |
|---|---|
| `sleepTime`, `wakeTime` | Segment bounds (analysis window) |
| `sleepLine` | Hex string, 2 bytes per **minute**; stage = top 3 bits (`value >> 13`): 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake. `parseSleepLine` returns `{index, type}`. KH-series lacks 2 and 3 |
| `onePointDuration` | Seconds per point (60) |
| `getUpTimes`, `getUpDuration` | Awakenings and awake minutes (arousal proxy) |
| `deepDuration`, `lightDuration`, `otherDuration` (REM), `sleepDuration` | Minutes |
| `insomniaTag/Score/Times/Duration/Record` | Insomnia flags |
| `sleepQuality`, `fallAsleepScore`, `deepScore`, `sleepEfficiencyScore`, `getUpScore`, `sleepTimeScore` | Vendor scores |
| `lastType`, `nextType` | 1 = stitch with previous/next segment |
| `accurateType` | 1 precise, 0 normal, 2 ZhongKe chip |

Legacy (`sleepType` 0): `veepooSDKGetSleepDataWithDate:` → `SLE_LINE` string, one char per
**5 minutes**, 0 light, 1 deep, 2 awake, plus `SLEEP_TIME`, `WAKE_TIME`, `WakeUpTime`.

## 9 · Tier 5: skin temperature every 5 minutes

`veepooSDKGetDeviceTemperatureDataWithDate:` → `month, day, hour, minute`, `value` (estimated
body °C), `OriginalValue` (skin °C). Useful only as a wear/illness covariate.

## 10 · Tier 6: raw PPG and accelerometer waveforms (customer-gated)

These exist in the SDK but each is tied to a specific Veepoo customer project. Whether the
CarePlix ring firmware answers any of them is **unknown until tested on hardware**.

| API | Signal | Gate |
|---|---|---|
| `ReceiveGreenLightData` block on `VPPeripheralBaseManage`, fed by `veepooSDKTestOxygenAndHeartStart:` | 50 Hz green PPG samples during a spot test | "special customization customers" |
| `veepooSDK_G08WProjectPPGSubscribe:` | PPG arrays, `type` 0 green / 1 red / 2 infrared | G08W project |
| `veepooSDK_JH58GetPPGAndAccelerationRawDataWithMeasurementMode:andTimestamp:` → `VPJH58PPGAccelerationModel { timestamp, ppgValueArray, accelerationArray<VPAccelerationModel{x,y,z int16}> }` | Stored green PPG + accel. Mode 1: 10 s every 15 min. Mode 2: 1 min every 5 min | JH58 project |
| `veepooSDK_JH58ActiveTestPPGAndAcceleration:` + `…Report:`, `veepooSDK_JH58ReqRealTimeTransmission:`, `veepooSDK_JH58MonitorRealTimeTransmissionPPGData:` / `…AccelerationData:` | Live per-second frames. Android `PPGSecondData`: green 100 Hz, 3-byte signed LE (300 B/s); accel 50 Hz, int16 x/y/z (300 B/s). Mode 3 real-time or breakpoint (device buffers 5 min across a BLE drop) | JH58 project |
| `veepooSDK_QX17IMUResultSubscribe:` → `VPQX17IMUModel { accelerometer, gyroscope, magnetometer, timestamp ms }` | Live IMU | QX17 project |
| `veepooSDKReadDisconnectOxygenDataWithLastReadTime:` → `VPOxygenDisconnectTestModel { y m d h m s, oxygen, heart }` | SpO₂/HR measured while disconnected | custom |
| `veepooSDKSettingAllDayOxygenTest:` | 24-hour SpO₂ instead of 00:00–07:00 | custom |

If the ring is a JH58-class device, Mode 2 (one minute of 100 Hz PPG + 50 Hz accel every five
minutes) plus Mode 3 real-time is enough to run our own desaturation and respiratory-effort
estimation. If not, we are limited to the per-minute derived values in §5–§7.

## 11 · Vendor-side apnea analysis already in the SDK

`VPOxygenAnalysisModel` (`initWithOneDayOxygens:` with the §5 array):

| Property | Meaning |
|---|---|
| `osahsResult` | −1 no result, 0 normal, 1 mild, 2 moderate, 3 severe (OSAHS grade) |
| `osahsResultDes` | Localised text |
| `frequentOccurrenceTimes`, `frequentOccurrenceValues` | Times at which apneas cluster, and counts |
| `aveOxygenValue`, `minOxygenValue` | 0 = no data |
| `aveRespirationRate`, `minRespirationRate`, `maxRespirationRate` | |
| `aveLowOxygenTime`, `maxLowOxygenTime` | |
| `aveCardiacLoad`, `maxCardiacLoad`, `minCardiacLoad` | |
| `aveSleepActivity` | |

Android `Spo2hOriginUtil(spList)`: `getApneaList()`, `getIsHypoxia()`, `getTenMinuteData(type)`,
`getOnedayDataArr(type)` (max/min/avg), `getDetailList(type, start)`; `ESpo2hDataType` =
`TYPE_SPO2H, TYPE_HEART, TYPE_SLEEP, TYPE_BREATH, TYPE_LOWSPO2H, TYPE_BEATH_BREAK, TYPE_HRV,
TYPE_SPO2H_MIN`. Ready-made UI: `VPOxygenCurveView`, `VPOxygenAnalysisSection*View`,
`VPOxygenDetailController`.

**Restriction:** the iOS API doc says SpO₂ is a "restricted function": without a commercial
unlock from Veepoo the oxygen query returns **only `OxygenValue`**, and `ApneaResult`,
`IsHypoxia`, `HypoxiaTime`, `Hypopnea`, `CardiacLoad`, `RespirationRate` come back empty.
Confirm with a real ring before designing around them.

## 12 · Device settings that must be on for a usable night

| Setting | iOS | Android |
|---|---|---|
| Nightly automatic SpO₂ | `veepooSDKSettingBaseFunctionType:VPSettingAutomaticOxygenTest` (1000), or `VPAutoMonitTestModel` type `VPAutoMonitTestTypeBloodOxygen` with `on`, `timeInterval`, start/end | `settingSpo2hAutoDetect(AllSetSetting(EAllSetType.SPO2H_NIGHT_AUTO_DETECT, 22,0, 8,0, …))` |
| Nightly HRV / Lorentz | `VPSettingAutomaticHRVTest`; `VPAutoMonitTestTypeHRV`, `VPAutoMonitTestTypeLorentz` | HRV auto switch |
| Automatic pulse (also gates precise sleep) | `VPSettingAutomaticHRTest`, `VPSettingAutomaticPPGTest` | `isOpenPPG` |
| Wear detection | `VPSettingWearDetection` | `wearDetectFunction` |
| Apnea vibration reminder | `veepooSDKSettingOxygenApneaRemind:settingMode:` with `VPOxygenApneaRemindModel { startH/M, endH/M, durationTime, remindTime, lowOxygenValue, defaultTime, state 1 on / 2 off }` | `BreathBreakRemindData { openStatus, minOxygen, remindTime, duringTime, start/end }` via `ISpo2hBreathBreakRemainListener` |
| Low-SpO₂ alarm | `VPSettingOxygenLowerRemind`; data alarm type 3 | |
| Skin temperature auto | `VPSettingAutomaticTemperatureTest` | |

## 13 · Daytime spot tests (for calibration, not for the night record)

| Test | iOS | States | Output |
|---|---|---|---|
| SpO₂ | `veepooSDKTestOxygenStart:` | `VPTestOxygenState` start · testing · **notWear** · deviceBusy · over · noFunction · calibration · calibrationComplete · invalid | `oxygenValue` % (calibration progress while calibrating) |
| Breathing rate | `veepooSDKTestBreathingRateStart:` | `VPTestBreathingRateState` start · testing · notWear · busy · over · complete · failure · noFunction | `breathingRateProgress` 0–100, `breathingRateValue` brpm (Android: 10–50 valid) |
| HRV | `veepooSDK_HRVTest:` | `VPTestHRVState` testing · alreadyStarted · lowPower · deviceBusy · notWear | `hrvValue` ms |
| Pulse | `veepooSDKTestHeartStart:` | `VPTestHeartState` | `heartValue` bpm |

## 14 · What to collect per night, minimum viable set

1. **Per minute, 00:00–07:00 (or all night if all-day SpO₂ is unlocked):** `Time`, `OxygenValue`,
   `HeartValue`, `RespirationRate` (drop 255), `SportValue`, `ApneaResult`, `IsHypoxia`,
   `HypoxiaTime`, `Hypopnea`, `CardiacLoad`, `HRV`, `Temp1`.
2. **Per minute:** `hrvValue` and the `hearts` RR list (×10 ms) from the HRV table; or the raw
   RR blocks (`dataStream`, 20 ms units) if the 3-day window is acceptable.
3. **Per 5 minutes:** `heartValue`, `ppgs[]`, `sportValue`, `motionState[]` for wear and arousal
   context; skin `OriginalValue`.
4. **Per segment:** `sleepTime`, `wakeTime`, `sleepLine` (per-minute stage) to restrict the
   apnea window to actual sleep and to count arousals (`getUpTimes`).
5. **Per night, from the SDK:** `VPOxygenAnalysisModel.osahsResult` and the `frequentOccurrence*`
   arrays, kept as the vendor's opinion beside our own.
6. **Raw waveforms only if the firmware answers the JH58 calls:** 100 Hz green PPG + 50 Hz accel.

## 15 · Open questions for Veepoo / bench

1. Is the CarePlix ring's SpO₂ path in restricted mode? If so, which of the §5 fields are
   populated, and what does the commercial unlock cost?
2. Which firmware project is the ring (JH58, G08W, QX17, other)? That decides whether any raw
   PPG/accel API in §10 works.
3. Units of `HypoxiaTime` and `CardiacLoad`, and the exact definition of `ApneaResult`
   (flag vs count per minute).
4. Does `veepooSDKSettingAllDayOxygenTest:` work on this firmware, to extend past 07:00?
5. Does `veepooSDK_readRRIntervalDataWithDayNumber:` return data, and is it 3 days on this ring?
6. Sampling interval of nightly SpO₂ on this firmware (the doc says per minute; older devices
   were every 10 minutes).
