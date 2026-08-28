package com.careplix.ringprovisioner.ble

/**
 * Builds the BLE name written to a ring.
 *
 * Two constraints drive this:
 *
 * 1. A BLE advertisement is 31 bytes total, shared between the name and every other AD
 *    structure (flags, service UUIDs, TX power). A name long enough to overflow gets silently
 *    truncated to the shortened-local-name AD type, or drops other data. [MAX_ADV_NAME_BYTES]
 *    keeps it comfortably inside that budget.
 *
 * 2. Naming every unit the bare string "LOOP" makes them indistinguishable in a phone's
 *    Bluetooth picker and in support logs. Appending a per-unit suffix derived from the MAC
 *    keeps them addressable at effectively no cost, which is why [suffixed] is the default.
 */
object RingNaming {

    const val BRAND = "LOOP"

    /**
     * Conservative ceiling for the advertised name. The 31-byte advertisement must also carry
     * flags (3 bytes) and the name's own AD header (2 bytes); leaving room for a service UUID
     * puts a safe limit well below the theoretical 26.
     */
    const val MAX_ADV_NAME_BYTES = 20

    /** `LOOP-A1B2` -- brand plus the last 4 hex of the MAC. Recommended. */
    fun suffixed(deviceId: DeviceId, brand: String = BRAND): String =
        clamp("$brand-${deviceId.shortCode}")

    /** The bare brand name, for when the spec really does call for every ring to read "LOOP". */
    fun plain(brand: String = BRAND): String = clamp(brand)

    /**
     * Truncates on a byte boundary, not a character boundary, so a multi-byte character can
     * never be split into an invalid UTF-8 sequence mid-name.
     */
    fun clamp(name: String, maxBytes: Int = MAX_ADV_NAME_BYTES): String {
        val bytes = name.toByteArray(Charsets.UTF_8)
        if (bytes.size <= maxBytes) return name
        var end = maxBytes
        while (end > 0 && (bytes[end].toInt() and 0xC0) == 0x80) end--
        return String(bytes, 0, end, Charsets.UTF_8)
    }

    /** Whether [name] fits the advertisement budget without truncation. */
    fun fits(name: String, maxBytes: Int = MAX_ADV_NAME_BYTES): Boolean =
        name.toByteArray(Charsets.UTF_8).size <= maxBytes
}
