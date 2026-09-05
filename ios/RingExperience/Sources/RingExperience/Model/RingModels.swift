//
//  RingModels.swift
//  RingExperience
//
//  The value types every screen renders. Two rules shape them:
//
//  1. HONESTY BY CONSTRUCTION. Values are optional and states are explicit, so a tile can always
//     say "Learning · night 3 of 7", "Not worn" or "Not measured" instead of showing a zero.
//  2. THE RING IS A CHARACTER. Battery, connection and sync are first-class models, not settings.
//

import Foundation

// MARK: - Ring state

/// What the ring reported about its battery. `percent` OR `bars` is set, depending on firmware.
public struct Battery: Equatable, Sendable, Codable {
    public var percent: Int?
    /// 0–4 bars on firmware that does not report a percentage.
    public var bars: Int?
    public var isCharging: Bool
    /// The firmware's own low-battery flag.
    public var isLow: Bool
    /// Nights the charge is forecast to last, from the last 24 h of reads. `nil` until known.
    public var forecastNights: Double?

    public init(percent: Int?, bars: Int? = nil, isCharging: Bool = false, isLow: Bool = false, forecastNights: Double? = nil) {
        self.percent = percent
        self.bars = bars
        self.isCharging = isCharging
        self.isLow = isLow
        self.forecastNights = forecastNights
    }

    public enum Level: Equatable, Sendable { case ok, low, critical, charging }

    /// low < 30 %, critical < 15 %; bars map 0–1 → critical, 2 → low.
    public var level: Level {
        if isCharging { return .charging }
        if let percent {
            if percent < 15 { return .critical }
            if percent < 30 { return .low }
            return .ok
        }
        if let bars {
            if bars <= 1 { return .critical }
            if bars == 2 { return .low }
            return .ok
        }
        return isLow ? .low : .ok
    }

    /// Roughly one night of wear at the ring's overnight sampling rate.
    public var isEnoughForTonight: Bool {
        if let forecastNights { return forecastNights >= 1 }
        if let percent { return percent >= 30 }
        if let bars { return bars >= 2 }
        return !isLow
    }
}

/// The link, as one value. A spinner and an error cannot coexist.
public enum RingConnection: Equatable, Sendable {
    case unpaired
    case connecting
    case connected
    /// Out of range or ring off. The ring keeps recording; `lastSync` is what the phone holds.
    case notConnected(lastSync: Date?)
    case bluetoothOff
    case syncing(progress: Double)

    public var isConnected: Bool {
        switch self {
        case .connected, .syncing: return true
        default: return false
        }
    }
}

/// Which sensors the connected ring reports. Populated after the handshake, cached per ring so
/// a transient drop does not blank the UI. Anything not listed here is never shown.
public struct RingCapabilities: Equatable, Sendable, Codable {
    public var heartRate: Bool
    public var hrv: Bool
    public var spo2: Bool
    public var breathingRate: Bool
    public var temperature: Bool
    public var stress: Bool
    /// REM / awake / insomnia stages available (`sleepType` 1 or 3).
    public var preciseSleep: Bool
    /// Days of history the ring keeps when away from the phone.
    public var saveDays: Int

    public init(heartRate: Bool, hrv: Bool, spo2: Bool, breathingRate: Bool, temperature: Bool, stress: Bool, preciseSleep: Bool, saveDays: Int) {
        self.heartRate = heartRate; self.hrv = hrv; self.spo2 = spo2; self.breathingRate = breathingRate
        self.temperature = temperature; self.stress = stress; self.preciseSleep = preciseSleep; self.saveDays = saveDays
    }

    public static let all = RingCapabilities(heartRate: true, hrv: true, spo2: true, breathingRate: true, temperature: true, stress: true, preciseSleep: true, saveDays: 7)
    public static let none = RingCapabilities(heartRate: false, hrv: false, spo2: false, breathingRate: false, temperature: false, stress: false, preciseSleep: false, saveDays: 0)

