// swift-tools-version: 5.9
//
//  RingExperience
//
//  The redesigned CarePlix ring experience: design tokens, the four tabs, the ring status
//  accessory, onboarding, and a `RingDataSource` protocol with a deterministic mock and a Veepoo
//  adapter. Pairing is NOT reimplemented here — it comes from `../RingDiscovery`, whose
//  `RingPairingModel` is rendered one-phase-at-a-time by `PairingScreen`.
//
//  This package is vendor-free. The Veepoo adapter (`VeepooRingDataSource`) lives in the app
//  target — ios/RingApp/CarePlixRing/Vendor — behind the `VEEPOO` compile flag, because a SwiftPM
//  target never sees an app's framework search paths. So this builds, and its tests run, on a
//  machine that has never seen the vendor framework.
//

import PackageDescription

let package = Package(
    name: "RingExperience",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "RingExperience", targets: ["RingExperience"]),
    ],
    dependencies: [
        .package(path: "../RingDiscovery"),
    ],
    targets: [
        .target(
            name: "RingExperience",
            dependencies: [
                .product(name: "RingDiscovery", package: "RingDiscovery"),
            ]
        ),
        .testTarget(
            name: "RingExperienceTests",
            dependencies: ["RingExperience"]
        ),
    ]
)
