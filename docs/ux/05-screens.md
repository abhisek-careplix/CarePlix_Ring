# 05 · Screens

*Information architecture, then every screen top-to-bottom with its data source, states and copy. Component names refer to `06-design-system.md`.*

## Information architecture

```
Tab bar (Liquid Glass, 4 tabs, no search role)
├── Today      sun.horizon      the answer + evidence, time-aware hero
├── Sleep      moon             last night, nights list, trends
├── Measure    waveform.path    now: HR through the day + spot tests + recent
└── Breathe    wind             breathing rate (overnight + now), oxygen, guided breathing
Tab-bar accessory (persists on every tab)
└── Ring status  ●  LOOP-E5FF · 64 % · Synced 6 min ago   → tap opens Ring sheet
Sheets
├── Ring        battery + forecast, connection, what it measures overnight, firmware, power mode, unpair
├── Profile     everything asked in onboarding, editable, re-synced to the ring on save
├── Metric detail  one per vital (day / week / month, typical band, how it was measured)
└── Measure session  one per spot test
```

Why these four: they map to the user's questions (*how am I? how did I sleep? how am I right now? how am I breathing / can I calm down?*), keep the team's existing vocabulary (Today · Sleep · Measure · Respi → Breathe), and drop the search bar because there is nothing to search. "Respi" becomes **Breathe** because the tab holds both the measurement and the action.

## Global chrome

- **Large title** with the date under it on Today ("Today · Fri 5 Sep"). Other tabs: plain large titles.
- **Ring accessory** (`RingStatusBar`): 44 pt bar above the tab bar. Left: ring glyph with a state colour dot. Middle: name · battery (percent + glyph; bars when the ring reports 0–4). Right: sync state ("Synced 6 min ago" / "Syncing…" with hairline progress / "Not connected" / "Charging 71 %" / "Bluetooth off"). Tap → Ring sheet. Long-press → "Sync now".
- **Pull to refresh** on every tab triggers a sync.
- **Info-only tag** (`WellnessTag`) on every score and vital detail.

## Today

Order is time-aware; the hero is the only element that changes.

1. **Header**: "Good morning, Aisha" (name from profile, optional) · date.
2. **Hero card** (`HeroCard`), one of:
   - *Morning (wake → 12:00)*: **Readiness ring** (hero size, 64 pt numeral) + one sentence built from contributors. Contributors row: HRV ↑ · RHR = · Sleep ✓ · Temp = (state chips).
   - *Afternoon (12:00 → bedtime − 3 h)*: **Stress now** (from origin `stress` smoothed) with a "Breathe 3 min" button, or **Activity** if steps are far from goal.
   - *Evening (bedtime − 3 h → bedtime)*: **Tonight**: bedtime target, ring battery with forecast, "Charge now" when needed, wind-down breathing.
   - *Learning (< 7 nights)*: "Learning your usual · night 3 of 7" with a breathing ring and what appears when.
   - *No night*: "No night recorded" with the reason (not worn / battery ran out at 02:14 / not synced) and one action.
3. **Score row** (`ScoreShortcutRow`): Readiness · Sleep · Activity, medium rings, tap → tab.
4. **Overnight vitals** (`VitalStrip`, 2×3 grid of `VitalTile`): Resting HR · HRV · SpO₂ · Breathing rate · Skin temp Δ · Sleep duration. Each tile: title, value + unit, state chip (*Typical* / *Outside typical* / *Learning*), 7-night sparkline. Capability-gated.
5. **Activity** (`ActivityCard`): steps vs goal as a bar, distance, active kcal, 30-min bars for the day, workouts row if any.
6. **Timeline** (`DayTimeline`): sync events, spot tests, sleep segments, charging, with clock labels. This replaces the search bar's real estate with the day's actual story.
7. **Weekly card** (Sundays or on demand).

States: syncing (skeletons), unpaired (a single "Pair your ring" card replaces 2–6), Bluetooth off (banner under the header).

## Sleep

