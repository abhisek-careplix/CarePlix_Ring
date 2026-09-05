//
//  MockDataSourceTests.swift
//  RingExperienceTests
//
//  The mock must behave like a data source the screens can trust: spot tests always end in a
//  terminal state, the scenarios carry the honest states they promise, and nothing renders a
//  capability the ring does not have.
//

import XCTest
@testable import RingExperience

@MainActor
final class MockDataSourceTests: XCTestCase {

    private func lastState(_ mock: MockRingDataSource, _ kind: SpotKind) async -> MeasureSessionState? {
        var last: MeasureSessionState?
        for await state in mock.startSpot(kind) { last = state }
        return last
    }

    func testSpotTestEndsInResult() async throws {
        let mock = MockRingDataSource(scenario: .established, spotTestDuration: 0.2)
        let last = try XCTUnwrap(await lastState(mock, .heartRate))
        XCTAssertTrue(last.isTerminal)
        guard case let .result(measurement) = last else { return XCTFail("expected a result, got \(last)") }
        XCTAssertEqual(measurement.kind, .heartRate)
        XCTAssertEqual(measurement.unit, "bpm")
    }

    func testSpotTestStreamsProgressBeforeResult() async {
        let mock = MockRingDataSource(scenario: .established, spotTestDuration: 0.2)
        var sawPreparing = false, sawMeasuring = false, sawLive = false
        for await state in mock.startSpot(.heartRate) {
            switch state {
            case .preparing: sawPreparing = true
            case let .measuring(progress, live):
                sawMeasuring = true
                XCTAssertTrue((0...1).contains(progress))
                if live != nil { sawLive = true }
            default: break
            }
        }
        XCTAssertTrue(sawPreparing && sawMeasuring && sawLive)
    }

    func testNotWornScenarioExitsHonestly() async throws {
        let mock = MockRingDataSource(scenario: .notWorn, spotTestDuration: 0.2)
        XCTAssertEqual(try XCTUnwrap(await lastState(mock, .bloodOxygen)), .notWorn)
    }

    func testFlatBatteryScenarioExitsHonestly() async throws {
        let mock = MockRingDataSource(scenario: .batteryDied, spotTestDuration: 0.2)
        guard case .lowBattery = try XCTUnwrap(await lastState(mock, .hrv)) else { return XCTFail("expected low battery") }
    }

    func testCancelEndsTheStream() async {
        let mock = MockRingDataSource(scenario: .established, spotTestDuration: 5)
        let stream = mock.startSpot(.stress)
        var states: [MeasureSessionState] = []
        let consumer = Task { for await state in stream { states.append(state) } }
        try? await Task.sleep(nanoseconds: 100_000_000)
        mock.cancelSpot()
        await consumer.value
        XCTAssertFalse(states.contains { if case .result = $0 { return true }; return false })
    }

    func testScenariosCarryTheirStates() {
        XCTAssertEqual(MockRingDataSource(scenario: .unpaired).connection, .unpaired)
        XCTAssertEqual(MockRingDataSource(scenario: .bluetoothOff).connection, .bluetoothOff)
        XCTAssertEqual(MockRingDataSource(scenario: .established).nights.count, 14)
        XCTAssertEqual(MockRingDataSource(scenario: .learning(night: 3)).nights.count, 3)
        XCTAssertTrue(MockRingDataSource(scenario: .notWorn).nights.last?.wasNotWorn ?? false)
        XCTAssertNotNil(MockRingDataSource(scenario: .batteryDied).nights.last?.batteryLossAt)
        XCTAssertTrue(MockRingDataSource().isDemo)
    }

    func testFixtureIsDeterministic() {
        let a = MockRingDataSource(scenario: .established, now: Date(timeIntervalSince1970: 1_788_000_000))
        let b = MockRingDataSource(scenario: .established, now: Date(timeIntervalSince1970: 1_788_000_000))
        XCTAssertEqual(a.nights, b.nights)
        XCTAssertEqual(a.today, b.today)
    }

    func testEstablishedVitalsHaveTypicalRanges() throws {
        let mock = MockRingDataSource(scenario: .established)
        let rhr = try XCTUnwrap(mock.today.vitals.first { $0.kind == .restingHeartRate })
        XCTAssertNotNil(rhr.typicalRange)
        XCTAssertTrue(rhr.state == .typical || rhr.state == .outsideTypical)
        XCTAssertEqual(rhr.history.count, 7)
    }

    func testLearningVitalsSayLearning() throws {
        let mock = MockRingDataSource(scenario: .learning(night: 3))
        let hrv = try XCTUnwrap(mock.today.vitals.first { $0.kind == .hrv })
        XCTAssertEqual(hrv.state, .learning(nights: 3, needed: 7))
        XCTAssertEqual(mock.today.readiness.state, .learning(nights: 3, needed: 7))
    }

    func testForgetRingClearsEverything() async {
        let mock = MockRingDataSource(scenario: .established)
        await mock.forgetRing()
        XCTAssertEqual(mock.connection, .unpaired)
        XCTAssertNil(mock.battery)
        XCTAssertTrue(mock.nights.isEmpty)
        XCTAssertEqual(mock.capabilities, .none)
    }

    func testSyncSetsLastSync() async {
        let mock = MockRingDataSource(scenario: .established)
        let before = mock.lastSync
        await mock.sync()
        XCTAssertEqual(mock.connection, .connected)
        XCTAssertNotNil(mock.lastSync)
        XCTAssertNotEqual(mock.lastSync, before)
    }
}
