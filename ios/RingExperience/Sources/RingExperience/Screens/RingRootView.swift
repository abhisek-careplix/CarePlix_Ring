//
//  RingRootView.swift
//  RingExperience
//
//  The four tabs — Today · Sleep · Measure · Breathe — with the ring status accessory that
//  persists on every tab, and the sheets (Ring, Profile, Metric detail, Measure session,
//  Pairing). No search role: there is nothing to search.
//
//  The accessory uses `tabViewBottomAccessory` on iOS 26 and a bottom safe-area inset on
//  iOS 17–18. The iOS 26 branch is additionally behind `#if compiler(>=6.2)` so the package still
//  compiles with Xcode 16, whose SDK does not know the modifier.
//

import SwiftUI
import RingDiscovery

public enum RingTab: Hashable {
    case today, sleep, measure, breathe
}

/// Every sheet the root can present, as one value.
public enum RingSheetRoute: Identifiable, Hashable {
    case ring
    case profile
    case measure(SpotKind)
    case metric(VitalKind)
    case pairing
    case wearGuide

    public var id: String {
        switch self {
        case .ring: return "ring"
        case .profile: return "profile"
        case let .measure(kind): return "measure-\(kind.rawValue)"
        case let .metric(kind): return "metric-\(kind.rawValue)"
        case .pairing: return "pairing"
        case .wearGuide: return "wear"
        }
    }
}

/// What screens can ask the root to do.
public struct RingNavigator {
    public var open: (RingSheetRoute) -> Void
    public var switchTab: (RingTab) -> Void
    public var breathe: (Int) -> Void

    public init(open: @escaping (RingSheetRoute) -> Void, switchTab: @escaping (RingTab) -> Void, breathe: @escaping (Int) -> Void) {
        self.open = open; self.switchTab = switchTab; self.breathe = breathe
    }

    public static let inert = RingNavigator(open: { _ in }, switchTab: { _ in }, breathe: { _ in })
}

public struct RingRootView<DS: RingDataSource>: View {
    @ObservedObject private var dataSource: DS
    @State private var tab: RingTab = .today
    @State private var sheet: RingSheetRoute?
    @State private var showsFirstRun: Bool
    @State private var breatheRequest: Int?

    @MainActor public init(dataSource: DS) {
        self.dataSource = dataSource
        _showsFirstRun = State(initialValue: dataSource.profile == nil)
    }

    private var navigator: RingNavigator {
        RingNavigator(
            open: { sheet = $0 },
            switchTab: { tab = $0 },
            breathe: { minutes in breatheRequest = minutes; tab = .breathe }
        )
    }

    public var body: some View {
        tabs
            .tint(RingTheme.Brand.ink)
            .sheet(item: $sheet) { route in sheetContent(route) }
            .fullScreenCover(isPresented: $showsFirstRun) {
                FirstRunFlow(dataSource: dataSource) { showsFirstRun = false }
            }
    }

    // MARK: Tabs & accessory

    @ViewBuilder
    private var tabs: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            tabView(inlineAccessory: false)
                .tabViewBottomAccessory { statusBar }
        } else {
            tabView(inlineAccessory: true)
        }
        #else
        tabView(inlineAccessory: true)
        #endif
    }

    private func tabView(inlineAccessory: Bool) -> some View {
        TabView(selection: $tab) {
            tabContent(TodayScreen(dataSource: dataSource, navigator: navigator), inline: inlineAccessory)
                .tabItem { Label("Today", systemImage: "sun.horizon") }.tag(RingTab.today)
            tabContent(SleepScreen(dataSource: dataSource, navigator: navigator), inline: inlineAccessory)
                .tabItem { Label("Sleep", systemImage: "moon") }.tag(RingTab.sleep)
            tabContent(MeasureScreen(dataSource: dataSource, navigator: navigator), inline: inlineAccessory)
                .tabItem { Label("Measure", systemImage: "waveform.path") }.tag(RingTab.measure)
            tabContent(BreatheScreen(dataSource: dataSource, navigator: navigator, breatheRequest: $breatheRequest), inline: inlineAccessory)
                .tabItem { Label("Breathe", systemImage: "wind") }.tag(RingTab.breathe)
        }
    }

    @ViewBuilder
    private func tabContent<Content: View>(_ content: Content, inline: Bool) -> some View {
        NavigationStack {
            if inline {
                content.safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
            } else {
                content
            }
        }
    }

    private var statusBar: some View {
        RingStatusBar(
            connection: dataSource.connection,
            battery: dataSource.battery,
            ringName: dataSource.ringName,
            onTap: { sheet = dataSource.connection == .unpaired ? .pairing : .ring },
            onSyncNow: { Task { await dataSource.sync() } }
        )
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ route: RingSheetRoute) -> some View {
        switch route {
        case .ring:
            RingSheet(dataSource: dataSource, navigator: navigator)
        case .profile:
            ProfileSheet(dataSource: dataSource)
        case let .measure(kind):
            MeasureSessionSheet(dataSource: dataSource, kind: kind)
        case let .metric(kind):
            MetricDetailSheet(kind: kind, nights: dataSource.nights, today: dataSource.today)
        case .pairing:
            PairingFlowSheet(dataSource: dataSource)
        case .wearGuide:
            NavigationStack {
                ScrollView {
                    WearGuide(hand: dataSource.profile?.wearHand ?? .left, finger: dataSource.profile?.wearFinger ?? .index)
                        .ringCard().padding()
                }
                .background(RingTheme.Background.base)
                .navigationTitle("How to wear it")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }
}

/// Pairing presented from the Ring sheet or the unpaired hero: J1 step 4 on its own.
struct PairingFlowSheet<DS: RingDataSource>: View {
    @ObservedObject var dataSource: DS
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: RingPairingModel

    @MainActor init(dataSource: DS) {
        self.dataSource = dataSource
        _model = StateObject(wrappedValue: RingPairingModel(link: dataSource.pairingLink))
    }

    var body: some View {
        NavigationStack {
            PairingScreen(model: model, demoPairing: dataSource.isDemo ? { Task { await dataSource.adoptPairedRing(id: "demo", name: "LOOP-E5FF"); dismiss() } } : nil) { ring in
                Task { await dataSource.adoptPairedRing(id: ring.id, name: ring.displayName); dismiss() }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

#Preview("Established · dark") {
    RingRootView(dataSource: MockRingDataSource(scenario: .established)).preferredColorScheme(.dark)
}

#Preview("Learning · light") {
    RingRootView(dataSource: MockRingDataSource(scenario: .learning(night: 3))).preferredColorScheme(.light)
}

#Preview("Unpaired") {
    RingRootView(dataSource: MockRingDataSource(scenario: .unpaired))
}