1. **Night selector**: horizontal 14-night strip of mini bars (duration, coloured by score), today at the right; swipe to change night.
2. **Hero**: Sleep score ring (hero) + "7 h 42 m · 23:12 → 06:54". Sentence: "Solid night. More deep sleep than usual, one long awakening at 03:20."
3. **Hypnogram** (`Hypnogram`): Awake / REM / Light / Deep lanes from `sleepLine`, gaps rendered as gaps, battery-loss marker if the ring died. Time axis every hour.
4. **Stages** (`StageBars`): four horizontal bars with duration and share vs the user's usual share.
5. **Contributors** (`ContributorList`): Duration vs need · Efficiency · Awakenings (`getUpTimes`) · Time to fall asleep (`fallAsleepScore`) · Regularity (bedtime variance over 7 nights). Each with a state chip and a one-line reading.
6. **Overnight vitals** (`OvernightVitalsList`): lowest HR line, HRV line, SpO₂ line with low-event markers, breathing rate, skin temp Δ. Each row shows the line, the night's value, and the typical band.
7. **Sleep debt** (`SleepDebtCard`): need vs 7-night total, "1 h 10 m short this week".
8. **Not worn / partial** states as full-height cards with the wear illustration.

## Measure

1. **Today's heart rate** (`HeartRateDayChart`): 5-min line 00:00 → now, resting band, spot tests as dots, gaps as gaps. Value pill follows the scrubber.
2. **Measure now** (`MeasureGrid`): tiles for Heart rate · Blood oxygen · HRV · Stress · Skin temperature, gated by capability; disabled with reason when the ring is not connected, on charger, or below 15 %.
3. **Recent** (`RecentMeasurementsList`): last 20 spot tests with value, state and time; tap → detail.
4. **Trends** shortcuts: RHR · HRV · SpO₂ 30-day.

**Measure session sheet** (`MeasureSessionSheet`): title, instruction ("Hold still. Keep your hand relaxed."), 30/60 s progress ring with live value (HR only), then result with state chip and typical band, Save / Discard. Exits: Not on finger · Ring busy · Battery too low · Timed out, each with its own copy and a retry.

## Breathe

1. **Overnight breathing rate** (`BreathHero`): last night's mean brpm, typical band, 14-night sparkline, sentence ("Steady, 14 breaths a minute, within your usual").
2. **Measure now** tile (breathing rate spot test, 60 s).
3. **Guided breathing** (`BreathingGuide`): 1 / 3 / 5 min chips, expanding circle with haptics, HR before/after when worn.
4. **Overnight oxygen** (`OxygenNightCard`): SpO₂ line, lowest value, count of dips below 90 % labelled "breathing disturbances (wellness estimate)".

## Ring sheet

1. **Header**: ring illustration in the chosen finish, name, "Connected" dot, firmware.
2. **Battery card** (`BatteryCard`): large percent, ring-shaped gauge, forecast ("About 3 nights"), charging state, "Charge before bed" tip, a 7-day battery history line.
3. **Sync**: last sync time, "Sync now", "Ring keeps 7 days of data when away from your phone".
4. **What your ring measures overnight** (`MonitoringSchedule`): toggles bound to `VPAutoMonitTestModel` (Heart rate · HRV · Blood oxygen · Skin temperature · Stress) with interval and window, each with a battery-cost hint.
5. **Wear**: hand and finger from profile, edit.
6. **Notifications**: the five in `04-journeys.md`.
7. **Power mode** (`lowPowerModel`).
8. **Danger zone**: Restart ring, Forget ring, Reset data (confirm sheet).

## Profile sheet

All onboarding answers as editable rows; saving writes `VPSyncPersonalInfo` and the long-form call with stature. Sleep goal and bedtime feed Sleep Debt and the evening hero.

## Copy principles

- Present tense, second person, no exclamation marks.
- State chips are exactly: **Typical · Outside typical · Learning · Not measured**. Scores use **Optimal · Good · Fair · Low · Not enough signal** (shared with the band app).
- Every empty state has a reason and one verb.
- Never name a disease. "Breathing disturbances", not "apnea". "Skin temperature change", not "fever".