    public func supports(_ kind: VitalKind) -> Bool {
        switch kind {
        case .restingHeartRate: return heartRate
        case .hrv: return hrv
        case .spo2: return spo2
        case .breathingRate: return breathingRate || hrv || spo2   // derived overnight from HRV/SpO₂-capable nights
        case .skinTempDelta: return temperature
        case .sleepDuration: return heartRate
        }
    }

    public func supports(_ kind: SpotKind) -> Bool {
        switch kind {
        case .heartRate: return heartRate
        case .bloodOxygen: return spo2
        case .hrv: return hrv
        case .stress: return stress
        case .skinTemperature: return temperature
        case .breathingRate: return breathingRate
        }
    }
}

// MARK: - Vitals

public enum VitalKind: String, CaseIterable, Hashable, Sendable, Identifiable, Codable {
    case restingHeartRate, hrv, spo2, breathingRate, skinTempDelta, sleepDuration
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .restingHeartRate: return "Resting heart rate"
        case .hrv: return "HRV"
        case .spo2: return "Blood oxygen"
        case .breathingRate: return "Breathing rate"
        case .skinTempDelta: return "Skin temperature"
        case .sleepDuration: return "Sleep duration"
        }
    }

    public var unit: String {
        switch self {
        case .restingHeartRate: return "bpm"
        case .hrv: return "ms"
        case .spo2: return "%"
        case .breathingRate: return "brpm"
        case .skinTempDelta: return "°C"
        case .sleepDuration: return "min"
        }
    }

    public var symbol: String {
        switch self {
        case .restingHeartRate: return "heart.fill"
        case .hrv: return "waveform"
        case .spo2: return "drop.fill"
        case .breathingRate: return "wind"
        case .skinTempDelta: return "thermometer.medium"
        case .sleepDuration: return "moon.fill"
        }
    }

    /// Spoken form for VoiceOver: "58 beats per minute".
    public var spokenUnit: String {
        switch self {
        case .restingHeartRate: return "beats per minute"
        case .hrv: return "milliseconds"
        case .spo2: return "percent"
        case .breathingRate: return "breaths per minute"
        case .skinTempDelta: return "degrees from your usual"
        case .sleepDuration: return "of sleep"
        }
    }

    /// Where the number comes from. Every value carries provenance.
    public var provenance: String {
        switch self {
        case .restingHeartRate: return "Lowest stable 5-minute average during sleep"
        case .hrv: return "Heartbeat timing, averaged over the night"
        case .spo2: return "Optical sensor, sampled through the night"
        case .breathingRate: return "Derived from heartbeat timing overnight"
        case .skinTempDelta: return "Finger skin sensor, vs your own baseline"
        case .sleepDuration: return "Time asleep between bedtime and wake"
        }
    }
}

/// Where a value sits against the user's own range.
public enum RangeState: Equatable, Sendable, Codable {
    case typical
    case outsideTypical
    /// Fewer than `needed` nights recorded so far.
    case learning(nights: Int, needed: Int)
    case notMeasured

    /// Exact chip copy from docs/ux/05: Typical · Outside typical · Learning · Not measured.
    public var label: String {
        switch self {
        case .typical: return "Typical"
        case .outsideTypical: return "Outside typical"
        case .learning: return "Learning"
        case .notMeasured: return "Not measured"
        }
    }

    public var metric: RingMetricState {
        switch self {
        case .typical: return .good
        case .outsideTypical: return .fair
        case .learning, .notMeasured: return .abstained
        }
    }

    public var symbol: String {
        switch self {
        case .typical: return "checkmark.circle.fill"
        case .outsideTypical: return "exclamationmark.circle.fill"
        case .learning: return "circle.dotted"
        case .notMeasured: return "minus.circle"
        }
    }

    public var spoken: String {
        switch self {
        case .typical: return "typical for you"
        case .outsideTypical: return "outside your typical range"
        case let .learning(n, needed): return "learning your range, night \(n) of \(needed)"
        case .notMeasured: return "not measured"
        }
    }
}

