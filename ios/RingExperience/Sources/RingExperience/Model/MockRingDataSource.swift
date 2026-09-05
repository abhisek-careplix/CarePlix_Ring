//
//  MockRingDataSource.swift
//  RingExperience
//
//  A complete, deterministic `RingDataSource` for previews and tests.
//
//  Each `MockScenario` is a state the real product must handle gracefully — a learning ring, a
//  night not worn, a battery that died at 02:14, no ring at all, Bluetooth off — so every screen
//  can be previewed in its honest empty state, not just its happy path.
//

import Foundation
import Combine

@MainActor
public final class MockRingDataSource: RingDataSource {

    @Published public private(set) var connection: RingConnection
    @Published public private(set) var battery: Battery?
    @Published public private(set) var capabilities: RingCapabilities
    @Published public private(set) var profile: UserProfile?
    @Published public private(set) var today: TodayDashboard
    @Published public private(set) var nights: [SleepNight]
    @Published public private(set) var activity: ActivityDay
    @Published public private(set) var spotMeasurements: [SpotMeasurement]
    @Published public private(set) var timeline: [DayTimelineItem]
    @Published public private(set) var monitoring: [MonitoringSetting]
    @Published public private(set) var ringName: String?
    @Published public private(set) var firmwareVersion: String?
    @Published public private(set) var heartRateToday: [TimedSample]
    @Published public private(set) var batteryHistory: [TimedSample]
    @Published public private(set) var lastSync: Date?
    @Published public private(set) var isLowPowerMode = false

    public var isDemo: Bool { true }

    public let scenario: MockScenario
    /// How long a simulated spot test takes. Tests set this very short.
    public var spotTestDuration: TimeInterval
    private var spotTask: Task<Void, Never>?
    private let now: Date

    /// - Parameters:
    ///   - scenario: which situation to reproduce.
    ///   - now: the clock the fixture is built around. Fixed in tests, `Date()` in previews.
    ///   - profile: pass `nil` to preview first-run onboarding.
    public init(scenario: MockScenario = .established, now: Date = Date(), profile: UserProfile? = .demo, spotTestDuration: TimeInterval = 3) {
        self.scenario = scenario
        self.now = now
        self.spotTestDuration = spotTestDuration
        let snapshot = MockFixtures.snapshot(scenario: scenario, now: now, profile: profile)
        connection = snapshot.connection
        battery = snapshot.battery
        capabilities = snapshot.capabilities
        self.profile = profile
        today = snapshot.today
        nights = snapshot.nights
        activity = snapshot.activity
        spotMeasurements = snapshot.spots
        timeline = snapshot.timeline
        monitoring = snapshot.monitoring
        ringName = snapshot.ringName
        firmwareVersion = snapshot.firmware
        heartRateToday = snapshot.heartRateToday
        batteryHistory = snapshot.batteryHistory
        switch scenario {
        case .unpaired: lastSync = nil
        case .bluetoothOff: lastSync = now.addingTimeInterval(-40 * 60)
        default: lastSync = snapshot.nights.last.map { $0.wake.addingTimeInterval(6 * 60) } ?? now
        }
    }

    // MARK: Sync

