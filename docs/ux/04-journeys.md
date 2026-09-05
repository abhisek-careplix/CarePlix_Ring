# 04 · Journeys

*Each journey is written as the user lives it, with the screen, the data source and the emotional intent at each step. Screens are specified in `05-screens.md`.*

## J1 · First launch → first night (the only onboarding that matters)

Goal: the ring is on the right finger, charged, paired, and the user knows what will appear tomorrow morning.

| Step | Screen | What happens | Why |
|---|---|---|---|
| 1 | **Welcome** | Three cards: *Sleep · Recovery · Vitals*. One line each. "Get started". Skip allowed. | Set the frame: this ring is about nights, not workouts. |
| 2 | **About you** (one question per screen) | Birth date → sex for ranges (with "prefer not to say" → neutral model) → height → weight → **wear hand + finger** (index / middle / ring, left / right) → **usual bedtime & wake time** → **sleep goal** (default 7 h 30). Each question carries a one-sentence reason. Units toggle inline. | Every answer is used: age/sex/height/weight → `veepooSDKSynchronousPersonalInformation`; hand/finger → wear-detection copy and support; bedtime → "charge before bed" timing and the evening hero; goal → Sleep Debt. |
| 3 | **Permissions** | Bluetooth (required, explained), Notifications (recommended: "one message at bedtime if your ring needs charging, one when your night is ready"), Health (optional write-through). Each is a card with the exact wording of what we will and will not do. | Consent is a design surface, not a system dialog. |
| 4 | **Pairing** | "Take the ring off the charger and hold it near your phone." Single phase at a time: Searching (breathing ring, 15 s deadline) → Found (list strongest-first, `LOOP-XXXX`) → Connecting → **Paired**: the ring's first heartbeat animates into the brand ring, battery reads immediately (round-trip proof). Failure states are specific: Bluetooth off → Settings link; nothing found → "Is it on the charger? Try again" with an **enabled** button; needs passcode → 4-digit prompt. | Contract from `ios/RingDiscovery`: one phase enum, never spinner + error together, retry never gated. |
| 5 | **Fit & wear** | Illustration of the sensor bumps facing the palm side, "snug but not tight", "wear tonight". Battery card: "64 % · enough for about 3 nights". | Fit determines every night's data quality. |
| 6 | **Today (day 0)** | Hero: "Your first night starts tonight." Timeline: *Tonight · sleep with the ring · Tomorrow 7:00 · your first Sleep page*. Score row shows "Learning · night 0 of 7". Ring accessory shows connected + battery. | Anticipation instead of an empty dashboard. |

## J2 · Morning check-in (the daily habit, 60–90 seconds)

1. **Sync.** App foregrounds → auto-connect → sync last night. Accessory shows *Syncing…* with a progress hairline; the Today hero shows a shimmer skeleton, never stale numbers.
2. **Today hero = Readiness** (once 7 nights exist) with one sentence: "Recovered. HRV above your usual, resting heart rate steady." Below: Sleep score, Sleep duration vs goal, and the **overnight vitals strip** (RHR · HRV · SpO₂ · Breathing · Temp Δ), each with *Typical* or *Outside typical*.
3. **Tap Sleep** → last night: bedtime/wake, hypnogram, stages bars, awakenings, overnight vitals lines, "how this compares to your usual".
4. **Ring accessory**: 61 % · Synced just now. Nothing else to do.

Failure branches, all designed:
- Ring not worn overnight → Sleep shows the **Not worn** state ("Your ring wasn't on your finger between 23:10 and 06:40") with the wear diagram; Today hero becomes "No night recorded".
- Ring battery died at 02:14 → Sleep shows partial night with a marker at the point of loss; Today hero: "Your ring ran out at 2:14. Charge it now and tonight is covered."
- Ring not synced (phone was off) → Today shows "Last night is still on your ring" with a Sync button; ring retains `saveDays` days.

## J3 · Midday "how am I now?" (Measure)

1. Open **Measure**. Top: today's HR line from origin data (5-min), with resting HR band. Below: **Measure now** grid of capability-gated tiles: Heart rate · Blood oxygen · HRV · Stress · Skin temperature.
2. Tap Heart rate → sheet: "Hold still for 30 seconds" → live value with a breathing pulse → Result: 72 bpm · "In your daytime range" → Save / Discard. If `notWear`: "Put the ring on and hold still" with retry. If `lowPower`: "Battery too low for this test (12 %)".
3. Result appends to **Recent** list and to the HR chart as a dot.

## J4 · Breathe (respiration, calm)

1. Top: **Overnight breathing rate** from last night (from HRV/SpO₂-capable nights), value + typical range + 14-night sparkline.
2. **Breathing rate now** spot test (`resRateType`): 60 s, progress ring, result in brpm.
3. **Guided breathing** (app-side, no sensor needed): 1 / 3 / 5-minute box breathing with haptics; if the ring is worn, HR before/after is shown as "Heart rate settled from 78 to 66".
4. Overnight oxygen line and low-oxygen event count live here too, labelled "breathing disturbances" (wellness).

## J5 · Evening wind-down and battery

- 2–3 h before the user's bedtime: if battery < 30 % (or forecast < 1 night), one notification: "Charge your ring for 40 minutes before bed." Today hero switches to a **Tonight** card: bedtime target, "ring 24 % · charge now", and a wind-down breathing shortcut.
- Charging: accessory shows a charging glyph and percent; on ≥ 80 % a notification "Ready for tonight" (only if the user enabled it).
- Ring off finger on charger → accessory "On charger".

## J6 · Disconnection and reconnection

- Out of range: accessory goes to *Not connected · last sync 14:02*; no modal. Ring keeps recording (`saveDays`).
- Back in range: auto-reconnect (`veepooSDKSelfScanConnectDevice` path), sync, accessory returns to *Connected*.
- Bluetooth off: accessory *Bluetooth is off* → tap → Settings deep link.
- Ring forgotten/reset: Ring sheet → "Pair a different ring" runs J1 step 4 only.

## J7 · Weekly review (My Trends, inside Today)

Sunday evening card on Today: 7-night sleep bars vs need, readiness line, resting HR and HRV lines, "3 nights outside your typical range" if any. Tappable into 14/30/90-day ranges. Exportable as a PDF later.

## Notification policy (one per event class, all opt-in after the first)

| Event | Timing | Copy |
|---|---|---|
| Night ready | On first sync after wake | "Your night is ready · Sleep 82" |
| Charge before bed | Bedtime − 2.5 h, battery < 30 % | "Charge your ring for about 40 min before bed" |
| Charged | ≥ 80 % while charging | "Ring charged · ready for tonight" |
| Not worn | Bedtime + 1 h, no wear signal | "Wearing your ring tonight? It's on the charger." |
| Vitals outside typical | Morning, ≥ 2 metrics out | "Two of your overnight vitals were outside your typical range" |
