//
//  MockFixtures.swift
//  RingExperience
//
//  A deterministic 14-night fixture. Same seed, same nights, every run — so previews are stable
//  and tests can assert on values. The generator is shaped like a real sleeper (90-minute
//  cycles, more deep sleep early, more REM late, a couple of awakenings) so the hypnogram and
//  the vitals list look like a night and not like noise.
//

import Foundation

/// Which situation the mock reproduces. Each one is a designed state, not an error.
public enum MockScenario: Equatable, Sendable {
    case established
    case learning(night: Int)
    case notWorn
    case batteryDied
    case unpaired
    case bluetoothOff
}

/// Tiny xorshift generator: deterministic, dependency-free.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 11_400_714_819_323_198_485 : seed }

    mutating func nextUnit() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }

    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * nextUnit() }
    mutating func int(_ lo: Int, _ hi: Int) -> Int { lo + Int(Double(hi - lo + 1) * nextUnit()) }
}

/// Everything the mock publishes, built in one pass.
struct MockSnapshot {
    var connection: RingConnection
    var battery: Battery?
    var capabilities: RingCapabilities
    var today: TodayDashboard
    var nights: [SleepNight]
    var activity: ActivityDay
    var spots: [SpotMeasurement]
    var timeline: [DayTimelineItem]
    var monitoring: [MonitoringSetting]
    var ringName: String?
    var firmware: String?
    var heartRateToday: [TimedSample]
    var batteryHistory: [TimedSample]
}

enum MockFixtures {

    static let calendar = Calendar.current

    static var profile: UserProfile { .demo }

    static let monitoring: [MonitoringSetting] = [
        MonitoringSetting(kind: .heartRate, isOn: true, intervalMin: 5),
        MonitoringSetting(kind: .hrv, isOn: true, intervalMin: 30, window: ClockTime(hour: 0)...ClockTime(hour: 8)),
        MonitoringSetting(kind: .bloodOxygen, isOn: true, intervalMin: 10, window: ClockTime(hour: 0)...ClockTime(hour: 8)),
        MonitoringSetting(kind: .skinTemperature, isOn: true, intervalMin: 5),
        MonitoringSetting(kind: .stress, isOn: false, intervalMin: 30),
    ]

    // MARK: Snapshot

    static func snapshot(scenario: MockScenario, now: Date, profile: UserProfile?) -> MockSnapshot {
        let prof = profile ?? Self.profile
        let todayStart = calendar.startOfDay(for: now)
        let nightCount: Int
        switch scenario {
        case .unpaired: nightCount = 0
        case let .learning(night): nightCount = max(0, min(night, 14))
        default: nightCount = 14
        }

        var rng = SeededRandom(seed: 12_648_430)
        var raw: [RawNight] = (0..<nightCount).map { i in
            rawNight(wakeDay: calendar.date(byAdding: .day, value: i - (nightCount - 1), to: todayStart) ?? todayStart, rng: &rng, profile: prof)
        }

        var noNight: NoNightReason?
        if scenario == .notWorn, let last = raw.last {
            let from = last.bedtime.addingTimeInterval(10 * 60), to = last.wake.addingTimeInterval(-14 * 60)
            raw[raw.count - 1] = notWornVariant(last, from: from, to: to)
            noNight = .notWorn(from: from, to: to)
        }
        if scenario == .batteryDied, let last = raw.last {
            let lossAt = calendar.date(bySettingHour: 2, minute: 14, second: 0, of: last.wake) ?? last.wake
            raw[raw.count - 1] = truncatedVariant(last, at: lossAt)
            noNight = .batteryRanOut(at: lossAt)
        }

        let nights = NightAssembly.nights(from: raw, profile: prof)
        let countedNights = nights.filter { !$0.wasNotWorn && $0.batteryLossAt == nil }.count

        let batteryHistory = Self.batteryHistory(now: now, scenario: scenario)
        let battery = Self.battery(scenario: scenario, history: batteryHistory, now: now)
        let activity = Self.activity(now: now, rng: &rng, profile: prof, scenario: scenario)
        let spots = scenario == .unpaired ? [] : Self.spots(now: now, rng: &rng)
        let hrToday = scenario == .unpaired ? [] : heartRateToday(now: now, rng: &rng, lastNight: nights.last)

        let connection: RingConnection
        switch scenario {
        case .unpaired: connection = .unpaired
        case .bluetoothOff: connection = .bluetoothOff
        default: connection = .connected
        }

        let hour = calendar.component(.hour, from: now)
        let stressNow: Int? = (scenario == .bluetoothOff || scenario == .unpaired || hour < 9) ? nil : 34
        let today = NightAssembly.dashboard(now: now, nights: nights, counted: countedNights, activity: activity, noNight: noNight, profile: prof, stressNow: stressNow, paired: scenario != .unpaired)

        return MockSnapshot(
            connection: connection,
            battery: battery,
            capabilities: scenario == .unpaired ? .none : .all,
            today: today,
            nights: nights,
            activity: activity,
            spots: spots,
            timeline: timeline(now: now, nights: nights, spots: spots, scenario: scenario, noNight: noNight),
            monitoring: monitoring,
            ringName: scenario == .unpaired ? nil : "LOOP-E5FF",
            firmware: scenario == .unpaired ? nil : "2.14.3",
            heartRateToday: hrToday,
            batteryHistory: batteryHistory
        )
    }

