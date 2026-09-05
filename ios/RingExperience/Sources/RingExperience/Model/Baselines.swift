//
//  Baselines.swift
//  RingExperience
//
//  Every derived metric, as a pure function. Nothing here touches the ring or the UI.
//
//  THE RULES (docs/ux/03 §5)
//  - Typical range: rolling 14 nights, 10th–90th percentile, needs 7 nights. Apple-style
//    "Typical / Outside typical" — never a diagnosis.
//  - Readiness abstains under 7 nights; each contributor carries its own state.
//  - Resting HR is the lowest STABLE 5-minute mean during sleep, never a daytime minimum.
//  - Battery forecast is the drain slope of the last 24 h, ignoring charging.
//  - Sleep lines: precise 0 deep · 1 light · 2 REM · 3 insomnia → awake · 4 awake;
//    legacy 0 light · 1 deep · 2 awake, one character per 5 minutes.
//

import Foundation

public enum Baselines {

    public static let nightsNeeded = 7
    public static let baselineWindow = 14

    // MARK: Typical range

    /// Linear-interpolated percentile of an already sorted array.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return .nan }
        let rank = p / 100 * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = rank - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    /// The 10th–90th percentile band of the last `baselineWindow` nights, or `nil` when fewer
    /// than `minNights` finite values exist. Abstaining here is what keeps the chips honest.
    public static func typicalRange(from history: [Double], minNights: Int = nightsNeeded) -> ClosedRange<Double>? {
        let recent = history.suffix(baselineWindow).filter { $0.isFinite }
        guard recent.count >= max(minNights, 1) else { return nil }
        let sorted = recent.sorted()
        let lower = percentile(sorted, 10), upper = percentile(sorted, 90)
        guard lower.isFinite, upper.isFinite, lower <= upper else { return nil }
        return lower...upper
    }

    /// Grades a value against a range, or says why it cannot.
    public static func rangeState(value: Double?, range: ClosedRange<Double>?, nights: Int, needed: Int = nightsNeeded) -> RangeState {
        guard let value, value.isFinite else { return .notMeasured }
        guard let range, nights >= needed else { return .learning(nights: min(nights, needed), needed: needed) }
        return range.contains(value) ? .typical : .outsideTypical
    }

    /// Trend glyph: above, inside, or below the band.
    public static func trend(value: Double?, range: ClosedRange<Double>?) -> Trend? {
        guard let value, let range else { return nil }
        if value > range.upperBound { return .up }
        if value < range.lowerBound { return .down }
        return .steady
    }

    // MARK: Readiness

    public struct ReadinessInputs: Sendable {
        public var nights: Int
        public var hrv: VitalReading?
        public var restingHeartRate: VitalReading?
        public var sleepScore: Int?
        public var skinTempDelta: VitalReading?
        public var breathingRate: VitalReading?

        public init(nights: Int, hrv: VitalReading? = nil, restingHeartRate: VitalReading? = nil, sleepScore: Int? = nil, skinTempDelta: VitalReading? = nil, breathingRate: VitalReading? = nil) {
            self.nights = nights; self.hrv = hrv; self.restingHeartRate = restingHeartRate
            self.sleepScore = sleepScore; self.skinTempDelta = skinTempDelta; self.breathingRate = breathingRate
        }
    }

