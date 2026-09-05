//
//  RingProfileModels.swift
//  RingExperience
//
//  The user, the day's story, and the one time-aware answer Today opens with.
//
//  Every profile answer is USED: age/sex/height/weight are written to the ring; hand and finger
//  drive wear-detection copy; bedtime and wake drive the evening hero and the charge reminder;
//  the sleep goal drives Sleep Debt. Nothing is asked that is not used.
//

import Foundation

// MARK: - Clock time

/// A wall-clock time without a date, for bedtime, wake time and monitoring windows.
public struct ClockTime: Equatable, Hashable, Comparable, Sendable, Codable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    /// The most recent occurrence of this time on or before `date`'s calendar day.
    public func date(on date: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? date
    }

    public func adding(minutes: Int) -> ClockTime {
        let total = ((minutesSinceMidnight + minutes) % 1440 + 1440) % 1440
        return ClockTime(hour: total / 60, minute: total % 60)
    }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }
}

// MARK: - Profile

public enum Sex: String, CaseIterable, Sendable, Codable, Identifiable {
    case female, male, preferNotToSay
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
}

public enum WearHand: String, CaseIterable, Sendable, Codable, Identifiable {
    case left, right
    public var id: String { rawValue }
    public var label: String { self == .left ? "Left" : "Right" }
}

public enum WearFinger: String, CaseIterable, Sendable, Codable, Identifiable {
    case index, middle, ring
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .index: return "Index"
        case .middle: return "Middle"
        case .ring: return "Ring"
        }
    }
}

public enum Units: String, CaseIterable, Sendable, Codable, Identifiable {
    case metric, imperial
    public var id: String { rawValue }
    public var label: String { self == .metric ? "cm · kg" : "ft · lb" }
}

public struct UserProfile: Equatable, Sendable, Codable {
    public var name: String?
    public var birthDate: Date
    public var sex: Sex
    public var heightCm: Double
    public var weightKg: Double
    public var wearHand: WearHand
    public var wearFinger: WearFinger
    public var bedtime: ClockTime
    public var wakeTime: ClockTime
    /// Sleep need. Default 7 h 30.
    public var sleepGoalMin: Int
    public var units: Units
    public var stepGoal: Int

    public init(name: String? = nil, birthDate: Date, sex: Sex, heightCm: Double, weightKg: Double, wearHand: WearHand = .left, wearFinger: WearFinger = .index, bedtime: ClockTime = ClockTime(hour: 23), wakeTime: ClockTime = ClockTime(hour: 7), sleepGoalMin: Int = 450, units: Units = .metric, stepGoal: Int = 8000) {
        self.name = name; self.birthDate = birthDate; self.sex = sex; self.heightCm = heightCm; self.weightKg = weightKg
        self.wearHand = wearHand; self.wearFinger = wearFinger; self.bedtime = bedtime; self.wakeTime = wakeTime
        self.sleepGoalMin = sleepGoalMin; self.units = units; self.stepGoal = stepGoal
    }

    /// Sensible starting values for onboarding.
    public static func draft(now: Date = Date()) -> UserProfile {
        let thirty = Calendar.current.date(byAdding: .year, value: -30, to: now) ?? now
        return UserProfile(birthDate: thirty, sex: .preferNotToSay, heightCm: 170, weightKg: 70)
    }

    public func age(at date: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.year], from: birthDate, to: date).year ?? 0
    }
}

// MARK: - Day timeline

public struct DayTimelineItem: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case sync, spotTest, sleep, charging, disconnected, notWorn, chargeReminder

        public var symbol: String {
            switch self {
            case .sync: return "arrow.triangle.2.circlepath"
            case .spotTest: return "waveform.path"
            case .sleep: return "moon.fill"
            case .charging: return "bolt.fill"
            case .disconnected: return "antenna.radiowaves.left.and.right.slash"
            case .notWorn: return "hand.raised.slash"
            case .chargeReminder: return "battery.25percent"
            }
        }
    }

    public var id: String
    public var time: Date
    public var kind: Kind
    public var title: String
    public var detail: String?

    public init(id: String, time: Date, kind: Kind, title: String, detail: String? = nil) {
        self.id = id; self.time = time; self.kind = kind; self.title = title; self.detail = detail
    }
}

