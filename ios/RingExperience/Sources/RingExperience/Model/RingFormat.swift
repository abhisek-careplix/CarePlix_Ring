//
//  RingFormat.swift
//  RingExperience
//
//  One place for every string a number becomes. Significant figures are a product decision, so
//  they live here and not in views.
//

import Foundation

public enum RingFormat {

    // MARK: Time

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f
    }()

    /// "23:12" (or "11:12 PM" per locale).
    public static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }

    /// "Fri 5 Sep".
    public static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    /// Single-letter weekday for the night strip.
    public static func weekdayInitial(_ date: Date) -> String { shortDayFormatter.string(from: date) }

    /// "7 h 42 m", "45 m", "8 h".
    public static func duration(minutes: Int) -> String {
        let m = max(minutes, 0)
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r) m" }
        if r == 0 { return "\(h) h" }
        return "\(h) h \(r) m"
    }

    /// "just now", "6 min ago", "2 h ago", or the clock time when older than a day.
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) h ago" }
        return "\(day(date)) \(clock(date))"
    }

    public static func clock(_ time: ClockTime) -> String {
        clock(time.date(on: Date()))
    }

    // MARK: Numbers

    public static func number(_ value: Double, decimals: Int = 0) -> String {
        String(format: "%.\(max(decimals, 0))f", value)
    }

    /// "+0.3", "−0.2", "0.0" with a true minus sign.
    public static func signed(_ value: Double, decimals: Int = 1) -> String {
        let text = number(abs(value), decimals: decimals)
        if value > 0 { return "+\(text)" }
        if value < 0 { return "\u{2212}\(text)" }
        return text
    }

    /// Display string for a vital's value in its own unit convention.
    public static func vital(_ kind: VitalKind, _ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        switch kind {
        case .restingHeartRate, .hrv, .spo2: return number(value)
        case .breathingRate: return number(value, decimals: value < 30 ? 1 : 0)
        case .skinTempDelta: return signed(value, decimals: 1)
        case .sleepDuration: return duration(minutes: Int(value.rounded()))
        }
    }

    /// The unit that follows `vital(_:_:)`, or nil when the value already carries it.
    public static func vitalUnit(_ kind: VitalKind) -> String? {
        kind == .sleepDuration ? nil : kind.unit
    }

    public static func spot(_ kind: SpotKind, _ value: Double) -> String {
        switch kind {
        case .heartRate, .bloodOxygen, .hrv, .stress: return number(value)
        case .skinTemperature: return number(value, decimals: 1)
        case .breathingRate: return number(value, decimals: 1)
        }
    }

    /// "56–63 bpm" style band.
    public static func range(_ range: ClosedRange<Double>?, kind: VitalKind) -> String? {
        guard let range else { return nil }
        let lower = vital(kind, range.lowerBound) ?? "", upper = vital(kind, range.upperBound) ?? ""
        let unit = vitalUnit(kind).map { " \($0)" } ?? ""
        return "\(lower)\u{2013}\(upper)\(unit)"
    }

    /// "About 3 nights", "Less than a night", "About half a night".
    public static func forecast(nights: Double?) -> String? {
        guard let nights, nights.isFinite else { return nil }
        if nights < 0.5 { return "Less than half a night" }
        if nights < 1 { return "Less than a night" }
        let rounded = Int(nights.rounded())
        return rounded == 1 ? "About 1 night" : "About \(rounded) nights"
    }

    public static func steps(_ steps: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    /// "12.3 km" or "7.6 mi".
    public static func distance(km: Double, units: Units) -> String {
        switch units {
        case .metric: return "\(number(km, decimals: 1)) km"
        case .imperial: return "\(number(km * 0.621371, decimals: 1)) mi"
        }
    }
}
