package com.careplix.ringprovisioner.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Observation of one advertising device.
 *
 * [advertisedName] is the name carried in the advertisement or scan response, which is what a
 * phone's Bluetooth picker displays. It is deliberately kept separate from the GAP device name
 * (characteristic 0x2A00): firmware can accept a write to the latter while continuing to
 * advertise the former, and a rename that only changes the GAP name is invisible to users.
 */
data class DiscoveredRing(
    val address: String,
    val advertisedName: String?,
    val rssi: Int,
    val device: BluetoothDevice,
)

@SuppressLint("MissingPermission")
class BleScanner(private val adapter: BluetoothAdapter) {

    /**
     * Streams advertisements, optionally restricted to a single MAC.
     *
     * Passing [address] pushes the match down into the Bluetooth controller via [ScanFilter],
     * so an unrelated ring on the bench cannot be provisioned by accident -- worth doing on a
     * production line where dozens are advertising at once.
     */
    fun scan(address: String? = null): Flow<DiscoveredRing> = callbackFlow {
        val scanner = adapter.bluetoothLeScanner
            ?: throw BleException("Bluetooth is off or LE scanning is unavailable")

        val filters = address
            ?.let { listOf(ScanFilter.Builder().setDeviceAddress(it).build()) }
            .orEmpty()

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .build()

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                trySend(
                    DiscoveredRing(
                        address = result.device.address,
                        // scanRecord.deviceName covers both the AD-type 0x09 complete local
                        // name and the 0x08 shortened one.
                        advertisedName = result.scanRecord?.deviceName ?: result.device.name,
                        rssi = result.rssi,
                        device = result.device,
                    )
                )
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach { onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, it) }
            }

            override fun onScanFailed(errorCode: Int) {
                close(BleException("BLE scan failed", errorCode))
            }
        }

        scanner.startScan(filters, settings, callback)
        awaitClose { runCatching { scanner.stopScan(callback) } }
    }

    /** Waits for one specific MAC to advertise. Returns null if it never shows up. */
    suspend fun findByAddress(address: String, timeoutMs: Long = 15_000L): DiscoveredRing? =
        withTimeoutOrNull(timeoutMs) { scan(address).first() }
}