// MARK: - Today

/// Why there is no night to show. Every case has a reason and one verb.
public enum NoNightReason: Equatable, Sendable {
    case notWorn(from: Date?, to: Date?)
    case batteryRanOut(at: Date)
    case notSynced

    public var headline: String { "No night recorded" }

    public var body: String {
        switch self {
        case let .notWorn(from, to):
            if let from, let to {
                return "Your ring wasn't on your finger between \(RingFormat.clock(from)) and \(RingFormat.clock(to))."
            }
            return "Your ring wasn't on your finger last night."
        case let .batteryRanOut(at):
            return "Your ring ran out at \(RingFormat.clock(at)). Charge it now and tonight is covered."
        case .notSynced:
            return "Last night is still on your ring."
        }
    }

    public var actionTitle: String {
        switch self {
        case .notWorn: return "See how to wear it"
        case .batteryRanOut: return "Charge now"
        case .notSynced: return "Sync"
        }
    }
}

/// The one thing Today leads with. Selected by `RingDataSource.heroNow(at:)`.
public enum TodayHero: Equatable, Sendable {
    case morning(Score)
    case afternoonStress(Int)
    case afternoonActivity(ActivityDay)
    case evening(bedtime: ClockTime, battery: Battery?)
    case learning(nights: Int)
    case noNight(NoNightReason)
    case unpaired
}

public struct WeeklySummary: Equatable, Sendable {
    public var sleepMinutes: [Int]
    public var readiness: [Int?]
    public var restingHeartRate: [Double?]
    public var hrv: [Double?]
    public var nightsOutsideTypical: Int
    public init(sleepMinutes: [Int], readiness: [Int?], restingHeartRate: [Double?], hrv: [Double?], nightsOutsideTypical: Int) {
        self.sleepMinutes = sleepMinutes; self.readiness = readiness; self.restingHeartRate = restingHeartRate; self.hrv = hrv; self.nightsOutsideTypical = nightsOutsideTypical
    }
}

/// Everything Today renders, assembled once per sync.
public struct TodayDashboard: Equatable, Sendable {
    public var date: Date
    public var readiness: Score
    public var sleep: Score
    public var activityScore: Score
    /// Capability-gated by the data source; tiles render exactly this list.
    public var vitals: [VitalReading]
    /// Vendor stress index from origin data, smoothed. "From heartbeat timing", wellness only.
    public var stressNow: Int?
    public var activity: ActivityDay
    public var nightsRecorded: Int
    public var lastNight: SleepNight?
    public var noNightReason: NoNightReason?
    public var sleepDebt: SleepDebt?
    public var weekly: WeeklySummary?

    public init(date: Date, readiness: Score, sleep: Score, activityScore: Score, vitals: [VitalReading], stressNow: Int?, activity: ActivityDay, nightsRecorded: Int, lastNight: SleepNight?, noNightReason: NoNightReason?, sleepDebt: SleepDebt? = nil, weekly: WeeklySummary? = nil) {
        self.date = date; self.readiness = readiness; self.sleep = sleep; self.activityScore = activityScore; self.vitals = vitals
        self.stressNow = stressNow; self.activity = activity; self.nightsRecorded = nightsRecorded; self.lastNight = lastNight
        self.noNightReason = noNightReason; self.sleepDebt = sleepDebt; self.weekly = weekly
    }

    public static func empty(date: Date) -> TodayDashboard {
        TodayDashboard(
            date: date,
            readiness: .learning(.readiness, nights: 0),
            sleep: .learning(.sleep, nights: 0),
            activityScore: .abstained(.activity, reason: "No steps yet"),
            vitals: [],
            stressNow: nil,
            activity: .empty(date: date),
            nightsRecorded: 0,
            lastNight: nil,
            noNightReason: nil
        )
    }
}
