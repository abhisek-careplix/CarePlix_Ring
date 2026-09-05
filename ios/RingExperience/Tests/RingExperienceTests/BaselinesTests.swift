//
//  BaselinesTests.swift
//  RingExperienceTests
//
//  The derived-metric rules from docs/ux/03 §5, checked as pure functions.
//

import XCTest
@testable import RingExperience

final class BaselinesTests: XCTestCase {

    // MARK: Typical range

    func testTypicalRangeIsTenthToNinetiethPercentile() throws {
        let history: [Double] = [50, 52, 54, 56, 58, 60, 62, 64, 66, 68, 70]
        let range = try XCTUnwrap(Baselines.typicalRange(from: history))
        // Linear interpolation over 11 sorted values: rank 1.0 → 52, rank 9.0 → 68.
        XCTAssertEqual(range.lowerBound, 52, accuracy: 0.001)
        XCTAssertEqual(range.upperBound, 68, accuracy: 0.001)
    }

    func testTypicalRangeUsesOnlyTheLastFourteenNights() throws {
        let old = Array(repeating: 200.0, count: 10)
        let recent = Array(repeating: 60.0, count: 14)
        let range = try XCTUnwrap(Baselines.typicalRange(from: old + recent))
        XCTAssertEqual(range.lowerBound, 60, accuracy: 0.001)
        XCTAssertEqual(range.upperBound, 60, accuracy: 0.001)
    }

    func testTypicalRangeAbstainsUnderSevenNights() {
        XCTAssertNil(Baselines.typicalRange(from: [56, 57, 58, 59, 60, 61]))
        XCTAssertNotNil(Baselines.typicalRange(from: [56, 57, 58, 59, 60, 61, 62]))
    }

    func testRangeStateVocabulary() {
        let range: ClosedRange<Double> = 54...61
        XCTAssertEqual(Baselines.rangeState(value: 58, range: range, nights: 10), .typical)
        XCTAssertEqual(Baselines.rangeState(value: 66, range: range, nights: 10), .outsideTypical)
        XCTAssertEqual(Baselines.rangeState(value: 58, range: range, nights: 3), .learning(nights: 3, needed: 7))
        XCTAssertEqual(Baselines.rangeState(value: 58, range: nil, nights: 10), .learning(nights: 7, needed: 7))
        XCTAssertEqual(Baselines.rangeState(value: nil, range: range, nights: 10), .notMeasured)
        XCTAssertEqual(RangeState.typical.label, "Typical")
        XCTAssertEqual(RangeState.outsideTypical.label, "Outside typical")
        XCTAssertEqual(RangeState.learning(nights: 1, needed: 7).label, "Learning")
        XCTAssertEqual(RangeState.notMeasured.label, "Not measured")
    }

    // MARK: Readiness

    func testReadinessAbstainsUnderSevenNights() {
        let hrv = VitalReading(kind: .hrv, value: 50, state: .typical, typicalRange: 40...55)
        let score = Baselines.readiness(from: .init(nights: 6, hrv: hrv, sleepScore: 80))
        XCTAssertNil(score.value)
        XCTAssertEqual(score.state, .learning(nights: 6, needed: 7))
    }

    func testReadinessScoresWithSevenNightsAndExplainsItself() throws {
        let hrv = VitalReading(kind: .hrv, value: 60, state: .outsideTypical, typicalRange: 40...55)
        let rhr = VitalReading(kind: .restingHeartRate, value: 57, state: .typical, typicalRange: 54...61)
        let score = Baselines.readiness(from: .init(nights: 7, hrv: hrv, restingHeartRate: rhr, sleepScore: 84))
        let value = try XCTUnwrap(score.value)
        XCTAssertTrue((0...100).contains(value))
        XCTAssertEqual(score.contributors.count, 3)
        XCTAssertTrue(score.caption.contains("HRV above your usual"))
        XCTAssertTrue(score.caption.contains("resting heart rate steady"))
    }

    func testReadinessAbstainsWithReasonWhenNothingWasMeasured() {
        let score = Baselines.readiness(from: .init(nights: 10))
        if case .abstained = score.state {} else { XCTFail("expected abstention, got \(score.state)") }
    }

    // MARK: Sleep line parsing

    func testParseSleepLinePreciseCodes() {
        let stages = Baselines.parseSleepLine(codes: [0, 1, 2, 3, 4, 9])
        XCTAssertEqual(stages, [.deep, .light, .rem, .awake, .awake, .gap])
    }

    func testParseSleepLineDictionariesOrderByIndexAndFillHoles() {
        let dicts: [[String: Any]] = [["index": 2, "type": 2], ["index": 0, "type": 0], ["index": 1, "type": "1"], ["index": 4, "type": 4]]
        XCTAssertEqual(Baselines.parseSleepLine(dictionaries: dicts), [.deep, .light, .rem, .gap, .awake])
    }

    func testParseSleepLineLegacyVariantExpandsFiveMinuteSlots() {
        let stages = Baselines.parseSleepLine(legacyLine: "012")
        XCTAssertEqual(stages.count, 15)
        XCTAssertEqual(Array(stages[0..<5]), Array(repeating: SleepStage.light, count: 5))
        XCTAssertEqual(Array(stages[5..<10]), Array(repeating: SleepStage.deep, count: 5))
        XCTAssertEqual(Array(stages[10..<15]), Array(repeating: SleepStage.awake, count: 5))
    }

    // MARK: Battery forecast

    func testBatteryForecastFromDrainSlope() throws {
        let now = Date()
        let samples = stride(from: 0, through: 24, by: 2).map { h in
            TimedSample(time: now.addingTimeInterval(Double(h - 24) * 3600), value: 100 - Double(h) * 0.9)
        }
        let nights = try XCTUnwrap(Baselines.batteryForecastNights(samples: samples, now: now))
        // 78.4 % left, draining 0.9 %/h → ≈ 3.6 nights.
        XCTAssertEqual(nights, 78.4 / (0.9 * 24), accuracy: 0.05)
    }

    func testBatteryForecastIgnoresChargingAndNeedsAnHour() {
        let now = Date()
        let charging = [TimedSample(time: now.addingTimeInterval(-7200), value: 40), TimedSample(time: now.addingTimeInterval(-3600), value: 70), TimedSample(time: now, value: 90)]
        XCTAssertNil(Baselines.batteryForecastNights(samples: charging, now: now))
        let short = [TimedSample(time: now.addingTimeInterval(-600), value: 60), TimedSample(time: now, value: 59)]
        XCTAssertNil(Baselines.batteryForecastNights(samples: short, now: now))
    }

    // MARK: Sleep debt & resting HR

    func testSleepDebtUsesLastSevenNights() {
        let debt = Baselines.sleepDebt(needMin: 450, totals: [600, 600, 400, 400, 400, 400, 400, 400, 400])
        XCTAssertEqual(debt.nights, 7)
        XCTAssertEqual(debt.totalMin, 2800)
        XCTAssertEqual(debt.deltaMin, -350)
        XCTAssertEqual(debt.level, .high)
        XCTAssertEqual(Baselines.sleepDebt(needMin: 450, totals: [450, 460]).level, .none)
    }

    func testRestingHeartRateIsLowestStableWindow() {
        // A single dip to 40 is noise; the stable window around 55 is the resting rate.
        let means: [Double] = [70, 68, 55, 56, 54, 40, 66, 65, 64]
        XCTAssertEqual(Baselines.restingHeartRate(fromOvernightMeans: means), 55)
        XCTAssertNil(Baselines.restingHeartRate(fromOvernightMeans: [58, 57]))
    }
}
