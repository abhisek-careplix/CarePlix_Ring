package com.careplix.ringprovisioner.ble

import java.util.UUID

/**
 * UUIDs the provisioner looks for.
 *
 * Only the SIG-assigned ones are guaranteed to mean what their name says. Everything under
 * [VENDOR_CANDIDATES] is a *guess* -- a service UUID commonly used by ring/band firmware --
 * and is used purely to rank the diagnostics dump so the likely command channel floats to
 * the top. Nothing in this file is a claim about what CarePlix ring firmware actually does.
 */
object BleUuids {

    /** Base for all 16-bit SIG UUIDs. */
    private const val SIG_BASE = "0000%04x-0000-1000-8000-00805f9b34fb"

    fun sig(short: Int): UUID = UUID.fromString(String.format(SIG_BASE, short))

    /** Generic Access. Holds the GAP device name. */
    val GENERIC_ACCESS: UUID = sig(0x1800)

    /**
     * GAP Device Name. The BLE spec permits this to be writable; most OEM firmware ships it
     * read-only. If it carries PROPERTY_WRITE, renaming is a single write.
     */
    val DEVICE_NAME: UUID = sig(0x2A00)

    /** Device Information Service, and the characteristics worth reading off it. */
    val DEVICE_INFORMATION: UUID = sig(0x180A)
    val SERIAL_NUMBER: UUID = sig(0x2A25)
    val FIRMWARE_REVISION: UUID = sig(0x2A26)
    val HARDWARE_REVISION: UUID = sig(0x2A27)
    val MANUFACTURER_NAME: UUID = sig(0x2A29)

    /** Client Characteristic Configuration -- written to enable notifications. */
    val CCCD: UUID = sig(0x2902)

    /** Nordic UART Service, the most common vendor command channel on this class of device. */
    val NUS_SERVICE: UUID = UUID.fromString("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    val NUS_RX_WRITE: UUID = UUID.fromString("6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    val NUS_TX_NOTIFY: UUID = UUID.fromString("6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    /**
     * Service UUIDs frequently seen carrying proprietary command sets on rings and bands.
     * Used only to sort the diagnostics view -- presence here proves nothing.
     */
    val VENDOR_CANDIDATES: List<UUID> = listOf(
        NUS_SERVICE,
        sig(0xFFF0),
        sig(0xFEE0),
        sig(0xFEE7),
        sig(0xFE59),
        sig(0xFD00),
    )
}
