// swift-tools-version: 5.9
//
//  RingDiscovery
//
//  Packaged as a library so the discovery layer can be dropped into the ring app and unit tested
//  on its own. It deliberately does NOT depend on the vendor SDK: the Veepoo implementation of
//  `RingLinking` lives in the app target (ios/RingApp/CarePlixRing/Vendor/VeepooRingLink.swift,
//  behind the `VEEPOO` flag), so this package builds, and its tests run, on a machine that has
//  never seen the vendor framework.
//

import PackageDescription

let package = Package(
    name: "RingDiscovery",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "RingDiscovery", targets: ["RingDiscovery"]),
    ],
    targets: [
        .target(name: "RingDiscovery"),
        .testTarget(name: "RingDiscoveryTests", dependencies: ["RingDiscovery"]),
    ]
)