    public func sync() async {
        switch connection {
        case .unpaired, .bluetoothOff: return
        default: break
        }
        for step in 1...6 {
            connection = .syncing(progress: Double(step) / 6)
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        connection = .connected
        lastSync = Date()
        timeline.append(DayTimelineItem(id: "sync-\(Date().timeIntervalSince1970)", time: Date(), kind: .sync, title: "Synced", detail: "Up to date"))
    }

    public func setLowPowerMode(_ on: Bool) async {
        isLowPowerMode = on
    }

    public func reconnect() async {
        guard connection != .unpaired, connection != .bluetoothOff else { return }
        connection = .connecting
        try? await Task.sleep(nanoseconds: 400_000_000)
        connection = .connected
    }

    // MARK: Spot tests

    /// Emits preparing → measuring(progress) → a terminal state. The scenario decides the exit:
    /// a ring that is not worn says so; a flat battery says so; nothing ever hangs.
    public func startSpot(_ kind: SpotKind) -> AsyncStream<MeasureSessionState> {
        spotTask?.cancel()
        let scenario = self.scenario
        let duration = spotTestDuration
        let battery = self.battery
        let range = today.vitals.first { $0.kind == kind.vital }?.typicalRange
        let nights = today.nightsRecorded

        let (stream, continuation) = AsyncStream<MeasureSessionState>.makeStream()
        let task = Task { @MainActor in
            continuation.yield(.preparing)
            try? await Task.sleep(nanoseconds: UInt64(duration * 0.15 * 1e9))
            if Task.isCancelled { continuation.finish(); return }

            switch scenario {
            case .unpaired: continuation.yield(.failed("No ring paired")); continuation.finish(); return
            case .bluetoothOff: continuation.yield(.failed("Bluetooth is off")); continuation.finish(); return
            case .notWorn: continuation.yield(.notWorn); continuation.finish(); return
            case .batteryDied: continuation.yield(.lowBattery(percent: battery?.percent)); continuation.finish(); return
            default: break
            }

            let steps = 20
            var live: Double = 74
            for step in 1...steps {
                if Task.isCancelled { continuation.finish(); return }
                live = (live + Double(step % 3) - 1)
                continuation.yield(.measuring(progress: Double(step) / Double(steps), live: kind.showsLiveValue ? live : nil))
                try? await Task.sleep(nanoseconds: UInt64(duration * 0.85 / Double(steps) * 1e9))
            }
            let value: Double
            switch kind {
            case .heartRate: value = 72
            case .bloodOxygen: value = 97
            case .hrv: value = 43
            case .stress: value = 29
            case .skinTemperature: value = 33.7
            case .breathingRate: value = 14.5
            }
            // Skin temperature is graded as a deviation from baseline, never as an absolute.
            let graded = kind == .skinTemperature ? 0.1 : value
            let state: RangeState = kind.vital == nil ? .typical : Baselines.rangeState(value: graded, range: range, nights: nights)
            continuation.yield(.result(SpotMeasurement(kind: kind, value: value, at: Date(), state: state)))
            continuation.finish()
        }
        spotTask = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func cancelSpot() {
        spotTask?.cancel()
        spotTask = nil
    }

    public func saveSpot(_ measurement: SpotMeasurement) {
        spotMeasurements.insert(measurement, at: 0)
        timeline.append(DayTimelineItem(id: measurement.id.uuidString, time: measurement.at, kind: .spotTest, title: "\(measurement.kind.title) \(RingFormat.spot(measurement.kind, measurement.value)) \(measurement.unit)".trimmingCharacters(in: .whitespaces), detail: measurement.state.label))
        timeline.sort { $0.time < $1.time }
    }

    // MARK: Profile & settings

    public func saveProfile(_ profile: UserProfile) async {
        self.profile = profile
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    public func setMonitoring(_ kind: MonitoringKind, on: Bool, intervalMin: Int) async {
        guard let index = monitoring.firstIndex(where: { $0.kind == kind }) else { return }
        monitoring[index].isOn = on
        monitoring[index].intervalMin = max(intervalMin, monitoring[index].minIntervalMin)
    }

    // MARK: Pairing lifecycle

    public func forgetRing() async {
        cancelSpot()
        connection = .unpaired
        battery = nil
        capabilities = .none
        ringName = nil
        firmwareVersion = nil
        nights = []
        spotMeasurements = []
        timeline = []
        heartRateToday = []
        batteryHistory = []
        lastSync = nil
        today = .empty(date: now)
    }

    public func adoptPairedRing(id: String, name: String) async {
        ringName = name
        firmwareVersion = firmwareVersion ?? "2.14.3"
        capabilities = .all
        connection = .connected
        if battery == nil { battery = Battery(percent: 64, isCharging: false, isLow: false, forecastNights: 3) }
        if nights.isEmpty { today = .empty(date: now) }
    }
}

public extension UserProfile {
    /// The demo wearer. Public so it can be a default argument on the mock's initialiser.
    static let demo = UserProfile(
        name: "Aisha",
        birthDate: Calendar.current.date(from: DateComponents(year: 1991, month: 4, day: 12)) ?? Date(),
        sex: .female, heightCm: 168, weightKg: 62,
        wearHand: .left, wearFinger: .index,
        bedtime: ClockTime(hour: 23, minute: 0), wakeTime: ClockTime(hour: 7, minute: 0),
        sleepGoalMin: 450, units: .metric, stepGoal: 8000
    )
}
