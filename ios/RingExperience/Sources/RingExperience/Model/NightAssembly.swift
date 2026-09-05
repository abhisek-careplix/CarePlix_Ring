//
//  NightAssembly.swift
//  RingExperience
//
//  Turns raw nights into what the screens show: `SleepNight`s with typical ranges built from the
//  nights before each, a readiness score per night, and the Today dashboard. Shared by the mock
//  fixture and the vendor adapter so both produce identical treatment for identical input.
//

import Foundation

/// A night as read from the ring, before baselines are applied. Built by the vendor adapter
/// (from the SDK database) and by the mock fixture alike.
public struct RawNight: Sendable {
    public var wakeDay: Date
    public var bedtime: Date
    public var wake: Date
    public var stages: [SleepStage]
    public var awakenings: Int
    public var values: [VitalKind: Double]
    public var series: [VitalKind: [TimedSample]]
    public var vendorQuality: Int
    public var lowOxygenEvents: Int
    public var batteryLossAt: Date?
    public var notWornRanges: [ClosedRange<Date>]
    public var fallAsleepMin: Int

    public init(wakeDay: Date, bedtime: Date, wake: Date, stages: [SleepStage], awakenings: Int, values: [VitalKind: Double], series: [VitalKind: [TimedSample]], vendorQuality: Int, lowOxygenEvents: Int, batteryLossAt: Date?, notWornRanges: [ClosedRange<Date>], fallAsleepMin: Int) {
        self.wakeDay = wakeDay; self.bedtime = bedtime; self.wake = wake; self.stages = stages; self.awakenings = awakenings
        self.values = values; self.series = series; self.vendorQuality = vendorQuality; self.lowOxygenEvents = lowOxygenEvents
        self.batteryLossAt = batteryLossAt; self.notWornRanges = notWornRanges; self.fallAsleepMin = fallAsleepMin
    }
}


public enum NightAssembly {

    /// Turns raw nights into `SleepNight`s with typical ranges built from the nights before each.
    public static func nights(from raw: [RawNight], profile: UserProfile) -> [SleepNight] {
        var nights: [SleepNight] = []
        for (i, night) in raw.enumerated() {
            let counted = i + 1
            let vitals: [VitalReading] = VitalKind.allCases.map { kind in
                let history = raw[max(0, i - 13)...i].compactMap { $0.values[kind] }
                let range = Baselines.typicalRange(from: history)
                let value = night.values[kind]
                return VitalReading(kind: kind, value: value, state: Baselines.rangeState(value: value, range: range, nights: counted), typicalRange: range, history: Array(history.suffix(7)), measuredAt: night.wake)
            }
            let asleep = night.stages.filter { $0 != .awake && $0 != .gap }.count
            let inBed = night.stages.filter { $0 != .gap }.count
            let efficiency = inBed > 0 ? Double(asleep) / Double(inBed) : 0

            let sleepScore: Score
            if night.notWornRanges.isEmpty == false {
                sleepScore = .abstained(.sleep, reason: "Ring not worn")
            } else if night.batteryLossAt != nil {
                sleepScore = .abstained(.sleep, reason: "Partial night · ring ran out at \(RingFormat.clock(night.batteryLossAt ?? night.wake))")
            } else {
                let value = Baselines.sleepScore(vendorQuality: night.vendorQuality, durationMin: asleep, needMin: profile.sleepGoalMin, awakenings: night.awakenings, efficiency: efficiency)
                let caption = counted < Baselines.nightsNeeded ? "Ring's estimate · night \(counted) of \(Baselines.nightsNeeded)" : sleepCaption(score: value, night: night, deepShare: Double(night.stages.filter { $0 == .deep }.count) / Double(max(asleep, 1)))
                sleepScore = Score(kind: .sleep, value: value, state: .measured(.grade(score: value)), caption: caption)
            }

            let bedtimes = raw[max(0, i - 6)...i].map { Double(ClockTime(date: $0.bedtime).minutesSinceMidnight) }
            let bedSpread = (bedtimes.max() ?? 0) - (bedtimes.min() ?? 0)
            let contributors = [
                Contributor(name: "Duration vs need", reading: "\(RingFormat.duration(minutes: asleep)) of \(RingFormat.duration(minutes: profile.sleepGoalMin))", state: asleep >= profile.sleepGoalMin - 30 ? .typical : .outsideTypical),
                Contributor(name: "Efficiency", reading: "\(Int((efficiency * 100).rounded())) %", state: efficiency >= 0.85 ? .typical : .outsideTypical),
                Contributor(name: "Awakenings", reading: "\(night.awakenings)", state: night.awakenings <= 2 ? .typical : .outsideTypical),
                Contributor(name: "Time to fall asleep", reading: "\(night.fallAsleepMin) min", state: night.fallAsleepMin <= 25 ? .typical : .outsideTypical),
                Contributor(name: "Regularity", reading: "±\(Int(bedSpread / 2)) min bedtime", state: counted < 7 ? .learning(nights: counted, needed: 7) : (bedSpread <= 60 ? .typical : .outsideTypical)),
            ]

            nights.append(SleepNight(
                date: night.wakeDay, bedtime: night.bedtime, wake: night.wake, durationMin: asleep,
                stages: night.stages, stageTotals: Baselines.stageTotals(night.stages), awakenings: night.awakenings,
                score: sleepScore, contributors: contributors, overnightVitals: vitals, series: night.series,
                batteryLossAt: night.batteryLossAt, notWornRanges: night.notWornRanges, lowOxygenEvents: night.lowOxygenEvents,
                isPrecise: true, vendorQuality: night.vendorQuality
            ))
        }
        return nights
    }

