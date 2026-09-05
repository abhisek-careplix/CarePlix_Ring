# 01 · Audit of the current ring experience

*What a user meets today, what is wrong with it, and the design debt each problem creates.*

The audit covers the shipping ring app as described by the team (tabs **Today · Sleep · Measure · Respi**, a search bar on Today, a four-field profile), the `ios/RingDiscovery` pairing layer in this repository, and the sibling CarePlix band app (`CardiacPro`) whose design system this redesign extends. Where the ring app's own screens were not in a repository we could read, the finding is stated as reported and marked *(reported)*.

## Summary verdict

The current app is a **data dump with tabs**. It shows what the vendor SDK happens to return, in the order the SDK returns it, with no point of view about what the user should do with it. A ring is worn 24 hours a day and looked at for about ninety seconds a day; the app has to earn those ninety seconds with one clear answer, and today it does not try.

| # | Finding | Severity | Journey it breaks |
|---|---|---|---|
| A1 | **Profile capture is thin and unexplained** *(reported)*: birth year, sex, height, weight, no reason given, no wear-hand, no bedtime, no goal. | High | First launch, every score afterwards |
| A2 | **A search bar on Today with nothing to search** *(reported)*. It occupies the most valuable pixels on the most valuable screen and leads nowhere. | High | Morning check-in |
| A3 | **No battery anywhere** *(reported)*. The SDK exposes percentage, charging state and low-battery flag (`veepooSDKReadDeviceBatteryAndChargeInfo`); the app shows none. A ring that dies at 2 a.m. silently loses the night, which is the whole product. | Critical | Every night |
| A4 | **No sync model**. There is no visible "last synced", no pull-to-sync, no in-progress state, so the user cannot tell "no data" from "not yet fetched". | High | Morning, after a disconnect |
| A5 | **Tabs mirror SDK test types, not user questions**. "Measure" and "Respi" are vendor commands (`veepooSDKTestHeartStart`, `veepooSDKTestBreathingRateStart`). Users ask "how did I sleep?" and "how am I doing?", not "run a respiration test". | High | Information architecture |
| A6 | **No baseline, no interpretation**. Every number is shown as an absolute with no "your usual". A resting heart rate of 58 means nothing without the user's own range. | High | Today, Sleep, Measure |
| A7 | **Pairing is a spinner that can hang forever** (documented in `ios/RingDiscovery/README.md`, root cause #3). Fixed in the discovery layer, but the UI contract for `.searching / .found / .foundNothing / .blocked / .paired` still needs screens. | Critical | Pairing |
| A8 | **Capabilities are not gated**. Cards for features the ring does not have (blood pressure, ECG, glucose) either render empty or are hidden ad hoc. The vendor model exposes every flag (`oxygenType`, `hrvType`, `resRateType`, `temperatureType`, `sleepType`) after handshake. | Medium | Measure, Today |
| A9 | **No off-body / not-worn state**. `VPTestHeartStateNotWear` and `wearMonitoringState` exist; the UI cannot say "the ring wasn't on your finger last night". | High | Sleep, Measure |
| A10 | **Dark-only, hard-coded colours, no Dynamic Type, no VoiceOver labels** *(reported)*. The band app already solved this with an adaptive, WCAG-measured token set; the ring app should inherit it. | Medium | Accessibility |
| A11 | **Nothing happens between the tabs**. No notifications, no bedtime reminder, no "charge before bed", no morning summary, so the app is only ever opened by curiosity. | High | Retention |

## What the user actually experiences (as-is journey)

1. **Install → profile.** Four pickers, no explanation of why. Nothing about which hand or finger the ring goes on, nothing about sleep goal. The user learns nothing and we learn nothing usable for interpretation.
2. **Pair.** "Looking for your ring" spinner. If the scan finds nothing, the spinner stays and the retry button is disabled. Force-quit.
3. **Today.** A search field, then a grid of raw values: HR, SpO₂, steps, temperature. No headline, no comparison, no ring state.
4. **Sleep.** Vendor sleep fields rendered as numbers (`deepDuration`, `lightDuration`, `sleepQuality`). No hypnogram, no bedtime/wake, no overnight vitals, no "you weren't wearing it".
5. **Measure.** A list of test buttons. Tap → vendor state codes surface as progress. Results vanish into a list with no trend.
6. **Respi.** A single breathing-rate test button. No overnight respiratory rate, no context, no guided breathing.
7. **Night.** Battery dies or the ring disconnects. No warning. Morning shows an empty Sleep tab with no explanation.

## Design debt, stated as principles we violated

- **Answer before evidence.** The first screen must answer "how am I?" in one glance, then let the user drill into why.
- **Every number needs a "usual".** Absolute values are for clinicians; personal ranges are for people.
- **The ring is a character in the story.** Battery, wear state, sync and firmware are part of the daily narrative, not settings.
- **Sensors define the menu.** Only show what the connected ring can do; say plainly what it cannot.
- **Silence is a bug.** Empty states must say *why* (not worn, not synced, ring off, battery flat) and what to do next.
- **Nothing is measured "at" the user.** Spot tests are for moments the user chooses; the nightly story is passive and automatic.

The rest of this folder is the fix.
