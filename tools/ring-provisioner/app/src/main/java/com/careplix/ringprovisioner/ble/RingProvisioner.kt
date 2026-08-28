package com.careplix.ringprovisioner.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.content.Context
import com.careplix.ringprovisioner.ble.rename.RenameOutcome
import com.careplix.ringprovisioner.ble.rename.RenameStrategy
import kotlinx.coroutines.delay

/**
 * Drives a single ring through connect -> inspect -> rename -> verify.
 *
 * Kept free of Android UI types so the sequencing can be reasoned about (and later tested)
 * on its own.
 */
@SuppressLint("MissingPermission")
class RingProvisioner(
    private val context: Context,
    private val adapter: BluetoothAdapter,
    private val scanner: BleScanner = BleScanner(adapter),
) {

    /**
     * Connects to [address], reads the full GATT table and Device Information Service, and
     * disconnects.
     *
     * This is the safe operation: it only reads. Run it against a new ring model first -- the
     * resulting [GattSnapshot.toReport] is what tells you whether a rename is even possible.
     */
    suspend fun diagnose(address: String, advertisedName: String? = null): GattSnapshot {
        val device = adapter.getRemoteDevice(address)
        val client = BleGattClient(context, device)
        return try {
            client.connect()
            val services = client.discoverServices()
            val info = readDeviceInformation(client, services)
            GattSnapshot.from(address, advertisedName, services, info)
        } finally {
            client.close()
        }
    }

    /**
     * Renames the ring at [address] to [newName], trying [strategies] in order.
     *
     * Every strategy whose preconditions hold gets an attempt; the first accepted write wins.
     * The result is then verified by disconnecting and re-scanning, because an accepted write
     * is not evidence that the advertised name changed -- firmware can update the GAP
     * characteristic while continuing to advertise the old name.
     */
    suspend fun rename(
        address: String,
        newName: String,
        strategies: List<RenameStrategy>,
        onProgress: (String) -> Unit = {},
    ): RenameOutcome {
        require(newName.isNotBlank()) { "new name must not be blank" }

        val device = adapter.getRemoteDevice(address)
        val client = BleGattClient(context, device)

        val attempted = mutableListOf<String>()
        var applied: RenameStrategy? = null
        var lastError: String? = null

        try {
            onProgress("Connecting to $address")
            client.connect()

            onProgress("Discovering services")
            val services = client.discoverServices()
            val snapshot = GattSnapshot.from(address, null, services)

            val applicable = strategies.filter { it.isApplicable(snapshot) }
            if (applicable.isEmpty()) {
                return RenameOutcome(
                    strategyId = "none",
                    requestedName = newName,
                    writeAccepted = false,
                    verified = false,
                    observedAdvertisedName = null,
                    message = "No rename strategy is applicable to this ring. " +
                        "GAP name writable: ${snapshot.isGapNameWritable}. " +
                        "Vendor candidate services found: " +
                        snapshot.vendorCandidates.joinToString { it.uuid.toString() }
                            .ifEmpty { "none" } + ". " +
                        "Run diagnostics and share the report with the firmware vendor.",
                )
            }

            for (strategy in applicable) {
                attempted += strategy.id
                onProgress("Trying ${strategy.label}")
                val result = runCatching { strategy.rename(client, snapshot, newName) }
                if (result.isSuccess) {
                    applied = strategy
                    break
                }
                lastError = result.exceptionOrNull()?.message
                onProgress("${strategy.label} failed: $lastError")
            }
        } finally {
            client.close()
        }

        if (applied == null) {
            return RenameOutcome(
                strategyId = attempted.joinToString(",").ifEmpty { "none" },
                requestedName = newName,
                writeAccepted = false,
                verified = false,
                observedAdvertisedName = null,
                message = "Every applicable strategy was rejected. Last error: $lastError",
            )
        }

        // The peripheral needs a moment to drop the link and restart advertising before the
        // new name can be observed.
        onProgress("Write accepted. Re-scanning to verify the advertised name")
        delay(POST_WRITE_SETTLE_MS)

        val observed = scanner.findByAddress(address, VERIFY_TIMEOUT_MS)
        val observedName = observed?.advertisedName
        val verified = observedName == newName

        return RenameOutcome(
            strategyId = applied.id,
            requestedName = newName,
            writeAccepted = true,
            verified = verified,
            observedAdvertisedName = observedName,
            message = when {
                verified ->
                    "Ring now advertises \"$newName\". Power cycle it and re-scan to confirm " +
                        "the change persists across reboot."
                observed == null ->
                    "Write was accepted but the ring did not advertise within " +
                        "${VERIFY_TIMEOUT_MS / 1000}s. It may still be reconnecting -- re-scan " +
                        "manually before assuming failure."
                else ->
                    "Write was accepted but the ring still advertises " +
                        "\"${observedName ?: "(no name)"}\". The firmware likely updated the GAP " +
                        "characteristic without updating its advertisement payload."
            },
        )
    }

    /** Best-effort read of DIS. Missing or unreadable fields are skipped, never fatal. */
    private suspend fun readDeviceInformation(
        client: BleGattClient,
        services: List<android.bluetooth.BluetoothGattService>,
    ): Map<String, String> {
        val dis = services.firstOrNull { it.uuid == BleUuids.DEVICE_INFORMATION }
            ?: return emptyMap()

        val wanted = mapOf(
            BleUuids.MANUFACTURER_NAME to "Manufacturer",
            BleUuids.HARDWARE_REVISION to "Hardware revision",
            BleUuids.FIRMWARE_REVISION to "Firmware revision",
            BleUuids.SERIAL_NUMBER to "Serial number",
        )

        return buildMap {
            wanted.forEach { (uuid, label) ->
                val characteristic = dis.getCharacteristic(uuid) ?: return@forEach
                runCatching { client.read(characteristic) }
                    .getOrNull()
                    ?.toString(Charsets.UTF_8)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?.let { put(label, it) }
            }
        }
    }

    private companion object {
        const val POST_WRITE_SETTLE_MS = 1_500L
        const val VERIFY_TIMEOUT_MS = 15_000L
    }
}