public struct VitalReading: Equatable, Sendable, Identifiable {
    public var kind: VitalKind
    public var value: Double?
    public var unit: String
    public var state: RangeState
    public var typicalRange: ClosedRange<Double>?
    /// One value per night, oldest first (7 for tiles, 14 for detail).
    public var history: [Double]
    public var measuredAt: Date?

    public var id: VitalKind { kind }

    public init(kind: VitalKind, value: Double?, unit: String? = nil, state: RangeState, typicalRange: ClosedRange<Double>? = nil, history: [Double] = [], measuredAt: Date? = nil) {
        self.kind = kind
        self.value = value
        self.unit = unit ?? kind.unit
        self.state = state
        self.typicalRange = typicalRange
        self.history = history
        self.measuredAt = measuredAt
    }

    public static func notMeasured(_ kind: VitalKind) -> VitalReading {
        VitalReading(kind: kind, value: nil, state: .notMeasured)
    }
}

// MARK: - Scores

public enum ScoreKind: String, CaseIterable, Sendable, Identifiable {
    case readiness, sleep, activity
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .readiness: return "Readiness"
        case .sleep: return "Sleep"
        case .activity: return "Activity"
        }
    }
}

public enum ScoreState: Equatable, Sendable {
    case measured(RingMetricState)
    case learning(nights: Int, needed: Int)
    case abstained(reason: String)
}

public enum Trend: String, Equatable, Sendable {
    case up, steady, down
    public var symbol: String {
        switch self {
        case .up: return "arrow.up"
        case .steady: return "equal"
        case .down: return "arrow.down"
        }
    }
}

/// One input to a score, shown with its own state so the score is explainable.
public struct Contributor: Equatable, Sendable, Identifiable {
    public var name: String
    public var reading: String
    public var state: RangeState
    public var trend: Trend?
    public var id: String { name }
    public init(name: String, reading: String, state: RangeState, trend: Trend? = nil) {
        self.name = name; self.reading = reading; self.state = state; self.trend = trend
    }
}

public struct Score: Equatable, Sendable {
    public var kind: ScoreKind
    public var value: Int?
    public var state: ScoreState
    /// One sentence: "Recovered. HRV above your usual, resting heart rate steady."
    public var caption: String
    public var contributors: [Contributor]

    public init(kind: ScoreKind, value: Int?, state: ScoreState, caption: String, contributors: [Contributor] = []) {
        self.kind = kind; self.value = value; self.state = state; self.caption = caption; self.contributors = contributors
    }

    public static func learning(_ kind: ScoreKind, nights: Int, needed: Int = 7) -> Score {
        Score(kind: kind, value: nil, state: .learning(nights: nights, needed: needed), caption: "Learning your usual · night \(nights) of \(needed)")
    }

    public static func abstained(_ kind: ScoreKind, reason: String) -> Score {
        Score(kind: kind, value: nil, state: .abstained(reason: reason), caption: reason)
    }
}

// MARK: - Sleep

public enum SleepStage: Int, CaseIterable, Hashable, Sendable {
    case deep = 0, light = 1, rem = 2, awake = 4
    /// A minute the ring did not record. Rendered as a gap, never interpolated.
    case gap = -1

    public var label: String {
        switch self {
        case .deep: return "Deep"
        case .light: return "Light"
        case .rem: return "REM"
        case .awake: return "Awake"
        case .gap: return "No data"
        }
    }

    /// Hypnogram lane, top to bottom: Awake · REM · Light · Deep.
    public static let lanes: [SleepStage] = [.awake, .rem, .light, .deep]
}

public struct TimedSample: Equatable, Sendable, Identifiable, Codable {
    public var time: Date
    public var value: Double
    public var id: Date { time }
    public init(time: Date, value: Double) { self.time = time; self.value = value }
}