    // MARK: Nights

    static func rawNight(wakeDay: Date, rng: inout SeededRandom, profile: UserProfile) -> RawNight {
        let wake = profile.wakeTime.adding(minutes: rng.int(-18, 12)).date(on: wakeDay)
        let inBedMin = 440 + rng.int(-40, 40)
        let bedtime = wake.addingTimeInterval(-Double(inBedMin) * 60)

        // Stages: 15 min settling, then 90-minute cycles that trade deep for REM as the night goes on.
        var stages: [SleepStage] = Array(repeating: .light, count: 15)
        var cycle = 0
        while stages.count < inBedMin {
            let deep = max(8, 32 - cycle * 6), rem = 12 + cycle * 6
            stages += Array(repeating: .light, count: 18)
            stages += Array(repeating: .deep, count: deep)
            stages += Array(repeating: .light, count: 12)
            stages += Array(repeating: .rem, count: rem)
            cycle += 1
        }
        stages = Array(stages.prefix(inBedMin))
        let awakenings = rng.int(1, 3)
        for _ in 0..<awakenings {
            let at = rng.int(60, inBedMin - 30), length = rng.int(3, 14)
            for m in at..<min(at + length, inBedMin) { stages[m] = .awake }
        }

        let rhr = (56 + rng.range(-3, 3)).rounded()
        let hrv = (44 + rng.range(-8, 8)).rounded()
        let spo2 = (96.5 + rng.range(-1.2, 1.0)).rounded()
        let breathing = (14.2 + rng.range(-0.8, 0.8) * 10).rounded() / 10
        let tempDelta = (rng.range(-0.35, 0.35) * 10).rounded() / 10
        let asleep = stages.filter { $0 != .awake }.count

        var series: [VitalKind: [TimedSample]] = [:]
        var hr: [TimedSample] = [], hrvSeries: [TimedSample] = [], ox: [TimedSample] = [], temp: [TimedSample] = [], br: [TimedSample] = []
        var lowOx = 0
        for m in stride(from: 0, to: inBedMin, by: 5) {
            let t = bedtime.addingTimeInterval(Double(m) * 60)
            let stage = stages[m]
            let base = stage == .deep ? rhr : (stage == .awake ? rhr + 14 : rhr + 6)
            hr.append(TimedSample(time: t, value: (base + rng.range(-3, 3)).rounded()))
            hrvSeries.append(TimedSample(time: t, value: (hrv + (stage == .deep ? 8 : 0) + rng.range(-9, 9)).rounded()))
            temp.append(TimedSample(time: t, value: (33.4 + tempDelta + rng.range(-0.15, 0.15) * 10 / 10)))
            br.append(TimedSample(time: t, value: ((breathing + rng.range(-0.6, 0.6)) * 10).rounded() / 10))
            if m % 10 == 0 {
                var value = (spo2 + rng.range(-1.5, 1.0)).rounded()
                if rng.nextUnit() < 0.02 { value = 89 }
                if value < 90 { lowOx += 1 }
                ox.append(TimedSample(time: t, value: value))
            }
        }
        series[.restingHeartRate] = hr; series[.hrv] = hrvSeries; series[.spo2] = ox; series[.skinTempDelta] = temp; series[.breathingRate] = br

        return RawNight(
            wakeDay: wakeDay, bedtime: bedtime, wake: wake, stages: stages, awakenings: awakenings,
            values: [.restingHeartRate: rhr, .hrv: hrv, .spo2: spo2, .breathingRate: breathing, .skinTempDelta: tempDelta, .sleepDuration: Double(asleep)],
            series: series, vendorQuality: rng.int(62, 90), lowOxygenEvents: lowOx, batteryLossAt: nil, notWornRanges: [], fallAsleepMin: rng.int(8, 22)
        )
    }

    static func notWornVariant(_ night: RawNight, from: Date, to: Date) -> RawNight {
        var n = night
        n.stages = Array(repeating: .gap, count: night.stages.count)
        n.values = [:]
        n.series = [:]
        n.awakenings = 0
        n.lowOxygenEvents = 0
        n.notWornRanges = [from...to]
        return n
    }

    static func truncatedVariant(_ night: RawNight, at lossAt: Date) -> RawNight {
        var n = night
        let cut = max(0, Int(lossAt.timeIntervalSince(night.bedtime) / 60))
        for m in min(cut, n.stages.count)..<n.stages.count { n.stages[m] = .gap }
        n.series = n.series.mapValues { $0.filter { $0.time < lossAt } }
        n.values[.sleepDuration] = Double(n.stages.filter { $0 != .awake && $0 != .gap }.count)
        n.values[.hrv] = nil
        n.values[.breathingRate] = nil
        n.batteryLossAt = lossAt
        n.lowOxygenEvents = 0
        return n
    }

}
