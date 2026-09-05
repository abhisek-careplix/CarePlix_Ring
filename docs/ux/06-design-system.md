# 06 · Design system for the ring app

*Extends the CarePlix band design system (`CardiacPro/UI/Design/Theme.swift`, `Typography.swift`, `Motion.swift`) so the two products read as one family. Values below are the resolved values from that source; the ring adds only what a ring needs.*

## Foundations

**Colour (adaptive, WCAG-measured).**

| Token | Dark | Light | Use |
|---|---|---|---|
| `bg.base` | `#08090C` | `#F5F7FA` | canvas |
| `bg.elevated` | `#101319` | `#FFFFFF` | sheets, bars |
| `bg.card` | `#171B22` | `#FFFFFF` | cards |
| `bg.recessed` | `#0D1015` | `#EDF1F6` | chart wells, tracks |
| `content.primary` | `#F2F4F8` | `#101319` | numerals, titles |
| `content.secondary` | `#A7B0BF` | `#535C6B` | supporting |
| `content.tertiary` | `#868F9C` | `#5F6875` | provenance (still ≥ 4.5:1) |
| `separator.hairline` | `#282E38` | `#E1E6ED` | decorative |
| `brand.crimson → coral` | `#E01B47 → #FF6B57` | `#C41239 → #E85A3C` | heart moments only |
| `brand.ink` | `#FF8A6B` | `#A8102F` | brand text |
| `status.optimal` | `#06E19F` | `#037F5A` | |
| `status.good` | `#64BDE9` | (light variant per source) | also **Typical** |
| `status.fair` | `#DF9109` | | **Outside typical** (attention) |
| `status.poor` | `#F95725` | | Low |
| `status.abstained` | `#969BA7` | | Learning / not measured |

Ring-specific additions (same chroma family, Okabe-Ito safe):
- `sleep.deep` `#3A5BD9`, `sleep.light` `#7C9BEA`, `sleep.rem` `#B48CF2`, `sleep.awake` `#F0A35E` — luminance-monotone so the hypnogram survives greyscale.
- `battery.ok` = `status.optimal`, `battery.low` = `status.fair` (< 30 %), `battery.critical` = `status.poor` (< 15 %), `battery.charging` = `status.good`.

**Typography.** SF Pro (system), Dynamic Type throughout. Numerals use `monospacedDigit`. Scales: hero numeral 64 pt medium / unit 22; large 44 semibold / 17; medium 30 semibold / 14; small 20 semibold / 12. Eyebrow: caption semibold, uppercase, +1 tracking. Provenance: footnote, tertiary.

**Spacing & shape.** 2 · 4 · 8 · 12 · 16 · 24 · 32 · 48. Corners: 10 small, 20 card, 28 sheet (continuous). Hairline 0.5 pt. Ring stroke 14 (hero), 8 (compact). Minimum touch target 48 pt.

**Motion.** `ringFill` decelerating fill for scores; `breathingPulse` 4 s cycle for any waiting state (never a spinner); `cardAppear` staggered 40 ms; Reduce Motion swaps to cross-fades. Haptics: `heartbeat` on first pairing, `success` on a completed measurement, `selection` on chips.

**Accessibility.** Every state uses colour + label + symbol. VoiceOver labels read "Resting heart rate 58 beats per minute, typical for you, measured last night". Charts expose `accessibilityChartDescriptor`. Increase Contrast tokens exist for secondary/tertiary.

## Components (ring additions)

| Component | Anatomy | States |
|---|---|---|
| `RingStatusBar` | 44 pt bar above tab bar: state dot · name · battery glyph + percent · sync text | connected / syncing (hairline progress) / not connected / charging / Bluetooth off / unpaired |
| `BatteryGauge` | ring-shaped gauge, percent numeral, forecast line | ok / low / critical / charging (animated fill) / bars mode (0–4) |
| `HeroCard` | 24 pt padding, headline sentence, ScoreRing hero or illustration, contributors row, one action | morning / afternoon / evening / learning / no-night / unpaired |
| `ScoreRing` (shared) | value / establishing(n of N) / abstained | hero 176 pt, medium 96, compact 44 |
| `ScoreShortcutRow` | three compact rings with labels | |
| `VitalTile` | title, numeral + unit, state chip, 7-pt sparkline, provenance | typical / outside / learning / not measured / unsupported (hidden) |
| `StateChip` | pill, symbol + label | Typical (good) · Outside typical (fair) · Learning (abstained) · Not measured |
| `Hypnogram` | 4 lanes, per-minute stage blocks, hour axis, gap and battery-loss markers | precise (REM) / basic (no REM) |
| `StageBars` | 4 horizontal bars with duration and share vs usual | |
| `ContributorList` | rows: name · reading · chip | |
| `OvernightVitalsList` | rows with line chart, night value, typical band | |
| `SleepDebtCard` | need vs total, delta sentence | none / building / high |
| `HeartRateDayChart` | 5-min line, resting band, spot-test dots, scrubber pill | |
| `MeasureGrid` | 2-col tiles with symbol, title, last value | enabled / disabled (reason) / hidden |
| `MeasureSessionSheet` | instruction, progress ring, live value, result, Save/Discard | preparing / measuring / result / notWorn / busy / lowBattery / timedOut |
| `BreathingGuide` | duration chips, expanding circle, haptic cadence, before/after HR | idle / running / done |
| `MonitoringSchedule` | toggle rows with interval, window, battery-cost hint | |
| `DayTimeline` | clock-labelled rows with symbols | |
| `WearGuide` | illustration + finger/hand from profile | |
| `WellnessTag` (shared) | "Information only · not medical advice" | |

## Chart grammar

- Duration → stacked bars. Continuous overnight → line with 10th–90th percentile band in `bg.recessed`, value line in `content.primary`, outliers in `status.fair`. Spot tests → dots. Stages → hypnogram. Battery → area line.
- Gaps are gaps. No interpolation across missing 5-minute slots.
- Axis labels tertiary, gridlines hairline, no chart junk.

## Ring identity

The band's brand gradient stays reserved for heart moments; the ring adds a single signature: the **circular gauge** language (battery, scores, breathing) so a ring app looks like a ring. Illustration style: soft graphite ring render with the sensor bumps visible, on the recessed tone, never photoreal.