    static func sleepCaption(score: Int, night: RawNight, deepShare: Double) -> String {
        let lead = score >= 80 ? "Solid night." : score >= 65 ? "Decent night." : "Light night."
        let deep = deepShare > 0.2 ? "More deep sleep than usual" : "Deep sleep about usual"
        let wake = night.awakenings > 1 ? ", \(night.awakenings) awakenings." : "."
        return "\(lead) \(deep)\(wake)"
    }

    /// Readiness for a night, computed the same way the real data source does it.
    public static func readiness(for night: SleepNight, counted: Int) -> Score {
        if night.wasNotWorn { return .abstained(.readiness, reason: "No night recorded") }
        if night.batteryLossAt != nil { return .abstained(.readiness, reason: "Partial night") }
        return Baselines.readiness(from: Baselines.ReadinessInputs(
            nights: counted,
            hrv: night.vital(.hrv),
            restingHeartRate: night.vital(.restingHeartRate),
            sleepScore: night.score.value,
            skinTempDelta: night.vital(.skinTempDelta),
            breathingRate: night.vital(.breathingRate)
        ))
    }

    /// The Today snapshot from assembled nights. `stressNow` is the caller's (vendor origin data
    /// smoothed, or nil), because the assembly never invents a daytime number.
    public static func dashboard(now: Date, nights: [SleepNight], counted: Int, activity: ActivityDay, noNight: NoNightReason?, profile: UserProfile, stressNow: Int?, paired: Bool = true) -> TodayDashboard {
        guard let last = nights.last, paired else {
            var empty = TodayDashboard.empty(date: now)
            empty.activity = activity
            return empty
        }
        let readiness = readiness(for: last, counted: counted)
        let vitals: [VitalReading] = noNight == nil
            ? last.overnightVitals
            : VitalKind.allCases.map { kind in
                // A partial night still has measured values for some vitals; keep those honest.
                let reading = last.vital(kind)
                return reading?.value == nil ? .notMeasured(kind) : reading!
            }
        let activityValue = Int((activity.goalFraction * 100).rounded())
        let activityScore = Score(kind: .activity, value: activityValue, state: .measured(.grade(score: max(activityValue, 40))), caption: "\(RingFormat.steps(activity.steps)) of \(RingFormat.steps(activity.goal)) steps")
        let debt = Baselines.sleepDebt(needMin: profile.sleepGoalMin, totals: nights.filter { !$0.wasNotWorn }.map { $0.durationMin })
        let week = Array(nights.suffix(7))
        let weekly = WeeklySummary(
            sleepMinutes: week.map { $0.durationMin },
            readiness: week.enumerated().map { readiness(for: $0.element, counted: counted - (week.count - 1 - $0.offset)).value },
            restingHeartRate: week.map { $0.vital(.restingHeartRate)?.value },
            hrv: week.map { $0.vital(.hrv)?.value },
            nightsOutsideTypical: week.filter { n in n.overnightVitals.filter { $0.state == .outsideTypical }.count >= 2 }.count
        )
        return TodayDashboard(
            date: now,
            readiness: readiness,
            sleep: last.score,
            activityScore: activityScore,
            vitals: vitals,
            stressNow: stressNow,
            activity: activity,
            nightsRecorded: counted,
            lastNight: last,
            noNightReason: noNight,
            sleepDebt: debt,
            weekly: weekly
        )
    }

}
