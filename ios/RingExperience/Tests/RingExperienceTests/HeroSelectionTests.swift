//
//  HeroSelectionTests.swift
//  RingExperienceTests
//
//  Today's hero is the one element that changes with the clock. These pin the rule.
//

import XCTest
@testable import RingExperience

@MainActor
final class HeroSelectionTests: XCTestCase {

    /// A fixed weekday at `hour`, so the fixture and the rule agree on "today".
    private func date(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 4   // a Friday
        components.hour = hour; components.minute = minute
        return Calendar.current.date(from: components)!
    }

    func testMorningShowsReadiness() {
        let mock = MockRingDataSource(scenario: .established, now: date(hour: 8))
        guard case let .morning(score) = mock.heroNow(at: date(hour: 8)) else { return XCTFail("expected morning") }
        XCTAssertEqual(score.kind, .readiness)
        XCTAssertNotNil(score.value)
    }

    func testEarlyAfternoonShowsStress() {
        let mock = MockRingDataSource(scenario: .established, now: date(hour: 13))
        guard case .afternoonStress = mock.heroNow(at: date(hour: 13)) else { return XCTFail("expected stress hero") }
    }

    func testLateAfternoonFarFromGoalShowsActivity() {
        let mock = MockRingDataSource(scenario: .established, now: date(hour: 15, minute: 30))
        let hero = mock.heroNow(at: date(hour: 15, minute: 30))
        if mock.today.activity.goalFraction < 0.5 {
            guard case .afternoonActivity = hero else { return XCTFail("expected activity hero") }
        } else {
            guard case .afternoonStress = hero else { return XCTFail("expected stress hero") }
        }
    }

    func testEveningShowsTonightWithBattery() {
        let mock = MockRingDataSource(scenario: .established, now: date(hour: 21))
        guard case let .evening(bedtime, battery) = mock.heroNow(at: date(hour: 21)) else { return XCTFail("expected evening") }
        XCTAssertEqual(bedtime, ClockTime(hour: 23))
        XCTAssertNotNil(battery)
    }

    func testEveningWindowIsThreeHoursBeforeBedtime() {
        let mock = MockRingDataSource(scenario: .established, now: date(hour: 19, minute: 59))
        if case .evening = mock.heroNow(at: date(hour: 19, minute: 59)) { XCTFail("19:59 is still afternoon for a 23:00 bedtime") }
        if case .evening = mock.heroNow(at: date(hour: 20)) {} else { XCTFail("20:00 is evening for a 23:00 bedtime") }
    }

    func testLearningBeatsMorning() {
        let mock = MockRingDataSource(scenario: .learning(night: 3), now: date(hour: 8))
        guard case let .learning(nights) = mock.heroNow(at: date(hour: 8)) else { return XCTFail("expected learning") }
        XCTAssertEqual(nights, 3)
    }

    func testNotWornExplainsItself() {
        let mock = MockRingDataSource(scenario: .notWorn, now: date(hour: 8))
        guard case let .noNight(reason) = mock.heroNow(at: date(hour: 8)), case .notWorn = reason else { return XCTFail("expected not-worn reason") }
        XCTAssertEqual(reason.actionTitle, "See how to wear it")
    }

    func testBatteryDeathExplainsItself() {
        let mock = MockRingDataSource(scenario: .batteryDied, now: date(hour: 9))
        guard case let .noNight(reason) = mock.heroNow(at: date(hour: 9)), case .batteryRanOut = reason else { return XCTFail("expected battery reason") }
        XCTAssertTrue(reason.body.contains("Charge it now"))
    }

    func testUnpairedWinsAtAnyHour() {
        let mock = MockRingDataSource(scenario: .unpaired, now: date(hour: 21))
        XCTAssertEqual(mock.heroNow(at: date(hour: 21)), .unpaired)
        XCTAssertEqual(mock.heroNow(at: date(hour: 8)), .unpaired)
    }

    func testPureSelectionUsesProfileBedtime() {
        let profile = UserProfile(birthDate: Date(), sex: .preferNotToSay, heightCm: 170, weightKg: 70, bedtime: ClockTime(hour: 1), wakeTime: ClockTime(hour: 9))
        let today = TodayDashboard.empty(date: date(hour: 23))
        let hero = HeroSelection.select(at: date(hour: 23), connection: .connected, today: today, battery: nil, profile: profile)
        guard case .evening = hero else { return XCTFail("23:00 is within three hours of a 01:00 bedtime") }
    }
}
