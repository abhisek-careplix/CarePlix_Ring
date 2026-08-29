//
//  RingAdvertisingTests.swift
//  RingDiscoveryTests
//
//  Tests for the platform-free half of discovery: name matching, RSSI interpretation, and the
//  discovery policy. These are the rules that decided a ring was "not usable", so they are the
//  rules worth pinning down.
//
//  Nothing here touches CoreBluetooth, so these run on any platform with a Swift toolchain.
//

import XCTest
@testable import RingDiscovery

final class RingNameMatcherTests: XCTestCase {

    func testMatchesProvisionedRingName() {
        XCTAssertTrue(RingNameMatcher.standard.matches("LOOP-E5FF"))
    }

    func testMatchesBareBrandName() {
        XCTAssertTrue(RingNameMatcher.standard.matches("LOOP"))
    }

    func testMatchingIsCaseInsensitive() {
        // Firmware capitalisation is not a contract. A ring that advertises "loop-e5ff" is still
        // ours, and a case-sensitive compare is an invisible way to lose it.
        XCTAssertTrue(RingNameMatcher.standard.matches("loop-e5ff"))
        XCTAssertTrue(RingNameMatcher.standard.matches("Loop-E5FF"))
    }

    func testTrimsSurroundingWhitespace() {
        // Padded advertised names are common enough to be worth defending against by default.
        XCTAssertTrue(RingNameMatcher.standard.matches("  LOOP-E5FF  "))
    }

    func testRejectsOtherDevices() {
        XCTAssertFalse(RingNameMatcher.standard.matches("AirPods Pro"))
        XCTAssertFalse(RingNameMatcher.standard.matches("MyLOOP"))   // prefix, not substring
    }

    func testRejectsNilAndBlankNames() {
        XCTAssertFalse(RingNameMatcher.standard.matches(nil))
        XCTAssertFalse(RingNameMatcher.standard.matches(""))
        XCTAssertFalse(RingNameMatcher.standard.matches("   "))
    }

    func testPermissiveMatcherAcceptsAnyNamedDevice() {
        XCTAssertTrue(RingNameMatcher.permissive.matches("AirPods Pro"))
        XCTAssertTrue(RingNameMatcher.permissive.matches("anything at all"))
    }

    func testPermissiveMatcherStillRejectsNamelessDevices() {
        // Even in diagnostic mode a nameless advertisement is not something a human can pick from
        // a list.
        XCTAssertFalse(RingNameMatcher.permissive.matches(nil))
        XCTAssertFalse(RingNameMatcher.permissive.matches("  "))
    }

    func testAdditionalPrefixesAdmitUnprovisionedUnits() {
        // The case that would otherwise make a factory-fresh ring invisible.
        let matcher = RingNameMatcher(prefixes: ["LOOP", "CarePlix", "VP"])
        XCTAssertTrue(matcher.matches("VP-R1-0042"))
        XCTAssertTrue(matcher.matches("CarePlix Ring"))
        XCTAssertTrue(matcher.matches("LOOP-E5FF"))
    }

    func testBlankPrefixNeverMatchesEverything() {
        // A blank prefix would make hasPrefix("") true for every device on the air. Guard it,
        // because a trailing comma in a config list is how that gets introduced.
        let matcher = RingNameMatcher(prefixes: ["", "   "])
        XCTAssertFalse(matcher.matches("AirPods Pro"))
    }
}

final class RingSignalTests: XCTestCase {

    func testReadsNegativeRssi() {
        XCTAssertEqual(RingSignal(coreBluetoothValue: NSNumber(value: -63)), .dBm(-63))
    }

    func testTreats127AsNotReported() {
        // 127 is CoreBluetooth's "RSSI unavailable" sentinel, not a signal strength.
        XCTAssertEqual(RingSignal(coreBluetoothValue: NSNumber(value: 127)), .notReported)
    }

    func testTreatsNilAsNotReported() {
        XCTAssertEqual(RingSignal(coreBluetoothValue: nil), .notReported)
    }

    func testRejectsNonNegativeValues() {
        // A real BLE RSSI is negative. A zero or positive value is a malformed reading, and
        // admitting it sorts a device that cannot be measured to the top of a nearest-first list.
        XCTAssertEqual(RingSignal(coreBluetoothValue: NSNumber(value: 0)), .notReported)
        XCTAssertEqual(RingSignal(coreBluetoothValue: NSNumber(value: 12)), .notReported)
    }

