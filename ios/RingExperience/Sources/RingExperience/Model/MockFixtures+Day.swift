//
//  MockFixtures+Day.swift
//  RingExperience
//
//  The daytime half of the fixture: the dashboard, battery, activity, spot tests, today's heart
//  rate line and the day timeline.
//

import Foundation

extension MockFixtures {

    // MARK: Dashboard

    // MARK: Battery

    static func batteryHistory(now: Date, scenario: MockScenario) -> [TimedSample] {
        guard scenario != .unpaired else { return [] }
        var samples: [TimedSample] = []
        var level = 100.0
        var t = now.addingTimeInterval(-7 * 86_400)
        while t <= now {
            level -= 1.8      // 0.9 % per hour, sampled every 2 h
            if level < 12 { level = 100 }
            samples.append(TimedSample(time: t, value: level.rounded()))
            t = t.addingTimeInterval(7_200)
        }
        if scenario == .batteryDied {
            // The last reads slide to zero at 02:14 and the ring has been off since.
            samples = samples.map { $0.time > now.addingTimeInterval(-6 * 3600) ? TimedSample(time: $0.time, value: max($0.value - 60, 0)) : $0 }
        }
        return samples
    }

    static func battery(scenario: MockScenario, history: [TimedSample], now: Date) -> Battery? {
        switch scenario {
        case .unpaired: return nil
        case .batteryDied: return Battery(percent: 6, isCharging: false, isLow: true, forecastNights: 0)
        case .bluetoothOff: return Battery(percent: 58, isCharging: false, isLow: false, forecastNights: 2.4)
        default:
            let percent = Int(history.last?.value ?? 64)
            return Battery(percent: percent, isCharging: false, isLow: percent < 20, forecastNights: Baselines.batteryForecastNights(samples: history, now: now))
        }
    }

    // MARK: Activity

    static func activity(now: Date, rng: inout SeededRandom, profile: UserProfile, scenario: MockScenario) -> ActivityDay {
        guard scenario != .unpaired else { return .empty(date: now, goal: profile.stepGoal) }
        let nowBucket = Calendar.current.component(.hour, from: now) * 2 + (Calendar.current.component(.minute, from: now) >= 30 ? 1 : 0)
        var buckets = Array(repeating: 0, count: 48)
        for b in 0..<48 where b <= nowBucket {
            let hour = Double(b) / 2
            let shape = max(0, sin((hour - 7) / 16 * .pi)) * (hour >= 7 ? 1 : 0)
            let burst = (b == 17 || b == 18 || b == 36) ? 900 : 0
            buckets[b] = Int(shape * 360 + Double(burst) + rng.range(0, 80))
        }
        let steps = buckets.reduce(0, +)
        let workouts = nowBucket >= 19 ? [Workout(id: "walk-1", name: "Walk", start: Calendar.current.date(bySettingHour: 8, minute: 40, second: 0, of: now) ?? now, durationMin: 32, kcal: 148, averageHeartRate: 104)] : []
        return ActivityDay(date: now, steps: steps, goal: profile.stepGoal, distanceKm: Double(steps) * 0.00072, kcal: Int(Double(steps) * 0.04), halfHourSteps: buckets, workouts: workouts)
    }

    // MARK: Spot tests

    static func spots(now: Date, rng: inout SeededRandom) -> [SpotMeasurement] {
        let plan: [(SpotKind, Double, Double)] = [
            (.heartRate, 3.2, 71), (.bloodOxygen, 3.5, 97), (.stress, 22, 31),
            (.hrv, 27, 41), (.skinTemperature, 28, 33.6), (.heartRate, 49, 68), (.breathingRate, 51, 14.5),
        ]
        return plan.map { kind, hoursAgo, value in
            SpotMeasurement(kind: kind, value: value + (rng.range(-1, 1)).rounded(), at: now.addingTimeInterval(-hoursAgo * 3600), state: .typical)
        }.sorted { $0.at > $1.at }
    }

    // MARK: Today's heart rate

    static func heartRateToday(now: Date, rng: inout SeededRandom, lastNight: SleepNight?) -> [TimedSample] {
        let start = Calendar.current.startOfDay(for: now)
        let rhr = lastNight?.vital(.restingHeartRate)?.value ?? 57
        var samples: [TimedSample] = []
        var t = start
        while t <= now {
            let hour = t.timeIntervalSince(start) / 3600
            // A 30-minute gap after waking: the ring was on the charger. Gaps are gaps.
            let onCharger = hour >= 7.4 && hour < 7.9
            if !onCharger {
                let asleep = lastNight.map { t < $0.wake && !$0.wasNotWorn } ?? (hour < 7)
                let base = asleep ? rhr + 5 : (hour < 9 ? rhr + 22 : rhr + 18 + 12 * sin((hour - 9) / 10 * .pi))
                samples.append(TimedSample(time: t, value: (base + rng.range(-4, 4)).rounded()))
            }
            t = t.addingTimeInterval(300)
        }
        return samples
    }

    // MARK: Timeline

    static func timeline(now: Date, nights: [SleepNight], spots: [SpotMeasurement], scenario: MockScenario, noNight: NoNightReason?) -> [DayTimelineItem] {
        guard scenario != .unpaired else { return [] }
        var items: [DayTimelineItem] = []
        let dayStart = Calendar.current.startOfDay(for: now)
        if let last = nights.last {
            switch noNight {
            case let .notWorn(from, to):
                items.append(DayTimelineItem(id: "notworn", time: from ?? last.bedtime, kind: .notWorn, title: "Ring not worn", detail: to.map { "Until \(RingFormat.clock($0))" }))
            case let .batteryRanOut(at):
                items.append(DayTimelineItem(id: "sleep", time: last.bedtime, kind: .sleep, title: "Asleep", detail: "From \(RingFormat.clock(last.bedtime))"))
                items.append(DayTimelineItem(id: "dead", time: at, kind: .disconnected, title: "Ring ran out", detail: "Recording stopped"))
            default:
                items.append(DayTimelineItem(id: "sleep", time: last.bedtime, kind: .sleep, title: "Slept \(RingFormat.duration(minutes: last.durationMin))", detail: "\(RingFormat.clock(last.bedtime)) → \(RingFormat.clock(last.wake))"))
                items.append(DayTimelineItem(id: "sync", time: last.wake.addingTimeInterval(6 * 60), kind: .sync, title: "Synced last night", detail: "\(nights.count) nights on your phone"))
            }
        }
        if scenario == .established || scenario == .bluetoothOff {
            items.append(DayTimelineItem(id: "charge", time: dayStart.addingTimeInterval(7.4 * 3600), kind: .charging, title: "On charger", detail: "30 minutes"))
        }
        if scenario == .bluetoothOff {
            items.append(DayTimelineItem(id: "bt", time: now.addingTimeInterval(-40 * 60), kind: .disconnected, title: "Bluetooth turned off", detail: "Ring keeps recording"))
        }
        for spot in spots where spot.at >= dayStart {
            items.append(DayTimelineItem(id: spot.id.uuidString, time: spot.at, kind: .spotTest, title: "\(spot.kind.title) \(RingFormat.spot(spot.kind, spot.value)) \(spot.kind.unit)".trimmingCharacters(in: .whitespaces), detail: spot.state.label))
        }
        return items.filter { $0.time >= dayStart.addingTimeInterval(-3 * 3600) }.sorted { $0.time < $1.time }
    }
}
