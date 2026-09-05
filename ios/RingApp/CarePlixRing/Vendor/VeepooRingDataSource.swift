//
//  VeepooRingDataSource.swift
//  CarePlix Ring
//
//  The production `RingDataSource`, backed by the Veepoo SDK for the LINK and the app's own
//  `RingDiscovery` package for DISCOVERY. Connection state is proven by round-trips (a battery
//  read under a timeout), never by a cached flag — see RingDiscovery/README.md, point 5.
//
//  WHY THIS LIVES IN THE APP TARGET
//  A SwiftPM package target never sees the app's FRAMEWORK_SEARCH_PATHS, so a `canImport`
//  guard inside `RingExperience` would be false in every real build. The vendor-facing code is
//  compiled here, only when Config/Vendor.xcconfig defines `VEEPOO` (device builds after
//  scripts/link-vendor-sdk.sh). Demo builds contain none of it.
//
//  Sections: data source (connection · sync · snapshot · power) · persistence · commands
//  (battery · spot tests · profile · monitoring) · spot session · night builder · pure mappers.
//  Every call marked `// VERIFY on device:` was written from the SDK header, not a running ring.
//

#if VEEPOO
import Foundation
import Combine
import CoreBluetooth
import VeepooBleSDK
import RingExperience
import RingDiscovery
import os

@MainActor
public final class VeepooRingDataSource: RingDataSource {

    @Published public private(set) var connection: RingConnection = .unpaired
    @Published public private(set) var battery: Battery?
    @Published public private(set) var capabilities: RingCapabilities = .none
    @Published public private(set) var profile: UserProfile?
    @Published public private(set) var today: TodayDashboard = .empty(date: Date())
    @Published public private(set) var nights: [SleepNight] = []
    @Published public private(set) var activity: ActivityDay = .empty(date: Date())
    @Published public private(set) var spotMeasurements: [SpotMeasurement] = []
    @Published public private(set) var timeline: [DayTimelineItem] = []
    @Published public private(set) var monitoring: [MonitoringSetting] = []
    @Published public private(set) var ringName: String?
    @Published public private(set) var firmwareVersion: String?
    @Published public private(set) var heartRateToday: [TimedSample] = []
    @Published public private(set) var batteryHistory: [TimedSample] = []

    let link: VeepooRingLink
    let scanner: RingScanner
    let store: VeepooRingStore
    let log = Logger(subsystem: "com.careplix.ring", category: "RingDataSource")

    @Published public private(set) var lastSync: Date?
    @Published public private(set) var isLowPowerMode = false

    var spotTask: Task<Void, Never>?

    public var isDemo: Bool { false }
    public var pairingLink: (any RingLinking)? { link }

    /// No-argument construction is what `AppDataSource.make()` and `@StateObject` need; the
    /// parameters exist for tests and previews inside the app target.
    public init(link: VeepooRingLink = .shared, scanner: RingScanner = RingScanner(), store: VeepooRingStore = VeepooRingStore()) {
        self.link = link
        self.scanner = scanner
        self.store = store
        profile = store.profile
        ringName = store.ringName
        capabilities = store.capabilities ?? .none
        batteryHistory = store.batteryHistory
        spotMeasurements = store.spotMeasurements
        lastSync = store.lastSync
        connection = store.ringID == nil ? .unpaired : .notConnected(lastSync: store.lastSync)
        link.prepare()
    }

    // MARK: SDK handles

    var manager: VPBleCentralManage? { VPBleCentralManage.sharedBleManager() }
    var peripheral: VPPeripheralBaseManage? { manager?.peripheralManage }
    var deviceModel: VPPeripheralModel? { manager?.peripheralModel }
    /// The database table id is the ring's MAC as the SDK reports it after the handshake.
    /// VERIFY on device: `deviceAddress` "may change after password verification" (header).
    var tableID: String? { deviceModel?.deviceAddress }

    // MARK: Connection lifecycle

    public func adoptPairedRing(id: String, name: String) async {
        store.ringID = id
        store.ringName = name
        ringName = name
        connection = .connected
        await afterHandshake()
    }

    /// Scan for the remembered ring and connect silently (`isFirstPairing: false`).
    public func reconnect() async {
        guard let savedID = store.ringID else { connection = .unpaired; return }
        if link.handshakeCompleted, await readBattery() != nil {
            connection = .connected
            return
        }
        connection = .connecting
        var candidate: RingCandidate?
        for await event in scanner.scan(policy: .standard) {
            switch event {
            case .discovered(let ring) where ring.id == savedID:
                candidate = ring
                scanner.stop()
            case .ended(.radioUnavailable(let state)):
                connection = state == .poweredOff ? .bluetoothOff : .notConnected(lastSync: lastSync)
                return
            default:
                break
            }
            if candidate != nil { break }
        }
        guard let candidate else { connection = .notConnected(lastSync: lastSync); return }
        for await state in link.connect(to: candidate, isFirstPairing: false) {
            switch state {
            case .verified:
                connection = .connected
                await afterHandshake()
                return
            case .radioOff:
                connection = .bluetoothOff
                return
            case .timedOut, .disconnected, .unmodelled:
                connection = .notConnected(lastSync: lastSync)
                return
            case .connecting, .connected, .needsPasscode, .awaitingConfirmationOnRing:
                connection = .connecting
            }
        }
    }

    /// Runs once the SDK reports `VerifyPasswordSuccess`: capabilities, battery, version, then sync.
    func afterHandshake() async {
        if let model = deviceModel {
            let caps = VeepooMappers.capabilities(
                heartRateType: Int(model.heartRateType),
                sleepType: Int(model.sleepType),
                hrvType: Int(model.hrvType),
                isSupportHRVTest: model.isSupportHRVTest,
                oxygenType: Int(model.oxygenType),
                resRateType: Int(model.resRateType),
                temperatureType: Int(model.temperatureType),
                stressType: Int(model.stressType),
                saveDays: Int(model.saveDays)
            )
            // VERIFY on device: some firmware leaves `heartRateType` at 0 and signals HR only in the
            // `deviceFuctionData` bitmask; if the HR tile vanishes on a ring that plainly has PPG,
            // fall back to that bitmask here.
            capabilities = caps
            store.capabilities = caps
            firmwareVersion = model.deviceVersion
        }
        _ = await readBattery()
        await loadMonitoring()
        await sync()
    }

    public func forgetRing() async {
        cancelSpot()
        link.disconnect()
        store.clearRing()
        connection = .unpaired
        battery = nil
        capabilities = .none
        ringName = nil
        firmwareVersion = nil
        nights = []
        heartRateToday = []
        batteryHistory = []
        timeline = []
        today = .empty(date: Date())
    }

