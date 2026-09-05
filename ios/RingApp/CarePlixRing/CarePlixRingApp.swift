//
//  CarePlixRingApp.swift
//  CarePlix Ring
//
//  The shipping app is deliberately thin: everything the user sees lives in the
//  `RingExperience` package, pairing lives in `RingDiscovery`, and this target only decides
//  which data source drives them (see AppDataSource.swift) and owns the bundle: icon,
//  Info.plist, version, signing.
//

import SwiftUI
import RingExperience

@main
struct CarePlixRingApp: App {

    /// One data source for the life of the process. `AppRingDataSource` resolves to the real
    /// Veepoo-backed source on device builds that link the vendor SDK, and to the deterministic
    /// demo source everywhere else (simulator, and any build made without the SDK).
    @StateObject private var dataSource: AppRingDataSource = AppDataSource.make()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RingRootView(dataSource: dataSource)
                .onChange(of: scenePhase) { _, phase in
                    // The ring keeps days of history on its own; foregrounding is the moment
                    // to reconnect and catch up, so the morning check-in never shows stale numbers.
                    guard phase == .active else { return }
                    Task { await dataSource.reconnect(); await dataSource.sync() }
                }
        }
    }
}
