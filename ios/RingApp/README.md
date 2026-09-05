# CarePlix Ring · iOS app

The archivable, distributable iOS app for the CarePlix ring. It is a thin shell: the experience is `../RingExperience`, pairing is `../RingDiscovery`, and this target owns the bundle (icon, Info.plist, version, signing) and chooses the data source.

## Two build modes, one project

| Mode | When | What you get |
|---|---|---|
| **Demo** | Any simulator build, or any build before the vendor SDK is linked | The full new UI on realistic, deterministic sample data. No Bluetooth. Archives and installs like the real thing. |
| **Ring** | Device builds after `scripts/link-vendor-sdk.sh` | The same UI driven by the real ring over Bluetooth through the Veepoo SDK. |

A fresh clone opens and archives in demo mode with no setup. Linking the SDK is one script and is never committed (the SDK is licensed).

## See the new UI in 2 minutes

1. Open `ios/RingApp/CarePlixRing.xcodeproj` in Xcode 15 or newer. Let it resolve the two open-source packages (`FMDB`, `MJExtension`) the vendor SDK depends on.
2. Pick any iPhone simulator, press Run. You are in demo mode.
3. Try other states with a launch argument (Product → Scheme → Edit Scheme → Arguments): `-demoScenario learning`, `notWorn`, `batteryDied`, `unpaired`, `bluetoothOff`.

## Run against a real ring

```bash
# the folder that holds VeepooBleSDK.framework and its siblings (for example ../CardiacPro/ios/Frameworks)
ios/RingApp/scripts/link-vendor-sdk.sh /path/to/Frameworks
```

This copies the frameworks to `ios/Frameworks/` (git-ignored) and writes `Config/Vendor.xcconfig` (git-ignored), which links them for device builds and defines `VEEPOO`. Plug in an iPhone, Run. The pairing flow, battery, sync and every measurement now come from the ring.

## Archive and distribute

1. **Signing, once.** Copy `Config/Signing.xcconfig.template` to `Config/Signing.xcconfig` and put your Team ID in it (Xcode → Settings → Accounts shows it). The file is git-ignored. Automatic signing does the rest, including the App Store Connect app record for `com.careplix.ring` on first upload if your account can create apps.
2. **Version.** `Config/Version.xcconfig` is the single source of truth: `MARKETING_VERSION` (what users see, e.g. `1.0.0`) and `CURRENT_PROJECT_VERSION` (the build number; must increase on every upload).
   ```bash
   ios/RingApp/scripts/bump-version.sh            # build +1
   ios/RingApp/scripts/bump-version.sh 1.1.0      # new version, build +1
   ios/RingApp/scripts/bump-version.sh 1.1.0 --tag   # …and commit + git tag ring-v1.1.0-<build>
   ```
3. **Archive.** Either Xcode → Product → Archive with the `CarePlixRing` scheme and a *Any iOS Device* destination, then *Distribute App* from Organizer, or from the terminal:
   ```bash
   ios/RingApp/scripts/archive.sh              # archives and uploads to TestFlight (ExportOptions.plist: app-store-connect)
   ios/RingApp/scripts/archive.sh --no-upload  # archives and exports a signed .ipa into build/
   ```
   The archive name carries the version: `build/CarePlixRing-1.0.0-1.xcarchive`.
4. **TestFlight.** After the upload finishes processing (5–15 min), add testers in App Store Connect → TestFlight. Internal testers get the build immediately; external groups need a short review the first time.

For an ad-hoc `.ipa` (registered devices, no TestFlight) change `method` in `ExportOptions.plist` to `ad-hoc` and use `--no-upload`.

## What the archive contains

- Bundle `com.careplix.ring`, display name *CarePlix Ring*, iOS 17+, iPhone only, portrait.
- Bluetooth usage strings, Health write strings, launch screen colour, single-size app icon.
- Demo-mode archives contain no vendor code at all. Ring-mode archives statically link `VeepooBleSDK`, `JL_BLEKit`, `DFUnits` and embed the four dynamic vendor helpers (`ABParTool`, `GRDFUSDK`, `JLDialUnit`, `ZipZap`), re-signed by the *Embed vendor frameworks* build phase. Those helpers ship armv7 slices; if App Store validation objects, strip them with `lipo -remove armv7` before linking.

## Layout

```
ios/RingApp/
├── CarePlixRing.xcodeproj/          project + shared scheme CarePlixRing
├── CarePlixRing/
│   ├── CarePlixRingApp.swift        @main; foreground → reconnect + sync
│   ├── AppDataSource.swift          VEEPOO ? real ring : demo data
│   ├── Vendor/                      Veepoo-backed data source + link (compiled only with VEEPOO)
│   ├── Assets.xcassets              AppIcon, AccentColor, LaunchBackground
│   └── Info.plist
├── Config/
│   ├── CarePlixRing.xcconfig        base settings; includes Version + optional Signing/Vendor
│   ├── Version.xcconfig             MARKETING_VERSION / CURRENT_PROJECT_VERSION
│   ├── Signing.xcconfig.template    copy → Signing.xcconfig (git-ignored)
│   └── Vendor.xcconfig.template     written by link-vendor-sdk.sh (git-ignored)
├── ExportOptions.plist              TestFlight upload by default
└── scripts/                         bump-version.sh · link-vendor-sdk.sh · archive.sh
```

## Not verified here

This project was authored in a Linux container without Xcode. The project file, scheme and configs follow the sibling CardiacPro app's known-good setup, but the first `Product → Archive` on a Mac is the real test. If Xcode reports a missing package product, use File → Packages → Resolve Package Versions once.