    // MARK: Sync

    /// Reads everything the ring holds, then rebuilds the snapshot from the SDK's database.
    public func sync() async {
        guard store.ringID != nil else { return }
        guard let peripheral, link.handshakeCompleted else {
            // `reconnect()` runs `afterHandshake()`, which syncs on success. No second pass here.
            await reconnect()
            return
        }
        connection = .syncing(progress: 0)
        let ok = await readAllData(peripheral)
        if capabilities.spo2 { await readSeries { peripheral.veepooSdkStartReadDeviceOxygenData($0) } }
        if capabilities.hrv { await readSeries { peripheral.veepooSdkStartReadDeviceHrvData($0) } }
        // VERIFY on device: temperatureType 5 is read as part of AllData and this call is refused.
        if capabilities.temperature, deviceModel?.temperatureType != 5 { await readSeries { peripheral.veepooSdkStartReadDeviceTemperatureData($0) } }
        _ = await readBattery()
        if ok {
            lastSync = Date()
            store.lastSync = lastSync
        }
        rebuildSnapshot()
        connection = link.handshakeCompleted ? .connected : .notConnected(lastSync: lastSync)
    }

    /// `veepooSdkStartReadDeviceAllDataWithReadStateChangeBlock:` reports per-day progress.
    private func readAllData(_ peripheral: VPPeripheralBaseManage) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce()
            let timeout = DispatchWorkItem { once.run { continuation.resume(returning: false) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: timeout)
            // VERIFY on device: Swift renames this selector to `…AllData(withReadStateChangeBlock:)`.
            peripheral.veepooSdkStartReadDeviceAllData(withReadStateChangeBlock: { [weak self] state, totalDay, currentDay, dayProgress in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let days = max(Double(totalDay), 1)
                    let progress = (Double(currentDay) - 1 + Double(dayProgress) / 100) / days
                    // VPReadDeviceBaseDataState: 0 start · 1 reading · 2 complete · 3 invalid.
                    switch state.rawValue {
                    case 0, 1:
                        self.connection = .syncing(progress: min(max(progress, 0), 0.95))
                    case 2:
                        timeout.cancel()
                        once.run { continuation.resume(returning: true) }
                    default:
                        timeout.cancel()
                        once.run { continuation.resume(returning: false) }
                    }
                }
            })
        }
    }

    /// The oxygen / HRV / temperature readers share one callback shape.
    private func readSeries(_ start: (@escaping (VPReadDeviceBaseDataState, UInt, UInt, UInt) -> Void) -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce()
            let timeout = DispatchWorkItem { once.run { continuation.resume() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: timeout)
            start { state, _, _, _ in
                if state.rawValue >= 2 {      // complete or invalid
                    timeout.cancel()
                    once.run { continuation.resume() }
                }
            }
        }
    }

    // MARK: Snapshot

    /// Everything the screens show, rebuilt from the SDK database for the last 14 days.
    func rebuildSnapshot() {
        guard let tableID else { return }
        let now = Date()
        let calendar = Calendar.current
        let profile = profile ?? UserProfile.draft(now: now)
        let days: [Date] = (0..<Baselines.baselineWindow).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: now)) }

        let builder = VeepooNightBuilder(tableID: tableID, profile: profile, capabilities: capabilities)
        let raw = days.compactMap { builder.rawNight(wakeDay: $0) }
        nights = builder.applyBaselines(raw)

        let todayKey = VeepooMappers.queryDateFormatter.string(from: now)
        let origin = (VPDataBaseOperation.veepooSDKGetOriginalData(withDate: todayKey, andTableID: tableID) as? [String: Any]) ?? [:]
        heartRateToday = VeepooMappers.fiveMinuteSeries(origin: origin, day: now, key: "heartValue")
        let halfHour = (VPDataBaseOperation.veepooSDKGetOriginalChangeHalfHourData(withDate: todayKey, andTableID: tableID) as? [String: Any]) ?? [:]
        VPDataBaseOperation.veepooSDKGetStepData(withDate: todayKey, andTableID: tableID, changeUserStature: UInt(profile.heightCm)) { [weak self] dict in
            DispatchQueue.main.async {
                guard let self else { return }
                var day = VeepooMappers.activityDay(stepDict: (dict as? [String: Any]) ?? [:], halfHour: halfHour, date: now, goal: profile.stepGoal)
                let runs = (VPDataBaseOperation.veepooSDKGetDeviceRunningData(withDate: todayKey, andTableID: tableID) as? [[String: Any]]) ?? []
                day.workouts = VeepooMappers.workouts(runs, day: now)
                self.activity = day
                self.today.activity = day
            }
        }

        let stress = capabilities.stress ? VeepooMappers.stressNow(origin: origin, day: now, now: now) : nil
        today = builder.dashboard(now: now, nights: nights, activity: activity, stressNow: stress, lastSync: lastSync)
        timeline = builder.timeline(now: now, lastNight: nights.last, spots: spotMeasurements, lastSync: lastSync)
    }

    // MARK: Power & danger zone

    /// `veepooSDKSettingLowPowerSettingMode:` takes `VPSettingFunctionState` (1 open · 2 close).
    public func setLowPowerMode(_ on: Bool) async {
        guard let peripheral, let mode = VPSettingFunctionState(rawValue: on ? 1 : 2) else { return }
        let done: Bool = await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { once.run { continuation.resume(returning: false) } }
            // VERIFY on device: VPSettingFunctionCompleteState 1 = open, 2 = closed, 3 = failure.
            peripheral.veepooSDKSettingLowPowerSettingMode(mode) { state in once.run { continuation.resume(returning: state.rawValue == (on ? 1 : 2)) } }
        }
        if done { isLowPowerMode = on }
    }

    public func powerOffRing() async {
        peripheral?.veepooSDKPowerOffDevice()
        connection = .notConnected(lastSync: lastSync)
    }

    public func resetRingData() async {
        peripheral?.veepooSDKResetDeviceData()
        nights = []
        heartRateToday = []
        today = .empty(date: Date())
    }
}

/// Resumes a continuation at most once, whichever of callback or timeout fires first.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}

// MARK: - Persistence