    /// 0–100 from overnight HRV, resting HR, sleep score, temperature and breathing deviation.
    /// Abstains with `.learning` under 7 nights and with a reason when nothing was measured.
    public static func readiness(from inputs: ReadinessInputs, needed: Int = nightsNeeded) -> Score {
        guard inputs.nights >= needed else { return .learning(.readiness, nights: inputs.nights, needed: needed) }

        var weighted: [(score: Double, weight: Double)] = []
        var contributors: [Contributor] = []

        if let hrv = inputs.hrv, let value = hrv.value, let range = hrv.typicalRange {
            let s: Double = value > range.upperBound ? 95 : (value < range.lowerBound ? 50 : 80)
            weighted.append((s, 0.30))
            contributors.append(Contributor(name: "HRV", reading: "\(RingFormat.vital(.hrv, value) ?? "") ms", state: hrv.state, trend: trend(value: value, range: range)))
        }
        if let rhr = inputs.restingHeartRate, let value = rhr.value, let range = rhr.typicalRange {
            let s: Double = value < range.lowerBound ? 95 : (value > range.upperBound ? 50 : 80)
            weighted.append((s, 0.25))
            contributors.append(Contributor(name: "Resting heart rate", reading: "\(RingFormat.vital(.restingHeartRate, value) ?? "") bpm", state: rhr.state, trend: trend(value: value, range: range)))
        }
        if let sleep = inputs.sleepScore {
            weighted.append((Double(sleep), 0.30))
            contributors.append(Contributor(name: "Sleep", reading: "\(sleep)", state: sleep >= 60 ? .typical : .outsideTypical))
        }
        if let temp = inputs.skinTempDelta, let value = temp.value {
            let inside = temp.typicalRange?.contains(value) ?? (abs(value) < 0.5)
            weighted.append((inside ? 80 : 55, 0.075))
            contributors.append(Contributor(name: "Skin temperature", reading: "\(RingFormat.signed(value)) °C", state: temp.state, trend: trend(value: value, range: temp.typicalRange)))
        }
        if let breathing = inputs.breathingRate, let value = breathing.value {
            let inside = breathing.typicalRange?.contains(value) ?? true
            weighted.append((inside ? 80 : 55, 0.075))
            contributors.append(Contributor(name: "Breathing rate", reading: "\(RingFormat.vital(.breathingRate, value) ?? "") brpm", state: breathing.state, trend: trend(value: value, range: breathing.typicalRange)))
        }

        let totalWeight = weighted.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return .abstained(.readiness, reason: "No overnight vitals were measured") }
        let value = Int((weighted.reduce(0) { $0 + $1.score * $1.weight } / totalWeight).rounded())
        let clamped = min(max(value, 0), 100)
        return Score(kind: .readiness, value: clamped, state: .measured(.grade(score: clamped)), caption: readinessCaption(score: clamped, contributors: contributors), contributors: contributors)
    }

    /// "Recovered. HRV above your usual, resting heart rate steady."
    static func readinessCaption(score: Int, contributors: [Contributor]) -> String {
        let lead: String
        switch score {
        case 85...: lead = "Recovered."
        case 70..<85: lead = "Ready."
        case 50..<70: lead = "Take it easy."
        default: lead = "Rest day."
        }
        var clauses: [String] = []
        if let hrv = contributors.first(where: { $0.name == "HRV" }), let t = hrv.trend {
            clauses.append("HRV " + (t == .up ? "above your usual" : t == .down ? "below your usual" : "in your usual range"))
        }
        if let rhr = contributors.first(where: { $0.name == "Resting heart rate" }), let t = rhr.trend {
            clauses.append("resting heart rate " + (t == .up ? "above your usual" : t == .down ? "below your usual" : "steady"))
        }
        guard !clauses.isEmpty else { return lead }
        return lead + " " + clauses.joined(separator: ", ") + "."
    }

    // MARK: Sleep

    /// Need vs the rolling 7-night total.
    public static func sleepDebt(needMin: Int, totals: [Int]) -> SleepDebt {
        let recent = Array(totals.suffix(7))
        return SleepDebt(needMin: needMin, totalMin: recent.reduce(0, +), nights: recent.count)
    }

    public static func stageTotals(_ stages: [SleepStage]) -> [SleepStage: Int] {
        var totals: [SleepStage: Int] = [:]
        for stage in stages { totals[stage, default: 0] += 1 }
        return totals
    }

    /// Our sleep score: vendor quality blended with duration vs need, efficiency and awakenings.
    public static func sleepScore(vendorQuality: Int?, durationMin: Int, needMin: Int, awakenings: Int, efficiency: Double) -> Int {
        let duration = min(Double(durationMin) / Double(max(needMin, 1)), 1.1) / 1.1 * 100
        let eff = min(max(efficiency, 0), 1) * 100
        let wake = max(0, 100 - Double(awakenings) * 12)
        var parts: [(Double, Double)] = [(duration, 0.4), (eff, 0.3), (wake, 0.15)]
        if let vendorQuality { parts.append((Double(vendorQuality), 0.15)) }
        let total = parts.reduce(0) { $0 + $1.1 }
        let score = parts.reduce(0) { $0 + $1.0 * $1.1 } / total
        return min(max(Int(score.rounded()), 0), 100)
    }

    // MARK: Resting heart rate

    /// Lowest stable 5-minute mean: the minimum over 3-sample windows whose spread ≤ 6 bpm.
    /// Abstains with fewer than 3 samples — one low reading is noise, not a resting rate.
    public static func restingHeartRate(fromOvernightMeans means: [Double]) -> Double? {
        let valid = means.filter { $0.isFinite && $0 > 0 }
        guard valid.count >= 3 else { return nil }
        var best: Double?
        for i in 0...(valid.count - 3) {
            let window = valid[i..<(i + 3)]
            guard let lo = window.min(), let hi = window.max(), hi - lo <= 6 else { continue }
            let mean = window.reduce(0, +) / 3
            if best == nil || mean < best! { best = mean }
        }
        return best.map { $0.rounded() }
    }

    // MARK: Battery forecast

    /// Nights of charge left, from the drain slope over the last 24 h of reads. Increases are
    /// charging and are excluded; with no discharge run of at least an hour the answer is `nil`.
    public static func batteryForecastNights(samples: [TimedSample], now: Date? = nil) -> Double? {
        let sorted = samples.filter { $0.value.isFinite }.sorted { $0.time < $1.time }
        guard let last = sorted.last else { return nil }
        let reference = now ?? last.time
        let window = sorted.filter { reference.timeIntervalSince($0.time) <= 86_400 }
        guard window.count >= 2 else { return nil }
        // The trailing non-increasing run is the current discharge.
        var run: [TimedSample] = [window[window.count - 1]]
        var i = window.count - 2
        while i >= 0, window[i].value >= run[0].value {
            run.insert(window[i], at: 0)
            i -= 1
        }
        guard let first = run.first, let end = run.last, run.count >= 2 else { return nil }
        let hours = end.time.timeIntervalSince(first.time) / 3600
        guard hours >= 1 else { return nil }
        let drainPerHour = (first.value - end.value) / hours
        guard drainPerHour > 0 else { return nil }
        return end.value / (drainPerHour * 24)
    }

    // MARK: Sleep line parsing

    /// Precise (per-minute) codes: 0 deep · 1 light · 2 REM · 3 insomnia → awake · 4 awake.
    /// Legacy (per 5 minutes) codes: 0 light · 1 deep · 2 awake — expanded to 5 minutes each.
    public static func parseSleepLine(codes: [Int], legacy: Bool = false) -> [SleepStage] {
        if legacy {
            return codes.flatMap { code -> [SleepStage] in
                let stage: SleepStage
                switch code {
                case 0: stage = .light
                case 1: stage = .deep
                case 2: stage = .awake
                default: stage = .gap
                }
                return Array(repeating: stage, count: 5)
            }
        }
        return codes.map { code in
            switch code {
            case 0: return .deep
            case 1: return .light
            case 2: return .rem
            case 3, 4: return .awake
            default: return .gap
            }
        }
    }

    /// The vendor's `parseSleepLine` output: `[{"index": n, "type": t}]`, ordered by index.
    public static func parseSleepLine(dictionaries: [[String: Any]]) -> [SleepStage] {
        let pairs: [(Int, Int)] = dictionaries.compactMap { dict in
            guard let index = intValue(dict["index"]), let type = intValue(dict["type"]) else { return nil }
            return (index, type)
        }
        guard let maxIndex = pairs.map({ $0.0 }).max() else { return [] }
        var codes = Array(repeating: -1, count: maxIndex + 1)
        for (index, type) in pairs where index >= 0 { codes[index] = type }
        return parseSleepLine(codes: codes)
    }

    /// The legacy `SLE_LINE` string, one character per 5 minutes.
    public static func parseSleepLine(legacyLine: String) -> [SleepStage] {
        parseSleepLine(codes: legacyLine.compactMap { $0.wholeNumberValue }, legacy: true)
    }

    /// Lenient integer parsing for vendor dictionaries (Int, NSNumber, String, Double).
    public static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let n as Int: return n
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        case let d as Double: return Int(d)
        default: return nil
        }
    }
}
