# 02 · Research: what world-class wearables do, and what we take from each

*Sources are the products' own documentation and 2025–2026 coverage of their redesigns; see the reference list at the end. We do not copy any product's proprietary UI; we adopt the patterns that have become category conventions and design our own expression of them.*

## Oura (ring; the category reference)

**Structure.** Oura's late-2025 redesign collapsed five tabs into three: **Today**, **Vitals**, **My Health**. Today opens with score shortcuts (Sleep, Readiness, Activity, Heart Rate, Daytime Stress, Cycle) in a horizontal row, then a **"one big thing"** card: the single most relevant insight for the moment (readiness in the morning, stress mid-afternoon, wind-down in the evening). Vitals is the deep-dive list with each metric against the wearer's own range. My Health holds long-horizon trends (Sleep Debt, Cardiovascular Age, Resilience).

**Patterns worth adopting.**
- *One big thing.* The hero of Today changes through the day. Morning: Readiness. Afternoon: stress or activity. Evening: bedtime guidance and "charge your ring".
- *Score row as shortcuts.* Small rings, tap to drill. Scores are only shown once a baseline exists; before that the ring shows progress toward it.
- *Personal range on every vital.* A band showing "your usual" behind the value, and a plain-language state (Optimal / Good / Pay attention).
- *Sleep Debt* as a single comparison of sleep need vs total sleep across nights.
- *Ring as a top-of-screen presence.* Tapping the ring at the top of Home shows battery and status; battery notifications 2–3 hours before bedtime and on charge complete.
- *Tags/notes* to annotate a day so the user can correlate.

**What we do not adopt.** Oura's subscription paywall, the AI advisor, cycle tracking (sensor support unknown for our ring), and the Oura visual identity.

## WHOOP (band; the "data-dense but simple" reference)

**Structure.** Overview screen of tiles: Recovery, Strain, Sleep, Health Monitor, Stress Monitor. Each tile is a doorway, not a destination. Recovery is a single 0–100 % with a colour (green/yellow/red). Health Monitor lists five vitals (RHR, HRV, respiratory rate, SpO₂, skin temp) each against a personal range, "typical" or "outside typical".

**Patterns worth adopting.**
- *Tiles are doorways.* Each tile states one number, one state word, one trend glyph. Everything else is behind the tap.
- *Health Monitor.* Five overnight vitals with typical-range bands is exactly the data set our ring produces passively overnight (HR, HRV, SpO₂, breathing rate, skin temperature).
- *Stress Monitor* from HRV with a "breathe" action attached; WHOOP added guided breathwork sessions in 2026.
- *Journal* to correlate behaviours with recovery.

**What we do not adopt.** Strain as a training-pressure target (our audience is health-first), teams/community, WHOOP Age.

## Apple Watch Vitals + iPhone Health (the honesty reference)

**Structure.** Vitals shows five overnight metrics: heart rate, respiratory rate, wrist temperature, blood oxygen, sleep duration. Each has a **typical range** built from seven nights. Values inside the range are blue and the overall status reads "Typical"; outliers are pink. A notification fires only when **two or more** metrics are out of range, with contextual reasons (illness, alcohol, altitude, medication). Health app uses Highlights (auto-generated cards), consistent chart grammar (bar for duration, line for continuous), and never shows a fabricated number.

**Patterns worth adopting.**
- *Typical range, not thresholds.* Seven nights to establish; outliers are stated as "outside your typical range", never diagnosed.
- *Multi-metric gating for alerts.* One outlier is noise; two is a signal.
- *Wrist/skin temperature as deviation from baseline*, never as an absolute.
- *Chart grammar.* Duration = stacked bars, continuous = line with range band, discrete tests = dots.
- *Honesty copy.* "Not enough data", "Learning your range · night 4 of 7".

## iPhone / iOS 26 platform conventions

- **Liquid Glass tab bar**: floating, pill-shaped, few top-level destinations; a **search role** tab is an island on the right and should exist only when there is something to search. Our answer to the empty search bar is to delete it.
- **Tab bar bottom accessory**: an official shelf above the tabs that persists across tabs. Apple uses it for Now Playing; we use it for **ring status** (connection · battery · last sync), which is the single most requested missing element.
- **Large titles, pull-to-refresh, sheets with detents, SF Symbols, Dynamic Type, VoiceOver, Reduce Motion, Increase Contrast** are table stakes.
- **HealthKit write-through** (sleep analysis, heart rate, SpO₂, respiratory rate, body temperature, steps) so the ring's data appears in Health like every other wearable.

## Other rings (Ultrahuman, RingConn, Samsung)

- Ultrahuman: "power modes" and battery estimate in days, onboarding asks wear hand and finger, bedtime and wake window.
- RingConn: subscription-free, battery percentage in the app header, sleep apnea monitoring trend.
- Samsung Galaxy Ring: Energy Score, auto workout detection, "Ring off finger" reminders.

Common ground across all three: **battery in the header, wear guidance in onboarding, one composite score, and an overnight vitals list against personal ranges.**

## Principles we carry into the design

1. **One big thing, then the evidence.** Today opens with a single time-aware hero.
2. **Every vital has a "usual".** Seven nights to learn, stated on screen until then.
3. **Ring status is ambient.** A persistent accessory above the tab bar: connected · 64 % · synced 6 min ago. Tap for the Ring sheet.
4. **Sensors define the menu.** Cards and tests appear only for capabilities the connected ring reports.
5. **Empty states explain.** Not worn, not synced, battery flat, ring off — each with one action.
6. **Chart grammar is fixed.** Bars for duration, line + band for continuous, dots for spot tests, hypnogram for stages.
7. **Calm technology.** Breathing pulses instead of spinners; one notification per event class; no streaks or guilt.
8. **Honesty by construction.** Abstain with a reason rather than fabricate; label wellness-only.

## References

- Oura, "Introducing the New Oura App Design" (Pulse blog, Oct 2025) and "Sleep Debt" support article.
- TechCrunch, "Oura launches redesigned app and cumulative stress feature" (Oct 2025).
- Oura Member Care, "Ring Battery Tips", "Managing Your Notifications", "Set Up the Oura App".
- WHOOP press centre, "WHOOP unveils 5.0 and MG" (May 2025); 925 Studios, "WHOOP Design Breakdown".
- Apple Support, "Track your overnight vitals with Apple Watch" (Vitals app, unchanged in watchOS 26).
- Apple Human Interface Guidelines, iOS 26 tab bars (search role, bottom accessory); Donny Wals, "Exploring tab bars on iOS 26 with Liquid Glass".
- Ultrahuman blog, "Getting started with the Ring AIR"; RingConn quick-start guides.