/// The few things that must survive a relaunch: which ring, the profile, cached capabilities
/// (so a transient drop does not blank the UI), battery history, spot results and the last sync.
public final class VeepooRingStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func codable<T: Codable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private func set<T: Codable>(_ value: T?, _ key: String) {
        defaults.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }

    public var ringID: String? { get { defaults.string(forKey: "ring.id") } set { defaults.set(newValue, forKey: "ring.id") } }
    public var ringName: String? { get { defaults.string(forKey: "ring.name") } set { defaults.set(newValue, forKey: "ring.name") } }
    public var lastSync: Date? { get { defaults.object(forKey: "ring.lastSync") as? Date } set { defaults.set(newValue, forKey: "ring.lastSync") } }
    public var profile: UserProfile? { get { codable("ring.profile") } set { set(newValue, "ring.profile") } }
    public var capabilities: RingCapabilities? { get { codable("ring.capabilities") } set { set(newValue, "ring.capabilities") } }
    public var batteryHistory: [TimedSample] { get { codable("ring.batteryHistory") ?? [] } set { set(Array(newValue.suffix(84)), "ring.batteryHistory") } }
    public var spotMeasurements: [SpotMeasurement] { get { codable("ring.spots") ?? [] } set { set(Array(newValue.prefix(20)), "ring.spots") } }

    public func clearRing() {
        ringID = nil; ringName = nil; lastSync = nil; capabilities = nil; batteryHistory = []; spotMeasurements = []
    }
}


// MARK: - Commands: battery · spot tests · profile · monitoring

extension VeepooRingDataSource {

    // MARK: Battery

    /// The cheapest proof that the link is alive. `nil` means no answer within 5 s.
    @discardableResult
    func readBattery() async -> Battery? {
        guard let peripheral else { return nil }
        let result: Battery? = await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            let timeout = DispatchWorkItem { once.run { continuation.resume(returning: nil) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
            peripheral.veepooSDKReadDeviceBatteryAndChargeInfo { isPercent, chargeState, isLow, level in
                timeout.cancel()
                let battery = VeepooMappers.battery(isPercent: isPercent, chargeStateRaw: Int(chargeState.rawValue), isLow: isLow, battery: Int(level), forecastNights: nil)
                once.run { continuation.resume(returning: battery) }
            }
        }
        guard var battery = result else { return nil }
        if let percent = battery.percent {
            batteryHistory.append(TimedSample(time: Date(), value: Double(percent)))
            store.batteryHistory = batteryHistory
        }
        battery.forecastNights = battery.isCharging ? nil : Baselines.batteryForecastNights(samples: batteryHistory)
        self.battery = battery
        return battery
    }

    // MARK: Spot tests

    public func startSpot(_ kind: SpotKind) -> AsyncStream<MeasureSessionState> {
        cancelSpot()
        let (stream, continuation) = AsyncStream<MeasureSessionState>.makeStream()
        guard let peripheral, capabilities.supports(kind) else {
            continuation.yield(.failed(connection.isConnected ? "This ring cannot measure \(kind.title.lowercased())" : "Ring not connected"))
            continuation.finish()
            return stream
        }
        if let battery, battery.level == .critical {
            continuation.yield(.lowBattery(percent: battery.percent))
            continuation.finish()
            return stream
        }

        let session = VeepooSpotSession(kind: kind, peripheral: peripheral, batteryPercent: battery?.percent, range: today.vitals.first { $0.kind == kind.vital }?.typicalRange, nights: today.nightsRecorded, continuation: continuation)
        session.start()
        spotTask = Task { [weak session] in
            try? await Task.sleep(nanoseconds: UInt64(kind.durationSeconds * 1e9))
            guard !Task.isCancelled else { return }
            session?.finish(with: .timedOut)
        }
        continuation.onTermination = { _ in session.stopOnRing() }
        return stream
    }

    public func cancelSpot() {
        spotTask?.cancel()
        spotTask = nil
    }

    public func saveSpot(_ measurement: SpotMeasurement) {
        spotMeasurements.insert(measurement, at: 0)
        spotMeasurements = Array(spotMeasurements.prefix(20))
        store.spotMeasurements = spotMeasurements
        timeline.append(DayTimelineItem(id: measurement.id.uuidString, time: measurement.at, kind: .spotTest, title: "\(measurement.kind.title) \(RingFormat.spot(measurement.kind, measurement.value)) \(measurement.unit)".trimmingCharacters(in: .whitespaces), detail: measurement.state.label))
        timeline.sort { $0.time < $1.time }
    }

    // MARK: Profile

    /// Writes age/sex/height/weight/step goal with the long form (which carries stature), and the
    /// sleep goal with `VPSyncPersonalInfo`. Both are sent; the ring keeps the last write of each field.
    public func saveProfile(_ profile: UserProfile) async {
        self.profile = profile
        store.profile = profile
        guard let peripheral, link.handshakeCompleted else { return }

        let birthYear = Calendar.current.component(.year, from: profile.birthDate)
        // VERIFY on device: the SDK has only 0 (female) / 1 (male). "Prefer not to say" is written
        // as 0 so the ring's own estimates err towards the lower-HR model; the app's ranges are
        // personal percentiles and never use sex at all.
        let sex: UInt = profile.sex == .male ? 1 : 0
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { once.run { continuation.resume() } }
            peripheral.veepooSDKSynchronousPersonalInformation(
                withStature: UInt(profile.heightCm.rounded()),
                weight: UInt(profile.weightKg.rounded()),
                birth: UInt(birthYear),
                sex: sex,
                targetStep: UInt(profile.stepGoal)
            ) { _ in once.run { continuation.resume() } }
        }

        let info = VPSyncPersonalInfo()
        info.status = Int32(profile.heightCm.rounded())     // `status` is stature in the header
        info.weight = Int32(profile.weightKg.rounded())
        info.age = Int32(profile.age())
        info.sex = Int32(sex)
        info.targetStep = Int32(profile.stepGoal)
        info.targetSleepDuration = Int32(profile.sleepGoalMin)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { once.run { continuation.resume() } }
            peripheral.veepooSDKSynchronousPersonalInformation(info) { _ in once.run { continuation.resume() } }
        }
    }

    // MARK: Monitoring schedule

    func loadMonitoring() async {
        guard let peripheral else { return }
        let models: [VPAutoMonitTestModel] = await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { once.run { continuation.resume(returning: []) } }
            peripheral.veepooSDKReadAutoMonitSwitchInfo { models in once.run { continuation.resume(returning: models) } }
        }
        monitoring = models.compactMap { model in
            guard let kind = VeepooMappers.monitoringKind(fromAutoMonitType: Int(model.type.rawValue)) else { return nil }
            let window: ClosedRange<ClockTime>? = model.supportRangeTime
                ? ClockTime(hour: Int(model.startHour), minute: Int(model.startMinute))...ClockTime(hour: Int(model.endHour), minute: Int(model.endMinute))
                : nil
            return MonitoringSetting(kind: kind, isOn: model.on, intervalMin: Int(model.timeInterval), minIntervalMin: Int(model.minStepValue), window: window)
        }
    }

    public func setMonitoring(_ kind: MonitoringKind, on: Bool, intervalMin: Int) async {
        guard let peripheral else { return }
        let models: [VPAutoMonitTestModel] = await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { once.run { continuation.resume(returning: []) } }
            peripheral.veepooSDKReadAutoMonitSwitchInfo { models in once.run { continuation.resume(returning: models) } }
        }
        guard let model = models.first(where: { VeepooMappers.monitoringKind(fromAutoMonitType: Int($0.type.rawValue)) == kind }) else { return }
        model.on = on
        model.timeInterval = UInt16(max(intervalMin, Int(model.minStepValue)))
        let success: Bool = await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { once.run { continuation.resume(returning: false) } }
            // VERIFY on device: Swift may import `veepooSDKSetAutoMonitSwitchWithModel:result:` as
            // `veepooSDKSetAutoMonitSwitch(with:result:)`; adjust the label if the compiler objects.
            peripheral.veepooSDKSetAutoMonitSwitch(with: model) { ok, _ in once.run { continuation.resume(returning: ok) } }
        }
        if success, let index = monitoring.firstIndex(where: { $0.kind == kind }) {
            monitoring[index].isOn = on
            monitoring[index].intervalMin = Int(model.timeInterval)
        }
    }
}

