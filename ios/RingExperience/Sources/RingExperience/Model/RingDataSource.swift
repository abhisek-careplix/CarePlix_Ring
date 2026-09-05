//
//  RingDataSource.swift
//  RingExperience
//
//  What every screen needs from the ring, with no vendor SDK in the signature.
//
//  Screens are generic over this protocol, so the whole experience renders against
//  `MockRingDataSource` in previews and tests and against `VeepooRingDataSource` in the app.
//  The published pieces are *snapshots* assembled once per sync; views never compute baselines.
//

import Foundation
import Combine
import RingDiscovery

@MainActor
public protocol RingDataSource: ObservableObject {
    var connection: RingConnection { get }
    var battery: Battery? { get }
    var capabilities: RingCapabilities { get }
    var profile: UserProfile? { get }
    var today: TodayDashboard { get }
    /// Oldest first. The last element is last night.
    var nights: [SleepNight] { get }
    var activity: ActivityDay { get }
    /// Newest first.
    var spotMeasurements: [SpotMeasurement] { get }
    var timeline: [DayTimelineItem] { get }
    var monitoring: [MonitoringSetting] { get }
    var ringName: String? { get }
    var firmwareVersion: String? { get }
    /// Today's 5-minute heart rate from origin data. Gaps are gaps.
    var heartRateToday: [TimedSample] { get }
    /// Seven days of battery reads for the Ring sheet history line.
    var batteryHistory: [TimedSample] { get }
    /// When the phone last pulled data off the ring.
    var lastSync: Date? { get }
    /// True for the demo data source, so the Ring sheet can say "Demo data".
    var isDemo: Bool { get }
    /// The link the pairing screen should connect through. Nil in demo builds.
    var pairingLink: (any RingLinking)? { get }
    /// The ring's low-power mode (`lowPowerModel`).
    var isLowPowerMode: Bool { get }

    /// Pulls last night (and anything since) off the ring. Updates `connection` as it goes.
    func sync() async
    /// Starts a spot test. The stream always ends in a terminal `MeasureSessionState`.
    func startSpot(_ kind: SpotKind) -> AsyncStream<MeasureSessionState>
    func cancelSpot()
    /// Keeps a finished result in `spotMeasurements` (and on the day chart).
    func saveSpot(_ measurement: SpotMeasurement)
    /// Persists the profile and writes it to the ring.
    func saveProfile(_ profile: UserProfile) async
    func setMonitoring(_ kind: MonitoringKind, on: Bool, intervalMin: Int) async
    /// Unpairs. Afterwards `connection == .unpaired`.
    func forgetRing() async
    /// Called by the pairing flow once the handshake succeeded.
    func adoptPairedRing(id: String, name: String) async
    /// Reconnects to the remembered ring after a drop (J6).
    func reconnect() async
    func setLowPowerMode(_ on: Bool) async
    /// Danger zone. Both no-ops by default; the vendor adapter implements them.
    func powerOffRing() async
    func resetRingData() async

    func heroNow(at date: Date) -> TodayHero
}

// MARK: - Defaults

public extension RingDataSource {
    var isDemo: Bool { false }
    var pairingLink: (any RingLinking)? { nil }
    var isLowPowerMode: Bool { false }
    var lastSync: Date? {
        if case let .notConnected(lastSync) = connection { return lastSync }
        return nil
    }
    func setLowPowerMode(_ on: Bool) async {}
    func powerOffRing() async {}
    func resetRingData() async {}

    /// Default hero selection; data sources rarely need to override it.
    func heroNow(at date: Date) -> TodayHero {
        HeroSelection.select(
            at: date,
            connection: connection,
            today: today,
            battery: battery,
            profile: profile
        )
    }
}

/// The time-of-day rule for Today's hero, as a pure function so it can be unit tested.
public enum HeroSelection {

    /// Nights needed before a readiness score is shown.
    public static let nightsNeeded = 7

    /// Hours before bedtime the evening card takes over.
    public static let eveningLeadHours = 3

    public static func select(
        at date: Date,
        connection: RingConnection,
        today: TodayDashboard,
        battery: Battery?,
        profile: UserProfile?,
        calendar: Calendar = .current
    ) -> TodayHero {
        if case .unpaired = connection { return .unpaired }

        let bedtime = profile?.bedtime ?? ClockTime(hour: 23)
        let wake = profile?.wakeTime ?? ClockTime(hour: 7)
        let now = ClockTime(date: date, calendar: calendar).minutesSinceMidnight
        let eveningStart = bedtime.adding(minutes: -eveningLeadHours * 60).minutesSinceMidnight

        // Evening: the last three hours before bedtime, and the hour after it (the user is
        // still up, and the only useful thing to say is "charge" or "wind down").
        let eveningEnd = bedtime.adding(minutes: 60).minutesSinceMidnight
        if isBetween(now, eveningStart, eveningEnd) {
            return .evening(bedtime: bedtime, battery: battery)
        }

        // A missing night explains itself before anything else is said.
        if let reason = today.noNightReason { return .noNight(reason) }

        if today.nightsRecorded < nightsNeeded { return .learning(nights: today.nightsRecorded) }

        // Morning: wake → noon. Anything before wake still counts as "last night's answer".
        let noon = 12 * 60
        if now < noon || now < wake.minutesSinceMidnight { return .morning(today.readiness) }

        // Afternoon: stress if we have a signal, otherwise activity. Far from the step goal
        // late in the day beats a mid stress number.
        let lateAfternoon = now >= 15 * 60
        if lateAfternoon, today.activity.goalFraction < 0.5 { return .afternoonActivity(today.activity) }
        if let stress = today.stressNow { return .afternoonStress(stress) }
        return .afternoonActivity(today.activity)
    }

    /// True when `minute` lies in the clock window `start → end`, wrapping past midnight.
    private static func isBetween(_ minute: Int, _ start: Int, _ end: Int) -> Bool {
        if start <= end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }
}
