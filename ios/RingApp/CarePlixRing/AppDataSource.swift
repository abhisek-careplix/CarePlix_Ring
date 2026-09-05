//
//  AppDataSource.swift
//  CarePlix Ring
//
//  Chooses the data source for this build.
//
//  DEVICE + VENDOR SDK LINKED  ->  VeepooRingDataSource (real ring over Bluetooth)
//  EVERYTHING ELSE             ->  MockRingDataSource   (demo mode: realistic, deterministic data)
//
//  `VEEPOO` is defined by Config/Vendor.xcconfig, which scripts/link-vendor-sdk.sh writes for
//  device SDKs only — the vendor archives have no simulator slice, so simulator builds are
//  always demo mode. That is also what makes a fresh clone archive with zero setup.
//
//  Demo mode can be steered for QA and screenshots with a launch argument:
//      -demoScenario established | learning | notWorn | batteryDied | unpaired | bluetoothOff
//

import Foundation
import RingExperience

#if VEEPOO
typealias AppRingDataSource = VeepooRingDataSource
#else
typealias AppRingDataSource = MockRingDataSource
#endif

enum AppDataSource {

    static func make() -> AppRingDataSource {
        #if VEEPOO
        return VeepooRingDataSource()
        #else
        return MockRingDataSource(scenario: demoScenario())
        #endif
    }

    /// True when this build shows demo data rather than a ring. Surfaced in the Ring sheet so
    /// nobody mistakes a demo build for a broken one.
    static var isDemo: Bool {
        #if VEEPOO
        return false
        #else
        return true
        #endif
    }

    #if !VEEPOO
    private static func demoScenario() -> MockScenario {
        switch UserDefaults.standard.string(forKey: "demoScenario") {
        case "learning":     return .learning(night: 3)
        case "notWorn":      return .notWorn
        case "batteryDied":  return .batteryDied
        case "unpaired":     return .unpaired
        case "bluetoothOff": return .bluetoothOff
        default:             return .established
        }
    }
    #endif
}