// MARK: - Spot session

/// One spot test against the ring. Owns the vendor callback and finishes exactly once.
final class VeepooSpotSession {
    let kind: SpotKind
    let peripheral: VPPeripheralBaseManage
    let batteryPercent: Int?
    let range: ClosedRange<Double>?
    let nights: Int
    private let continuation: AsyncStream<MeasureSessionState>.Continuation
    private let started = Date()
    private var lastValue: Double?
    private var finished = false

    init(kind: SpotKind, peripheral: VPPeripheralBaseManage, batteryPercent: Int?, range: ClosedRange<Double>?, nights: Int, continuation: AsyncStream<MeasureSessionState>.Continuation) {
        self.kind = kind; self.peripheral = peripheral; self.batteryPercent = batteryPercent
        self.range = range; self.nights = nights; self.continuation = continuation
    }

    private var elapsedProgress: Double { min(Date().timeIntervalSince(started) / kind.durationSeconds, 0.98) }

    func start() {
        continuation.yield(.preparing)
        switch kind {
        case .heartRate:
            peripheral.veepooSDKTestHeartStart(true) { [weak self] state, value in
                guard let self else { return }
                if value > 0 { self.lastValue = Double(value) }
                self.handle(VeepooMappers.heartTestState(raw: Int(state.rawValue), value: Int(value), progress: self.elapsedProgress))
            }
        case .bloodOxygen:
            peripheral.veepooSDKTestOxygenStart(true) { [weak self] state, value in
                guard let self else { return }
                if value > 0 { self.lastValue = Double(value) }
                self.handle(VeepooMappers.oxygenTestState(raw: Int(state.rawValue), value: Int(value), progress: self.elapsedProgress))
            }
        case .breathingRate:
            peripheral.veepooSDKTestBreathingRateStart(true) { [weak self] state, progress, value in
                guard let self else { return }
                if value > 0 { self.lastValue = Double(value) }
                self.handle(VeepooMappers.breathingTestState(raw: Int(state.rawValue), progress: Int(progress)))
            }
        case .hrv:
            // VERIFY on device: `veepooSDK_HRVTest:callBack:` — `con` is undocumented; `hrvValue` is
            // taken as the running result and the last non-zero value is reported at `over`.
            peripheral.veepooSDK_HRVTest(true) { [weak self] _, ack, hrvValue in
                guard let self else { return }
                if hrvValue > 0 { self.lastValue = Double(hrvValue) }
                let mapped = VeepooMappers.hrvTestState(raw: Int(ack.rawValue), progress: self.elapsedProgress, batteryPercent: self.batteryPercent)
                self.handle(mapped)
                if self.lastValue != nil, self.elapsedProgress >= 0.5 { self.handle(nil) }
            }
        case .stress:
            peripheral.veepooSDK_stressTestStart(true) { [weak self] state, progress, stress in
                guard let self else { return }
                if stress > 0 { self.lastValue = Double(stress) }
                self.handle(VeepooMappers.stressTestState(raw: Int(state.rawValue), progress: Int(progress), batteryPercent: self.batteryPercent))
            }
        case .skinTemperature:
            // Values are ×0.1 °C. We keep `originalTempValue` (skin), never the body estimate.
            peripheral.veepooSDK_temperatureTestStart(true) { [weak self] state, _, progress, _, originalTempValue in
                guard let self else { return }
                if originalTempValue > 0 { self.lastValue = Double(originalTempValue) / 10 }
                self.handle(VeepooMappers.temperatureTestState(raw: Int(state.rawValue), progress: Int(progress)))
            }
        }
    }

    /// `nil` from a mapper means "the test finished normally": grade the last value.
    private func handle(_ mapped: MeasureSessionState?) {
        guard !finished else { return }
        guard let mapped else {
            guard let value = lastValue else { finish(with: .failed("The ring finished without a reading")); return }
            // Skin temperature is graded as deviation from the overnight baseline, never as an absolute.
            let graded: Double = kind == .skinTemperature ? (range.map { value - ($0.lowerBound + $0.upperBound) / 2 } ?? 0) : value
            let state: RangeState = kind.vital == nil ? .typical : Baselines.rangeState(value: graded, range: range, nights: nights)
            finish(with: .result(SpotMeasurement(kind: kind, value: value, at: Date(), state: state)))
            return
        }
        if mapped.isTerminal { finish(with: mapped) } else { continuation.yield(mapped) }
    }

    func finish(with state: MeasureSessionState) {
        guard !finished else { return }
        finished = true
        continuation.yield(state)
        continuation.finish()
        stopOnRing()
    }

    /// Tells the ring to stop, whatever happened on our side.
    func stopOnRing() {
        DispatchQueue.main.async { [peripheral, kind] in
            switch kind {
            case .heartRate: peripheral.veepooSDKTestHeartStart(false) { _, _ in }
            case .bloodOxygen: peripheral.veepooSDKTestOxygenStart(false) { _, _ in }
            case .breathingRate: peripheral.veepooSDKTestBreathingRateStart(false) { _, _, _ in }
            case .hrv: peripheral.veepooSDK_HRVTest(false, callBack: nil)
            case .stress: peripheral.veepooSDK_stressTestStart(false, result: nil)
            case .skinTemperature: peripheral.veepooSDK_temperatureTestStart(false) { _, _, _, _, _ in }
            }
        }
    }
}

