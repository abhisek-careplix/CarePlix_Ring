package com.careplix.ringprovisioner.ble.rename

import com.careplix.ringprovisioner.ble.BleGattClient
import com.careplix.ringprovisioner.ble.GattSnapshot

/**
 * One way of asking a ring to change its BLE name.
 *
 * There is no portable way to do this. The BLE spec permits the GAP device name to be
 * writable but does not require it, and every vendor that supports renaming out-of-band does
 * it with a different proprietary opcode. So the provisioner carries several strategies,
 * probes which ones the connected hardware admits to supporting, and applies the first that
 * works. Adding support for a new ring family means adding a class here, not touching the flow.
 */
interface RenameStrategy {

    /** Stable key used in logs and reports. */
    val id: String

    /** Human-readable label shown in the strategy picker. */
    val label: String

    /**
     * Whether this strategy is worth attempting against the discovered GATT table.
     *
     * A `true` here means "the required characteristics exist with the required properties",
     * not "this will work" -- firmware routinely exposes a writable characteristic and then
     * rejects or silently ignores the write.
     */
    fun isApplicable(snapshot: GattSnapshot): Boolean

    /**
     * Attempts the rename. Implementations should throw on transport failure and let the
     * caller decide whether to fall through to the next strategy.
     */
    suspend fun rename(client: BleGattClient, snapshot: GattSnapshot, newName: String)
}

/**
 * Outcome of a full provisioning attempt.
 *
 * [verified] is the field that matters. A write that returns GATT_SUCCESS proves only that the
 * peripheral accepted the bytes. Until the ring has been re-scanned and seen advertising the
 * new name, the rename has not actually been demonstrated -- and until it has been power
 * cycled and re-scanned again, it has not been shown to persist.
 */
data class RenameOutcome(
    val strategyId: String,
    val requestedName: String,
    val writeAccepted: Boolean,
    val verified: Boolean,
    val observedAdvertisedName: String?,
    val message: String,
) {
    val succeeded: Boolean get() = writeAccepted && verified
}
