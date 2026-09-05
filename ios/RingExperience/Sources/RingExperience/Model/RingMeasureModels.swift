//
//  RingMeasureModels.swift
//  RingExperience
//
//  Spot measurements (user-initiated tests) and the passive monitoring schedule.
//
//  Every spot test shares ONE state machine — Preparing → Measuring → Result — with three
//  explicit exits the user can act on: Not on finger, Ring busy, Battery too low. Timeouts are
//  ours (30 s HR/SpO₂, 60 s everything else); the vendor SDK does not always finish.
//

import Foundation

// MARK: - Spot measurements

public enum SpotKind: String, CaseIterable, Hashable, Sendable, Identifiable, Codable {
    case heartRate, bloodOxygen, hrv, stress, skinTemperature, breathingRate
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .heartRate: return "Heart rate"
        case .bloodOxygen: return "Blood oxygen"
        case .hrv: return "HRV"
        case .stress: return "Stress"
        case .skinTemperature: return "Skin temperature"
        case .breathingRate: return "Breathing rate"
        }
    }

    public var unit: String {
        switch self {
        case .heartRate: return "bpm"
        case .bloodOxygen: return "%"
        case .hrv: return "ms"
        case .stress: return ""
        case .skinTemperature: return "°C"
        case .breathingRate: return "brpm"
        }
    }

    public var symbol: String {
        switch self {
        case .heartRate: return "heart.fill"
        case .bloodOxygen: return "drop.fill"
        case .hrv: return "waveform"
        case .stress: return "brain.head.profile"
        case .skinTemperature: return "thermometer.medium"
        case .breathingRate: return "wind"
        }
    }

    /// Our timeout, not the SDK's: 30 s HR/SpO₂, 60 s breathing/HRV/stress/temperature.
    public var durationSeconds: Double {
        switch self {
        case .heartRate, .bloodOxygen: return 30
        case .hrv, .stress, .skinTemperature, .breathingRate: return 60
        }
    }

    /// Only heart rate streams a live value during the test.
    public var showsLiveValue: Bool { self == .heartRate }

    public var instruction: String {
        switch self {
        case .stress: return "Hold still and breathe normally. Keep your hand relaxed."
        default: return "Hold still. Keep your hand relaxed."
        }
    }

    /// The vital whose typical range grades the result, if any.
    public var vital: VitalKind? {
        switch self {
        case .heartRate: return nil          // daytime HR is graded against a daytime band, not RHR
        case .bloodOxygen: return .spo2
        case .hrv: return .hrv
        case .stress: return nil
        case .skinTemperature: return .skinTempDelta
        case .breathingRate: return .breathingRate
        }
    }
}

public struct SpotMeasurement: Equatable, Sendable, Identifiable, Codable {
    public var id: UUID
    public var kind: SpotKind
    public var value: Double
    public var unit: String
    public var at: Date
    public var state: RangeState
    public init(id: UUID = UUID(), kind: SpotKind, value: Double, unit: String? = nil, at: Date, state: RangeState) {
        self.id = id; self.kind = kind; self.value = value; self.unit = unit ?? kind.unit; self.at = at; self.state = state
    }
}

/// Every spot test shares one state machine with three honest exits and our own timeout.
public enum MeasureSessionState: Equatable, Sendable {
    case preparing
    case measuring(progress: Double, live: Double?)
    case result(SpotMeasurement)
    case notWorn
    case busy
    case lowBattery(percent: Int?)
    case timedOut
    case failed(String)

    public var isTerminal: Bool {
        switch self {
        case .preparing, .measuring: return false
        default: return true
        }
    }
}

// MARK: - Monitoring schedule

public enum MonitoringKind: String, CaseIterable, Sendable, Identifiable {
    case heartRate, hrv, bloodOxygen, skinTemperature, stress
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .heartRate: return "Heart rate"
        case .hrv: return "HRV"
        case .bloodOxygen: return "Blood oxygen"
        case .skinTemperature: return "Skin temperature"
        case .stress: return "Stress"
        }
    }
    /// Plain-language battery cost, shown beside the toggle.
    public var batteryCostHint: String {
        switch self {
        case .heartRate: return "Small battery cost"
        case .hrv: return "Moderate battery cost"
        case .bloodOxygen: return "Largest battery cost · night only"
        case .skinTemperature: return "Negligible battery cost"
        case .stress: return "Moderate battery cost"
        }
    }
}

public struct MonitoringSetting: Equatable, Sendable, Identifiable {
    public var kind: MonitoringKind
    public var isOn: Bool
    public var intervalMin: Int
    public var minIntervalMin: Int
    public var window: ClosedRange<ClockTime>?
    public var id: MonitoringKind { kind }
    public init(kind: MonitoringKind, isOn: Bool, intervalMin: Int, minIntervalMin: Int = 5, window: ClosedRange<ClockTime>? = nil) {
        self.kind = kind; self.isOn = isOn; self.intervalMin = intervalMin; self.minIntervalMin = minIntervalMin; self.window = window
    }
}