// MARK: - Night builder

struct VeepooNightBuilder {
    let tableID: String
    let profile: UserProfile
    let capabilities: RingCapabilities
    let calendar = Calendar.current

    // MARK: Raw night

    /// One night ending on `wakeDay`, or nil when the ring holds nothing for that day.
    func rawNight(wakeDay: Date) -> RawNight? {
        let key = VeepooMappers.queryDateFormatter.string(from: wakeDay)
        let segments = readSegments(key: key)
        let origin = (VPDataBaseOperation.veepooSDKGetOriginalData(withDate: key, andTableID: tableID) as? [String: Any]) ?? [:]
        let previousDay = calendar.date(byAdding: .day, value: -1, to: wakeDay) ?? wakeDay
        let previousKey = VeepooMappers.queryDateFormatter.string(from: previousDay)
        let previousOrigin = (VPDataBaseOperation.veepooSDKGetOriginalData(withDate: previousKey, andTableID: tableID) as? [String: Any]) ?? [:]

        let heart = VeepooMappers.fiveMinuteSeries(origin: previousOrigin, day: previousDay, key: "heartValue")
            + VeepooMappers.fiveMinuteSeries(origin: origin, day: wakeDay, key: "heartValue")

        let bedtime: Date, wake: Date
        var stages: [SleepStage] = []
        var awakenings = 0, quality: Int?, fallAsleep = 0
        if let main = VeepooMappers.mainSegment(segments), let start = VeepooMappers.timestamp(main.sleepTime), let end = VeepooMappers.timestamp(main.wakeTime) {
            bedtime = start; wake = end
            stages = Baselines.parseSleepLine(dictionaries: main.parsedLine)
            let minutes = max(Int(end.timeIntervalSince(start) / 60), 0)
            if stages.count < minutes { stages += Array(repeating: .gap, count: minutes - stages.count) }
            awakenings = VeepooMappers.int(main.getUpTimes) ?? 0
            quality = VeepooMappers.vendorQuality(main.sleepQuality)
            fallAsleep = max(0, 100 - (VeepooMappers.int(main.fallAsleepScore) ?? 100)) / 4
        } else {
            // No sleep segment: a night the ring did not record. Use the profile's window so the
            // Not-worn card can say between which times.
            bedtime = profile.bedtime.date(on: previousDay)
            wake = profile.wakeTime.date(on: wakeDay)
            guard !heart.contains(where: { $0.time > bedtime && $0.time < wake }) else { return nil }
            let n = RawNight(wakeDay: wakeDay, bedtime: bedtime, wake: wake, stages: Array(repeating: .gap, count: Int(wake.timeIntervalSince(bedtime) / 60)), awakenings: 0, values: [:], series: [:], vendorQuality: 0, lowOxygenEvents: 0, batteryLossAt: nil, notWornRanges: [bedtime...wake], fallAsleepMin: 0)
            return n
        }

        let window = bedtime...wake
        let overnightHeart = heart.filter { window.contains($0.time) }
        let notWorn = VeepooMappers.gaps(in: overnightHeart, window: window)
        let hrv = capabilities.hrv ? VeepooMappers.hrvSeries(dicts(VPDataBaseOperation.veepooSDKGetDeviceHrvData(withDate: key, andTableID: tableID)), day: wakeDay).filter { window.contains($0.time) } : []
        let oxygen = capabilities.spo2 ? VeepooMappers.oxygenNight(dicts(VPDataBaseOperation.veepooSDKGetDeviceOxygenData(withDate: key, andTableID: tableID)), day: wakeDay) : VeepooMappers.OxygenNight(spo2: [], breathing: [], lowOxygenEvents: 0)
        let temp = capabilities.temperature ? VeepooMappers.skinTemperatureSeries(dicts(VPDataBaseOperation.veepooSDKGetDeviceTemperatureData(withDate: key, andTableID: tableID)), day: wakeDay).filter { window.contains($0.time) } : []

        var values: [VitalKind: Double] = [:]
        if let rhr = Baselines.restingHeartRate(fromOvernightMeans: overnightHeart.map { $0.value }) { values[.restingHeartRate] = rhr }
        if !hrv.isEmpty { values[.hrv] = (hrv.map { $0.value }.reduce(0, +) / Double(hrv.count)).rounded() }
        if !oxygen.spo2.isEmpty { values[.spo2] = (oxygen.spo2.map { $0.value }.reduce(0, +) / Double(oxygen.spo2.count)).rounded() }
        if !oxygen.breathing.isEmpty { values[.breathingRate] = ((oxygen.breathing.map { $0.value }.reduce(0, +) / Double(oxygen.breathing.count)) * 10).rounded() / 10 }
        if !temp.isEmpty { values[.skinTempDelta] = temp.map { $0.value }.reduce(0, +) / Double(temp.count) }   // absolute here; made a delta in applyBaselines
        values[.sleepDuration] = Double(stages.filter { $0 != .awake && $0 != .gap }.count)

        // VERIFY on device: battery death is inferred — recording stops well before the wake time
        // AND the next battery read is flat. The SDK has no explicit "powered off at" record.
        var lossAt: Date?
        if let lastHeart = overnightHeart.last?.time, wake.timeIntervalSince(lastHeart) > 2 * 3600, stages.suffix(120).allSatisfy({ $0 == .gap }) {
            lossAt = lastHeart
        }

        return RawNight(
            wakeDay: wakeDay, bedtime: bedtime, wake: wake, stages: stages, awakenings: awakenings,
            values: values,
            series: [.restingHeartRate: overnightHeart, .hrv: hrv, .spo2: oxygen.spo2, .breathingRate: oxygen.breathing, .skinTempDelta: temp],
            vendorQuality: quality ?? 0, lowOxygenEvents: oxygen.lowOxygenEvents, batteryLossAt: lossAt, notWornRanges: notWorn, fallAsleepMin: fallAsleep
        )
    }

    private func dicts(_ array: [Any]?) -> [[String: Any]] {
        (array ?? []).compactMap { $0 as? [String: Any] }
    }