    func testUnreportedSignalSortsLast() {
        let strong = RingSignal.dBm(-40)
        let weak = RingSignal.dBm(-95)
        let unknown = RingSignal.notReported
        let sorted = [unknown, weak, strong].sorted { $0.sortKey > $1.sortKey }
        XCTAssertEqual(sorted, [strong, weak, unknown])
    }
}

final class RingDiscoveryPolicyTests: XCTestCase {

    func testAdmitsSignalsAtOrAboveTheFloor() {
        let policy = RingDiscoveryPolicy(minimumSignal: -100)
        XCTAssertTrue(policy.admits(.dBm(-100)))
        XCTAssertTrue(policy.admits(.dBm(-40)))
    }

    func testRejectsSignalsBelowTheFloor() {
        let policy = RingDiscoveryPolicy(minimumSignal: -100)
        XCTAssertFalse(policy.admits(.dBm(-110)))
    }

    func testAdmitsUnreportedSignals() {
        // The absence of a measurement is not evidence of a weak one. Dropping these hides a
        // device that is present — the exact class of mistake this module exists to undo.
        let policy = RingDiscoveryPolicy(minimumSignal: -100)
        XCTAssertTrue(policy.admits(.notReported))
    }

    func testStandardPolicyIsMorePermissiveThanTheVendorDefault() {
        // The vendor SDK gates at -85 dBm, which is tight enough to hide a ring on the desk once
        // a hand or a body is in the path.
        XCTAssertLessThan(RingDiscoveryPolicy.standard.minimumSignal, -85)
    }

    func testStandardPolicyHasAFiniteDeadline() {
        // A scan with no deadline is what latched the retry button off. If this assertion is ever
        // relaxed, read README.md root cause #3 first.
        XCTAssertGreaterThan(RingDiscoveryPolicy.standard.deadline, 0)
        XCTAssertLessThanOrEqual(RingDiscoveryPolicy.standard.deadline, 30)
    }
}

final class RingLinkStateMappingTests: XCTestCase {

    func testMapsEveryDocumentedVendorState() {
        XCTAssertEqual(ringLinkState(fromVendorRawValue: 0), .disconnected)
        XCTAssertEqual(ringLinkState(fromVendorRawValue: 1), .connecting)
        XCTAssertEqual(ringLinkState(fromVendorRawValue: 2), .connected)
        XCTAssertEqual(ringLinkState(fromVendorRawValue: 3), .verified)
        XCTAssertEqual(ringLinkState(fromVendorRawValue: 4), .needsPasscode)
        XCTAssertEqual(ringLinkState(fromVendorRawValue: 6), .timedOut)
        XCTAssertEqual(ringLinkState(fromVendorRawValue: 7), .awaitingConfirmationOnRing)
    }

    func testFirmwareDiscoveryIsIgnoredRatherThanMapped() {
        // Raw 5 is DiscoverNewUpdateFirm — not a link state. Emitting it as one would move a
        // pairing flow off its current stage for a reason that has nothing to do with the link.
        XCTAssertNil(ringLinkState(fromVendorRawValue: 5))
    }

    func testUnknownStateIsReportedLoudlyWithItsRawValue() {
        // Never silently dropped: an unmodelled state that vanishes strands the user on a spinner,
        // and the raw value is what tells the next engineer which case to add.
        XCTAssertEqual(ringLinkState(fromVendorRawValue: 99), .unmodelled(99))
    }

    func testConnectedIsNotTerminalButVerifiedIs() {
        // "Connected" is a BLE link; "verified" is a completed handshake. Treating the first as
        // paired is how a flow reports success before the ring has agreed to anything.
        XCTAssertFalse(RingLinkState.connected.isTerminal)
        XCTAssertTrue(RingLinkState.verified.isTerminal)
        XCTAssertFalse(RingLinkState.verified.isFailure)
    }

    func testNeedsPasscodeIsNotAFailure() {
        // A non-default code is a prompt, not an error.
        XCTAssertFalse(RingLinkState.needsPasscode.isFailure)
        XCTAssertFalse(RingLinkState.needsPasscode.isTerminal)
    }
}
