package com.careplix.ringprovisioner.ble

/**
 * A ring identifier as it comes off a QR code, a 1D barcode, or the manual entry field.
 *
 * The production QR encodes a BLE MAC, but scanners and label printers mangle it in
 * predictable ways (no separators, dashes instead of colons, lowercase, a "MAC:" prefix,
 * surrounding whitespace). [parse] normalises all of those to one canonical form so the
 * rest of the app only ever deals with `AA:BB:CC:DD:EE:FF`.
 *
 * Anything that is not recognisably a MAC is kept as a [Serial] rather than rejected --
 * a label with a vendor serial on it is still useful, it just has to be matched by
 * reading the Device Information Service after connecting instead of by scan filter.
 */
sealed interface DeviceId {

    /** The exact text that was scanned or typed, before normalisation. */
    val raw: String

    /** Last 4 significant characters, used to build a per-unit name suffix. */
    val shortCode: String

    /**
     * A BLE MAC. [value] is always upper-case, colon-separated -- the form
     * `BluetoothAdapter.getRemoteDevice` and `ScanFilter.setDeviceAddress` require.
     */
    data class Mac(override val raw: String, val value: String) : DeviceId {

        /** Last 4 hex digits, e.g. `E5FF`. */
        override val shortCode: String get() = value.replace(":", "").takeLast(4)
    }

    /** Anything that is not a MAC: a vendor serial, a batch code, an opaque token. */
    data class Serial(override val raw: String, val value: String) : DeviceId {

        override val shortCode: String
            get() = value.filter { it.isLetterOrDigit() }.takeLast(4).uppercase()
    }

    companion object {

        private val MAC_SEPARATED = Regex("^([0-9A-Fa-f]{2})([:-])(?:[0-9A-Fa-f]{2}\\2){4}[0-9A-Fa-f]{2}$")
        private val MAC_BARE = Regex("^[0-9A-Fa-f]{12}$")

        /**
         * Strips a `mac:` / `id:` style prefix and any URI wrapper, then classifies what is left.
         *
         * Returns null only for blank input -- every other string parses as at least a [Serial].
         */
        fun parse(input: String): DeviceId? {
            val raw = input.trim()
            if (raw.isEmpty()) return null

            val body = raw
                .substringAfterLast('/')          // careplix://ring/AABBCCDDEEFF
                .substringAfterLast('=')          // https://x/y?mac=AABBCCDDEEFF
                .removePrefix("MAC:").removePrefix("mac:")
                .removePrefix("ID:").removePrefix("id:")
                .removePrefix("SN:").removePrefix("sn:")
                .trim()

            val compact = body.replace(" ", "")

            return when {
                MAC_SEPARATED.matches(compact) -> Mac(raw, normalise(compact.replace("-", ":")))
                MAC_BARE.matches(compact) -> Mac(raw, normalise(compact.chunked(2).joinToString(":")))
                else -> Serial(raw, body)
            }
        }

        private fun normalise(mac: String) = mac.uppercase()
    }
}