    /// Accurate sleep when the ring supports it, legacy `SLE_LINE` otherwise.
    private func readSegments(key: String) -> [VeepooMappers.SleepSegment] {
        let accurate = (VPDataBaseOperation.veepooSDKGetAccurateSleepData(withDate: key, andTableID: tableID) as [VPAccurateSleepModel]?) ?? []
        if !accurate.isEmpty {
            return accurate.map { model in
                VeepooMappers.SleepSegment(
                    sleepTime: model.sleepTime, wakeTime: model.wakeTime, sleepDuration: model.sleepDuration,
                    getUpTimes: model.getUpTimes, sleepQuality: model.sleepQuality, fallAsleepScore: model.fallAsleepScore,
                    accurateType: model.accurateType,
                    parsedLine: model.parseSleepLine().map { dict in
                        var out: [String: Any] = [:]
                        for (k, v) in dict { if let key = k as? String { out[key] = v } }
                        return out
                    }
                )
            }
        }
        // Legacy dictionaries: expand the 5-minute line into the accurate `{index, type}` shape.
        return dicts(VPDataBaseOperation.veepooSDKGetSleepData(withDate: key, andTableID: tableID)).map { dict in
            let stages = Baselines.parseSleepLine(legacyLine: (dict["SLE_LINE"] as? String) ?? "")
            let codes: [[String: Any]] = stages.enumerated().map { i, stage in
                ["index": i, "type": stage == .deep ? 0 : (stage == .light ? 1 : 4)]
            }
            let hours = VeepooMappers.double(dict["SLE_HOUR"]) ?? 0, minutes = VeepooMappers.double(dict["SLE_MINUTE"]) ?? 0
            return VeepooMappers.SleepSegment(
                sleepTime: (dict["SLEEP_TIME"] as? String) ?? "", wakeTime: (dict["WAKE_TIME"] as? String) ?? "",
                sleepDuration: "\(Int(hours * 60 + minutes))", getUpTimes: "\(VeepooMappers.int(dict["WakeUpTime"]) ?? 0)",
                sleepQuality: "\(max((VeepooMappers.int(dict["SLEEP_LEVEL"]) ?? 1) - 1, 0))", fallAsleepScore: "100", accurateType: "0", parsedLine: codes
            )
        }
    }

    // MARK: Baselines & dashboard

    /// Skin temperature arrives absolute; the tile shows deviation from the user's own baseline.
    func applyBaselines(_ raw: [RawNight]) -> [SleepNight] {
        var adjusted = raw
        let temps = raw.compactMap { $0.values[.skinTempDelta] }
        if temps.count >= 3 {
            let baseline = temps.sorted()[temps.count / 2]
            for i in adjusted.indices {
                if let t = adjusted[i].values[.skinTempDelta] { adjusted[i].values[.skinTempDelta] = ((t - baseline) * 10).rounded() / 10 }
            }
        } else {
            for i in adjusted.indices { adjusted[i].values[.skinTempDelta] = nil }
        }
        return NightAssembly.nights(from: adjusted, profile: profile).map { night in
            var n = night
            n.overnightVitals = n.overnightVitals.filter { capabilities.supports($0.kind) }
            n.isPrecise = capabilities.preciseSleep
            return n
        }
    }

    func dashboard(now: Date, nights: [SleepNight], activity: ActivityDay, stressNow: Int?, lastSync: Date?) -> TodayDashboard {
        let counted = nights.filter { !$0.wasNotWorn && $0.batteryLossAt == nil }.count
        var reason: NoNightReason?
        if let last = nights.last, calendar.isDate(last.date, inSameDayAs: now) {
            if last.wasNotWorn { reason = .notWorn(from: last.notWornRanges.first?.lowerBound, to: last.notWornRanges.first?.upperBound) }
            else if let at = last.batteryLossAt { reason = .batteryRanOut(at: at) }
        } else if lastSync == nil || !(lastSync.map { calendar.isDate($0, inSameDayAs: now) } ?? false) {
            reason = .notSynced
        }
        var dash = NightAssembly.dashboard(now: now, nights: nights, counted: counted, activity: activity, noNight: reason, profile: profile, stressNow: stressNow)
        dash.vitals = dash.vitals.filter { capabilities.supports($0.kind) }
        return dash
    }

    func timeline(now: Date, lastNight: SleepNight?, spots: [SpotMeasurement], lastSync: Date?) -> [DayTimelineItem] {
        var items: [DayTimelineItem] = []
        if let last = lastNight, calendar.isDate(last.date, inSameDayAs: now), !last.wasNotWorn {
            items.append(DayTimelineItem(id: "sleep", time: last.bedtime, kind: .sleep, title: "Slept \(RingFormat.duration(minutes: last.durationMin))", detail: "\(RingFormat.clock(last.bedtime)) → \(RingFormat.clock(last.wake))"))
            if let loss = last.batteryLossAt { items.append(DayTimelineItem(id: "loss", time: loss, kind: .disconnected, title: "Ring ran out", detail: "Recording stopped")) }
        }
        if let lastSync { items.append(DayTimelineItem(id: "sync", time: lastSync, kind: .sync, title: "Synced", detail: nil)) }
        let dayStart = calendar.startOfDay(for: now)
        for spot in spots where spot.at >= dayStart {
            items.append(DayTimelineItem(id: spot.id.uuidString, time: spot.at, kind: .spotTest, title: "\(spot.kind.title) \(RingFormat.spot(spot.kind, spot.value)) \(spot.unit)".trimmingCharacters(in: .whitespaces), detail: spot.state.label))
        }
        return items.sorted { $0.time < $1.time }
    }
}

// MARK: - Pure mappers (no SDK types; raw values from VPPublicDefine.h)

enum VeepooMappers {

    // MARK: Battery

    /// `veepooSDKReadDeviceBatteryAndChargeInfo`: `isPercent`, `VPDeviceChargeState` (0 normal,
    /// 1 charging, 2 low pressure (deprecated), 3 full (unreliable)), `percenTypeIsLowBat`,
    /// `battery` (0–100 when `isPercent`, else 0–4 bars).
    static func battery(isPercent: Bool, chargeStateRaw: Int, isLow: Bool, battery: Int, forecastNights: Double?) -> Battery {
        Battery(
            percent: isPercent ? min(max(battery, 0), 100) : nil,
            bars: isPercent ? nil : min(max(battery, 0), 4),
            isCharging: chargeStateRaw == 1,
            isLow: isLow,
            forecastNights: forecastNights
        )
    }

    // MARK: Capabilities

    /// From `VPPeripheralModel` after `VerifyPasswordSuccess`. Blood pressure, glucose, ECG and the
    /// other non-physical flags are deliberately not parameters: nothing downstream may read them.
    static func capabilities(heartRateType: Int, sleepType: Int, hrvType: Int, isSupportHRVTest: Bool, oxygenType: Int, resRateType: Int, temperatureType: Int, stressType: Int, saveDays: Int) -> RingCapabilities {
        RingCapabilities(
            heartRate: heartRateType != 0,
            hrv: hrvType != 0 || isSupportHRVTest,
            spo2: oxygenType != 0,
            breathingRate: resRateType == 1,
            temperature: temperatureType != 0,
            stress: stressType != 0,
            preciseSleep: sleepType == 1 || sleepType == 3,
            saveDays: saveDays
        )
    }

