# RingExperience

The redesigned CarePlix ring experience as a SwiftUI package: design tokens, the four tabs
(**Today · Sleep · Measure · Breathe**), the ring status accessory, onboarding, the Ring and Profile
sheets, spot-test sessions, and a `RingDataSource` protocol with a deterministic mock. It implements
[`docs/ux/`](../../docs/ux/) and builds on [`../RingDiscovery`](../RingDiscovery) for pairing.

**This package is vendor-free.** The Veepoo adapter (`VeepooRingDataSource`, `VeepooRingLink`) lives
in the app target at `ios/RingApp/CarePlixRing/Vendor/`, compiled only when the `VEEPOO` flag is
defined — a SwiftPM target never sees an app's framework search paths, so it could not link the SDK
from here. The package therefore builds and tests anywhere.

## Embed

```swift
import RingExperience

@StateObject private var dataSource = MockRingDataSource(scenario: .established)   // or VeepooRingDataSource() in the app

var body: some Scene {
    WindowGroup { RingRootView(dataSource: dataSource) }
}
```

`RingRootView` is generic over any `RingDataSource`. It presents first-run onboarding when
`profile == nil`, the ring status accessory on every tab (`tabViewBottomAccessory` on iOS 26, a
bottom safe-area inset on iOS 17–18), and every sheet (Ring, Profile, Metric detail, Measure session,
Pairing).

## Layout

```
Sources/RingExperience/
  Design/       RingTheme (the only file with hex colours) · RingTypography · RingMotion
  Model/        RingModels · RingMeasureModels · RingProfileModels · RingFormat
                RingDataSource (protocol + HeroSelection) · Baselines (pure rules)
                NightAssembly (raw nights → SleepNight / dashboard, shared with the adapter)
                MockFixtures · MockFixtures+Day · MockRingDataSource
  Components/   RingStatusBar · BatteryGauge · ScoreRing · StateChip · VitalTile · Sparkline · HeroCard
                Hypnogram · StageBars · ContributorList · OvernightVitalsList · SleepDebtCard
                HeartRateDayChart · MeasureGrid · MeasureSessionSheet · BreathingGuide
                MonitoringSchedule · DayTimeline · WearGuide · WellnessTag · EmptyStates
  Screens/      RingRootView · FirstRunFlow · TodayScreen · SleepScreen · MeasureScreen · BreatheScreen
                RingSheet · ProfileSheet · MetricDetailSheet · ProfileOnboardingFlow
                PermissionsScreen · PairingScreen · FitAndWearScreen
Tests/RingExperienceTests/
  BaselinesTests · HeroSelectionTests · MockDataSourceTests
```

## The data-source contract

`RingDataSource` is an `ObservableObject` snapshot: `connection`, `battery`, `capabilities`, `profile`,
`today`, `nights`, `activity`, `spotMeasurements`, `timeline`, `monitoring`, `heartRateToday`,
`batteryHistory`, `lastSync`, plus `sync()`, `startSpot(_:) -> AsyncStream<MeasureSessionState>`,
`cancelSpot()`, `saveSpot(_:)`, `saveProfile(_:)`, `setMonitoring(_:on:intervalMin:)`, `forgetRing()`,
`adoptPairedRing(id:name:)`, `reconnect()`, and `heroNow(at:)`. Optional members with defaults:
`isDemo` (true on the mock → "Demo data" in the Ring sheet), `pairingLink` (the `RingLinking` the
pairing screen connects through; nil in demo builds), `isLowPowerMode` / `setLowPowerMode(_:)`,
`powerOffRing()`, `resetRingData()`.

Everything visible is capability-gated by `RingCapabilities` and can render an honest state:
`Learning · night n of 7`, `Not worn`, `Not synced`, `Battery ran out at HH:MM`, `Not measured`.
Chips read exactly **Typical · Outside typical · Learning · Not measured**; scores **Optimal · Good ·
Fair · Low · Not enough signal**. No disease names; no blood pressure, glucose or ECG UI.

## Scenario previews

Every screen has `#Preview` blocks in light and dark against `MockRingDataSource` scenarios:

| Scenario | What it shows |
|---|---|
| `.established` | 14 nights, typical ranges, readiness, connected at 64 % |
| `.learning(night: 3)` | Learning hero, dashed rings, "Learning · night 3 of 7" chips |
| `.notWorn` | "Ring not worn" night, No-night hero, spot test exits with Not on finger |
| `.batteryDied` | Partial night with a 02:14 marker, "Charge it now" hero, low-battery exits |
| `.unpaired` | Single "Pair your ring" card, pairing flow with a demo ring |
| `.bluetoothOff` | Banner, accessory "Bluetooth is off", stale sync |

`MockRingDataSource(scenario:now:profile:spotTestDuration:)` — pass `profile: nil` to preview
first-run onboarding; tests use a short `spotTestDuration`.

## Build caveat

**Nothing here has been compiled.** The package was written in a Linux container with no Swift
toolchain or Xcode. Before relying on it:

```bash
cd ios/RingExperience
swift build && swift test        # Xcode 16 or newer; no vendor SDK needed
```

The iOS 26 accessory branch is behind `#if compiler(>=6.2)` and `if #available(iOS 26, *)`, so
Xcode 16 builds the iOS 17–18 fallback. The vendor adapter in the app target carries
`// VERIFY on device:` comments wherever a call was written from the SDK header rather than a
running ring.
