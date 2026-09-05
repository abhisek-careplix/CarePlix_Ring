# 03 · Sensor & vendor-SDK data map

*Everything the ring can tell us, taken from the shipped `VeepooBleSDK` headers (`VPPeripheralBaseManage.h`, `VPDataBaseOperation.h`, `VPPeripheralModel.h`, `VPPublicDefine.h`, `VPAccurateSleepModel.h`, `VPAutoMonitTestModel.h`), and where each datum lives in the redesigned app.*

The CarePlix ring is a Veepoo-platform device with an optical (PPG) front end, an accelerometer and a skin thermistor. There is no ECG electrode pair, no bio-impedance, no electrochemical sensor. The SDK model advertises far more than the hardware can do; **capability flags decide what the app shows, and the physics decides what we will never show** (see the last section).

## 1 · Capability discovery (after handshake)

All of these populate on `VPPeripheralModel` only after `VPDeviceConnectStateVerifyPasswordSuccess`. They are `0` during scanning. The app must cache the last-known set per ring so a transient BLE drop does not blank the UI (the band app's P0 bug).

| Flag | Meaning | Gates |
|---|---|---|
| `heartRateType` / `deviceFuctionData` HR bit | PPG heart rate | Everything |
| `sleepType` (0 normal, 1/3 precise) | Precise sleep with REM/insomnia stages | Sleep hypnogram detail |
| `hrvType` ≠ 0, `hrvSupportAllDay`, `isSupportHRVTest` | Nightly HRV (00:00–08:00 or all day), manual HRV | Recovery, HRV card, HRV spot test |
| `oxygenType` ≠ 0, `oxygenAutoDetectType` | SpO₂ spot + nightly auto | SpO₂ card, spot test, overnight oxygen line |
| `resRateType` = 1 | Breathing-rate spot test | Breathe tab spot test |
| `temperatureType` ≠ 0 | Skin temperature every 5 min | Temperature deviation card |
| `stressType`, `fatigueLevelType` | Vendor stress / fatigue index | Stress card (labelled "from heartbeat timing") |
| `bloodPressureType`, `isSupportBPTest`, `pttState` | PPG blood-pressure *estimate* | **Hidden** (see policy) |
| `ecgType` | ECG | **Hidden** on ring (no electrodes) |
| `bloodGlucoseType`, `bloodAnalysisType`, `bodyCompositionType`, `gsrType`, `emotionType` | Non-physical for this hardware | **Never shown** |
| `wearMonitoringState`, `VPTest*StateNotWear` | Wear detection | "Not worn" states |
| `lowPowerType`, `lowPowerModel` | Low-power mode | Ring sheet power mode |
| `runningSaveTimes`, `runningType` | Sport modes stored | Activity workouts list |
| `saveDays` | Days of history the ring retains offline | Sync copy ("ring holds 7 days") |

## 2 · Live device state

| Call | Returns | Shown in |
|---|---|---|
| `veepooSDKReadDeviceBatteryAndChargeInfo` | `isPercent`, `chargeState` (normal / charging), `percenTypeIsLowBat`, `battery` (0–100 or 0–4 bars) | Ring accessory, Ring sheet, bedtime notification |
| `vpBleConnectStateChangeBlock` | connected / disconnected / verified / needsPasscode / timeout / awaitingConfirmation | Ring accessory, pairing screens |
| `veepooSDKReadDeviceVersion` / `deviceVersion`, `deviceNumber` | Firmware, model | Ring sheet, DFU flow |
| `veepooSDKSynchronousPersonalInformation:` (`VPSyncPersonalInfo`: weight, age, sex, targetStep, targetSleepDuration; stature via the long form) | Writes profile to the ring | Profile onboarding → written on pair and on edit |
| `veepooSDKReadAutoMonitSwitchInfo` / `SetAutoMonitSwitch` (`VPAutoMonitTestModel`: type HR/BP/Glucose/Stress/SpO₂/Temp/Lorentz/HRV, `on`, `timeInterval`, start/end time) | Passive monitoring schedule | Ring sheet → "What your ring measures overnight" |
| `veepooSDKSettingBaseFunctionType:` (`VPSettingAutomaticHRTest`, `AutomaticOxygenTest` (night), `AutomaticHRVTest`, `AutomaticTemperatureTest`, `Stress`, `DisconnectRemind`, `OxygenLowerRemind`) | Legacy switches | Same sheet |
| `veepooSDKPowerOffDevice`, `veepooSDKResetDeviceData` | Power off, factory reset | Ring sheet → danger zone |

## 3 · Passive history (synced from ring storage, queried by date + MAC)

| Call | Cadence & shape | Screen |
|---|---|---|
| `veepooSDKGetOriginalDataWithDate` | Every 5 min: `heartValue`, `stepValue`, `calValue`, `disValue`, `sportValue`, `stress`, `met`, `ppgs[]`, `motionState[]` | Today (HR through the day, steps), Measure (HR trend), Sleep (overnight HR) |
| `veepooSDKGetOriginalChangeHalfHourData` | 30-min rollups | Today activity bars |
| `veepooSDKGetStepDataWithDate` | Day totals: steps, distance, calories | Today activity |
| `veepooSDKGetAccurateSleepDataWithDate` → `VPAccurateSleepModel` | Per sleep segment: `sleepTime`, `wakeTime`, `sleepDuration`, `deepDuration`, `lightDuration`, `getUpDuration`, `otherDuration` (REM on precise), `getUpTimes`, `sleepQuality` (score), `fallAsleepScore`, `deepScore`, `sleepEfficiencyScore`, `getUpScore`, `sleepTimeScore`, `insomniaTag/Score/Times/Duration`, `sleepLine` (per-minute stage: 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake; KH series lacks 2 & 3), `exitSleepMode`, `accurateType` | Sleep (hypnogram, stages, score contributors, awakenings) |
| `veepooSDKGetSleepDataWithDate` | Legacy 5-min `SLE_LINE` (0 light, 1 deep, 2 awake) | Fallback hypnogram |
| `veepooSDKGetDeviceHrvDataWithDate` | Per minute: `VPHRVTimeKey`, `VPHRVValueKey`, `VPHRVHeartsKey` (RR intervals ×10 ms) | Sleep overnight HRV, Recovery, Lorentz (Measure → HRV detail) |
| `veepooSDKGetDeviceOxygenDataWithDate` | Nightly SpO₂ series (typically every 10 min 00:00–08:00), plus apnea/low events on capable firmware | Sleep overnight SpO₂, Breathe (oxygen during sleep) |
| `veepooSDKGetDeviceTemperatureDataWithDate` | Every 5 min: `Value` (est. body), `OriginalValue` (skin) | Sleep overnight temperature deviation |
| `veepooSDKGetDeviceRunningDataWithDate` | Workouts: mode, duration, steps, distance, kcal, avg HR | Today activity → Workouts |
| `veepooSDKGetBloodDataWithDate` | Hourly BP estimates | **Not shown** |

Origin data is the backbone: the SDK notes that a gap in the 5-minute grid means the ring was not read (or not worn); the app must render gaps as gaps, never interpolate across them.

## 4 · Spot measurements (user-initiated)

| Call | States | Result | Screen |
|---|---|---|---|
| `veepooSDKTestHeartStart:` | start · testing (live value) · **notWear** · deviceBusy · over | `heartValue` bpm | Measure → Heart rate |
| `veepooSDKTestOxygenStart:` / `TestOxygenAndHeartStart:` | start · testing · notWear · busy · over · noFunction · **calibration** · calibrationComplete · invalid | `oxygenValue` % (+ HR) | Measure → Blood oxygen |
| `veepooSDKTestBreathingRateStart:` | start · testing (`progress` 0–100) · notWear · busy · over · complete · failure · noFunction | `breathingRateValue` brpm | Breathe → Breathing rate |
| `veepooSDKTestHRVStart` (via `VPManualHRVModel`) | testing · alreadyStarted · **lowPower** · busy · notWear | `hrvArray` | Measure → HRV |
| `veepooSDKTestStress` (`VPDeviceStressTestState`) | noFunction · busy · over · lowPower · notWear · complete | `value` | Measure → Stress |
| Temperature (`VPTemperatureTestState`) | unsupported · open · close · notWear | `bodyTemp`, `origTemp` (×0.1 °C) | Measure → Skin temperature |
| Manual history: `VPManualMeasurementDataModel` (`VPManualTestDataType` bitmask) | Timestamped past spot tests stored on ring | Measure → "Recent" list |

Every spot test shares the same UI state machine: **Preparing → Measuring (progress) → Result** with three explicit exits: *Not on finger*, *Ring busy*, *Battery too low*. Timeouts are ours (30 s HR/SpO₂, 60 s breathing/HRV/stress); the SDK does not always finish.

## 5 · Derived metrics (computed in the app, never by the ring)

| Metric | Inputs | Rule |
|---|---|---|
| **Readiness** (0–100) | Overnight HRV vs 14-night baseline, resting HR vs baseline, sleep score, skin-temp deviation, breathing-rate deviation | Abstains until 7 nights; each contributor shown with its own state |
| **Sleep score** | Vendor `sleepQuality` blended with duration vs need, efficiency, awakenings, regularity | Vendor score shown as "ring's estimate" until 7 nights of our own |
| **Typical range** per vital | Rolling 14 nights, 10th–90th percentile | Apple-style "Typical / Outside typical" |
| **Sleep need & debt** | User target (`targetSleepDuration`) vs 7-night rolling total | Oura-style |
| **Resting HR** | Lowest stable 5-min mean during main sleep | Never a daytime minimum |
| **Stress index (day)** | Vendor `stress` in origin data, smoothed | Labelled "from heartbeat timing", wellness only |
| **Battery forecast** | Slope of last 24 h of battery reads | "About 3 days left" / "Charge before bed" |

## 6 · HealthKit write-through

Sleep analysis (in-bed, asleep by stage), heart rate (5-min), resting heart rate, HRV (SDNN from RR where the SDK gives RR), SpO₂, respiratory rate, body temperature (as wrist/skin), step count, distance, active energy, workouts. Read-through: none required for v1.

## 7 · Policy: what we do not show, and why

- **Blood pressure, glucose, blood components, body composition, GSR, emotion, fatigue "disease" panels** — not physically measurable with PPG + accelerometer + thermistor at consumer quality, or regulated. Naming them turns a wellness ring into an unapproved diagnostic. Hidden regardless of vendor flag.
- **ECG** — no electrodes on a ring; hidden.
- **Absolute body temperature** — a finger thermistor gives skin temperature; we show **deviation from the user's own baseline** only.
- **Sleep apnea AHI** — we may show "breathing disturbances (low-oxygen events)" as a count with a wellness label, never a diagnosis.

Everything shown carries an information-only tag, and every value carries provenance (sensor, time, and "vs your usual").