    // MARK: Time helpers

    static let queryDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `"HH:mm"` on a given calendar day.
    static func time(_ hhmm: String, on day: Date, calendar: Calendar = .current) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    /// The SDK writes sleep timestamps as `yyyy/MM/dd HH:mm` in the legacy dictionaries; the
    /// accurate model's `sleepTime` is a string of the same family. Both spellings are accepted.
    static func timestamp(_ text: String) -> Date? {
        let formats = ["yyyy/MM/dd HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss"]
        for format in formats {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let date = f.date(from: text) { return date }
        }
        return nil
    }

    static func double(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d.isFinite ? d : nil
        case let n as NSNumber: return n.doubleValue
        case let i as Int: return Double(i)
        case let s as String: return Double(s)
        default: return nil
        }
    }

    static func int(_ any: Any?) -> Int? { Baselines.intValue(any) }

    // MARK: Origin (5-minute) data

    /// `veepooSDKGetOriginalDataWithDate`: `{"10:40": {heartValue, stepValue, stress, ...}}`.
    /// A slot that is missing or reads 0 is NOT a sample: the ring was not read or not worn.
    static func fiveMinuteSeries(origin: [String: Any], day: Date, key: String) -> [TimedSample] {
        origin.compactMap { slot, value -> TimedSample? in
            guard let dict = value as? [String: Any], let v = double(dict[key]), v > 0, let t = time(slot, on: day) else { return nil }
            return TimedSample(time: t, value: v)
        }
        .sorted { $0.time < $1.time }
    }

    /// Windows of at least `minimumGapMinutes` with no heart value inside `window`.
    static func gaps(in samples: [TimedSample], window: ClosedRange<Date>, minimumGapMinutes: Int = 30) -> [ClosedRange<Date>] {
        let inside = samples.filter { window.contains($0.time) }.map { $0.time }.sorted()
        var edges = [window.lowerBound] + inside + [window.upperBound]
        edges.sort()
        var ranges: [ClosedRange<Date>] = []
        for i in 1..<edges.count {
            let gap = edges[i].timeIntervalSince(edges[i - 1]) / 60
            if gap >= Double(minimumGapMinutes) { ranges.append(edges[i - 1]...edges[i]) }
        }
        return ranges
    }

    /// Latest smoothed vendor stress index (0–100) from the last hour of origin data.
    static func stressNow(origin: [String: Any], day: Date, now: Date) -> Int? {
        let recent = fiveMinuteSeries(origin: origin, day: day, key: "stress").filter { now.timeIntervalSince($0.time) <= 3600 }
        guard !recent.isEmpty else { return nil }
        return Int((recent.map { $0.value }.reduce(0, +) / Double(recent.count)).rounded())
    }

    // MARK: Steps

    /// `veepooSDKGetStepDataWithDate` → `{Step, Dis (km), Cal (kcal)}` plus the half-hour rollup.
    static func activityDay(stepDict: [String: Any], halfHour: [String: Any], date: Date, goal: Int) -> ActivityDay {
        var buckets = Array(repeating: 0, count: 48)
        for (slot, value) in halfHour {
            guard let dict = value as? [String: Any], let steps = int(dict["stepValue"]) else { continue }
            let parts = slot.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let index = parts[0] * 2 + (parts[1] >= 30 ? 1 : 0)
            if buckets.indices.contains(index) { buckets[index] = steps }
        }
        return ActivityDay(
            date: date,
            steps: int(stepDict["Step"]) ?? buckets.reduce(0, +),
            goal: goal,
            distanceKm: double(stepDict["Dis"]) ?? 0,
            kcal: Int(double(stepDict["Cal"]) ?? 0),
            halfHourSteps: buckets
        )
    }

    /// `veepooSDKGetDeviceRunningDataWithDate` entries.
    static func workouts(_ array: [[String: Any]], day: Date) -> [Workout] {
        array.enumerated().compactMap { index, dict in
            guard int(dict["isHide"]) != 1 else { return nil }
            let start = (dict["beginTime"] as? String).flatMap { timestamp($0) ?? time($0, on: day) } ?? day
            let total = int(dict["totalTime"]) ?? 0
            let mode = int(dict["type"]) ?? 0
            return Workout(id: "\(day.timeIntervalSince1970)-\(index)", name: workoutName(mode: mode), start: start, durationMin: total / 60, kcal: (int(dict["totalCal"]) ?? 0) / 1000, averageHeartRate: int(dict["averHeart"]))
        }
    }

    static func workoutName(mode: Int) -> String {
        switch mode {
        case 1: return "Outdoor run"
        case 2: return "Outdoor walk"
        case 3: return "Indoor run"
        case 4: return "Indoor walk"
        case 5: return "Hike"
        case 6: return "Stepper"
        case 7: return "Outdoor ride"
        case 8: return "Indoor ride"
        case 9: return "Elliptical"
        case 10: return "Rowing"
        default: return "Workout"
        }
    }

    // MARK: HRV · oxygen · temperature

    /// `veepooSDKGetDeviceHrvDataWithDate`: per minute `{time: "HH:mm", hrvValue, hearts: [RR×10ms]}`.
    static func hrvSeries(_ array: [[String: Any]], day: Date) -> [TimedSample] {
        array.compactMap { dict in
            guard let slot = dict["time"] as? String, let t = time(slot, on: day), let v = double(dict["hrvValue"]), v > 0 else { return nil }
            return TimedSample(time: t, value: v)
        }.sorted { $0.time < $1.time }
    }

    struct OxygenNight {
        var spo2: [TimedSample]
        var breathing: [TimedSample]
        var lowOxygenEvents: Int
    }

    /// `veepooSDKGetDeviceOxygenDataWithDate`: `{Time, OxygenValue, RespirationRate, ApneaResult, IsHypoxia, ...}`.
    /// Apnea flags are folded into a wellness "breathing disturbances" count, never a diagnosis.
    static func oxygenNight(_ array: [[String: Any]], day: Date) -> OxygenNight {
        var spo2: [TimedSample] = [], breathing: [TimedSample] = []
        var low = 0
        for dict in array {
            guard let slot = dict["Time"] as? String, let t = time(slot, on: day) else { continue }
            if let v = double(dict["OxygenValue"]), v > 0 {
                spo2.append(TimedSample(time: t, value: v))
                if v < 90 || int(dict["IsHypoxia"]) == 1 { low += 1 }
            }
            if let r = double(dict["RespirationRate"]), r > 0 { breathing.append(TimedSample(time: t, value: r)) }
        }
        return OxygenNight(spo2: spo2.sorted { $0.time < $1.time }, breathing: breathing.sorted { $0.time < $1.time }, lowOxygenEvents: low)
    }

    /// `veepooSDKGetDeviceTemperatureDataWithDate`: `{month, day, hour, minute, value, OriginalValue}`.
    /// We keep the SKIN value (`OriginalValue`) — the estimated body value is never shown.
    static func skinTemperatureSeries(_ array: [[String: Any]], day: Date, calendar: Calendar = .current) -> [TimedSample] {
        array.compactMap { dict in
            guard let hour = int(dict["hour"]), let minute = int(dict["minute"]) else { return nil }
            // VERIFY on device: the original-value key's string is not spelled out in the header
            // comment block; "OriginalValue" mirrors the getter name and "originalValue" is tried too.
            guard let v = double(dict["OriginalValue"]) ?? double(dict["originalValue"]) ?? double(dict["value"]), v > 20, v < 45 else { return nil }
            guard let t = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
            return TimedSample(time: t, value: v)
        }.sorted { $0.time < $1.time }
    }

    // MARK: Sleep

    /// The fields of one `VPAccurateSleepModel` segment, already read out as strings.
    struct SleepSegment {
        var sleepTime: String
        var wakeTime: String
        var sleepDuration: String
        var getUpTimes: String
        var sleepQuality: String
        var fallAsleepScore: String
        var accurateType: String
        /// `parseSleepLine()` output, `[{"index", "type"}]`.
        var parsedLine: [[String: Any]]
    }

    /// Picks the main sleep of the day: the longest segment.
    /// VERIFY on device: segments flagged `lastType == 1` / `nextType == 1` are meant to be joined
    /// with their neighbours; the ring in hand may or may not split nights this way.
    static func mainSegment(_ segments: [SleepSegment]) -> SleepSegment? {
        segments.max { (int($0.sleepDuration) ?? 0) < (int($1.sleepDuration) ?? 0) }
    }

    /// `sleepQuality` is 0–4 stars; scaled to 0–100 for the "ring's estimate".
    static func vendorQuality(_ text: String) -> Int? {
        guard let stars = int(text) else { return nil }
        return min(max(stars, 0), 4) * 25
    }

    // MARK: Spot-test states (raw enum values from VPPublicDefine.h)

    /// `VPTestHeartState`: 0 start · 1 testing · 2 notWear · 3 deviceBusy · 4 over.
    static func heartTestState(raw: Int, value: Int, progress: Double) -> MeasureSessionState? {
        switch raw {
        case 0: return .preparing
        case 1: return .measuring(progress: progress, live: value > 0 ? Double(value) : nil)
        case 2: return .notWorn
        case 3: return .busy
        case 4: return nil          // over: the adapter decides from the last live value
        default: return .failed("Unexpected heart-rate state \(raw)")
        }
    }

    /// `VPTestOxygenState`: 0 start · 1 testing · 2 notWear · 3 busy · 4 over · 5 noFunction ·
    /// 6 calibration · 7 calibrationComplete · 8 invalid.
    static func oxygenTestState(raw: Int, value: Int, progress: Double) -> MeasureSessionState? {
        switch raw {
        case 0, 6, 7: return .preparing
        case 1: return .measuring(progress: progress, live: nil)
        case 2: return .notWorn
        case 3: return .busy
        case 4: return nil
        case 5: return .failed("This ring cannot measure blood oxygen")
        case 8: return .failed("Blood oxygen is temporarily unavailable")
        default: return .failed("Unexpected blood-oxygen state \(raw)")
        }
    }

    /// `VPTestBreathingRateState`: 0 start · 1 testing · 2 notWear · 3 busy · 4 over · 5 complete · 6 failure · 7 noFunction.
    static func breathingTestState(raw: Int, progress: Int) -> MeasureSessionState? {
        switch raw {
        case 0: return .preparing
        case 1: return .measuring(progress: Double(min(max(progress, 0), 100)) / 100, live: nil)
        case 2: return .notWorn
        case 3: return .busy
        case 4, 5: return nil
        case 6: return .failed("The test did not produce a reading")
        case 7: return .failed("This ring cannot measure breathing rate")
        default: return .failed("Unexpected breathing-rate state \(raw)")
        }
    }

    /// `VPTestHRVState`: 0 testing · 1 alreadyStarted · 2 lowPower · 3 deviceBusy · 4 notWear.
    static func hrvTestState(raw: Int, progress: Double, batteryPercent: Int?) -> MeasureSessionState? {
        switch raw {
        case 0: return .measuring(progress: progress, live: nil)
        case 1, 3: return .busy
        case 2: return .lowBattery(percent: batteryPercent)
        case 4: return .notWorn
        default: return .failed("Unexpected HRV state \(raw)")
        }
    }

    /// `VPDeviceStressTestState`: 0 noFunction · 1 busy · 2 over · 3 lowPower · 4 notWear · 5 complete.
    static func stressTestState(raw: Int, progress: Int, batteryPercent: Int?) -> MeasureSessionState? {
        switch raw {
        case 0: return .failed("This ring cannot measure stress")
        case 1: return .busy
        case 2, 5: return nil
        case 3: return .lowBattery(percent: batteryPercent)
        case 4: return .notWorn
        default: return .measuring(progress: Double(min(max(progress, 0), 100)) / 100, live: nil)
        }
    }

    /// `VPTemperatureTestState`: 0 unsupported · 1 open · 2 close · 9 notWear.
    static func temperatureTestState(raw: Int, progress: Int) -> MeasureSessionState? {
        switch raw {
        case 0: return .failed("This ring cannot measure skin temperature")
        case 1: return .measuring(progress: Double(min(max(progress, 0), 100)) / 100, live: nil)
        case 2: return nil
        case 9: return .notWorn
        default: return .failed("Unexpected temperature state \(raw)")
        }
    }

    // MARK: Monitoring

    /// `VPAutoMonitTestType`: 0 HR · 1 BP · 2 glucose · 3 stress · 4 SpO₂ · 5 temperature ·
    /// 6 Lorentz · 7 HRV · 8 blood components. Only the five we show map; the rest return nil.
    static func monitoringKind(fromAutoMonitType raw: Int) -> MonitoringKind? {
        switch raw {
        case 0: return .heartRate
        case 3: return .stress
        case 4: return .bloodOxygen
        case 5: return .skinTemperature
        case 7: return .hrv
        default: return nil
        }
    }
}
#endif