public struct SleepNight: Equatable, Sendable, Identifiable {
    /// The calendar day the user woke up on.
    public var date: Date
    public var bedtime: Date
    public var wake: Date
    public var durationMin: Int
    /// One entry per minute from `bedtime`. `.gap` where the ring recorded nothing.
    public var stages: [SleepStage]
    public var stageTotals: [SleepStage: Int]
    public var awakenings: Int
    public var score: Score
    public var contributors: [Contributor]
    public var overnightVitals: [VitalReading]
    /// Per-vital overnight series for the vitals list.
    public var series: [VitalKind: [TimedSample]]
    /// When the ring's battery died during the night, if it did.
    public var batteryLossAt: Date?
    /// Windows the ring was off the finger.
    public var notWornRanges: [ClosedRange<Date>]
    /// Dips below 90 % SpO₂ — shown as "breathing disturbances", a wellness estimate.
    public var lowOxygenEvents: Int
    public var isPrecise: Bool
    /// The ring's own 0–100 estimate, shown as "ring's estimate" until 7 nights of ours exist.
    public var vendorQuality: Int?

    public var id: Date { date }

    public init(date: Date, bedtime: Date, wake: Date, durationMin: Int, stages: [SleepStage], stageTotals: [SleepStage: Int], awakenings: Int, score: Score, contributors: [Contributor], overnightVitals: [VitalReading], series: [VitalKind: [TimedSample]] = [:], batteryLossAt: Date? = nil, notWornRanges: [ClosedRange<Date>] = [], lowOxygenEvents: Int = 0, isPrecise: Bool = true, vendorQuality: Int? = nil) {
        self.date = date; self.bedtime = bedtime; self.wake = wake; self.durationMin = durationMin
        self.stages = stages; self.stageTotals = stageTotals; self.awakenings = awakenings; self.score = score
        self.contributors = contributors; self.overnightVitals = overnightVitals; self.series = series
        self.batteryLossAt = batteryLossAt; self.notWornRanges = notWornRanges; self.lowOxygenEvents = lowOxygenEvents
        self.isPrecise = isPrecise; self.vendorQuality = vendorQuality
    }

    /// True when the ring was not worn for (nearly) the whole window.
    public var wasNotWorn: Bool {
        let worn = stages.filter { $0 != .gap }.count
        return stages.isEmpty || Double(worn) / Double(max(stages.count, 1)) < 0.1
    }

    public func vital(_ kind: VitalKind) -> VitalReading? {
        overnightVitals.first { $0.kind == kind }
    }
}

public struct SleepDebt: Equatable, Sendable {
    public var needMin: Int
    public var totalMin: Int
    public var nights: Int
    public var deltaMin: Int { totalMin - needMin * nights }
    public enum Level: Sendable { case none, building, high }
    public var level: Level {
        if deltaMin >= -30 { return .none }
        if deltaMin >= -180 { return .building }
        return .high
    }
    public init(needMin: Int, totalMin: Int, nights: Int) { self.needMin = needMin; self.totalMin = totalMin; self.nights = nights }
}

// MARK: - Activity

public struct Workout: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var start: Date
    public var durationMin: Int
    public var kcal: Int
    public var averageHeartRate: Int?
    public init(id: String, name: String, start: Date, durationMin: Int, kcal: Int, averageHeartRate: Int?) {
        self.id = id; self.name = name; self.start = start; self.durationMin = durationMin; self.kcal = kcal; self.averageHeartRate = averageHeartRate
    }
}

public struct ActivityDay: Equatable, Sendable {
    public var date: Date
    public var steps: Int
    public var goal: Int
    public var distanceKm: Double
    public var kcal: Int
    /// 48 buckets, 00:00 → 23:30.
    public var halfHourSteps: [Int]
    public var workouts: [Workout]
    public var goalFraction: Double { goal > 0 ? min(Double(steps) / Double(goal), 1) : 0 }
    public init(date: Date, steps: Int, goal: Int, distanceKm: Double, kcal: Int, halfHourSteps: [Int], workouts: [Workout] = []) {
        self.date = date; self.steps = steps; self.goal = goal; self.distanceKm = distanceKm; self.kcal = kcal; self.halfHourSteps = halfHourSteps; self.workouts = workouts
    }
    public static func empty(date: Date, goal: Int = 8000) -> ActivityDay {
        ActivityDay(date: date, steps: 0, goal: goal, distanceKm: 0, kcal: 0, halfHourSteps: Array(repeating: 0, count: 48))
    }
}

