package com.careplix.ringprovisioner.ble.rename

import android.bluetooth.BluetoothGattCharacteristic
import com.careplix.ringprovisioner.ble.BleException
import com.careplix.ringprovisioner.ble.BleGattClient
import com.careplix.ringprovisioner.ble.BleUuids
import com.careplix.ringprovisioner.ble.GattSnapshot

/**
 * Writes the new name straight to the GAP Device Name characteristic (0x2A00).
 *
 * This is the only rename path defined by the Bluetooth spec rather than by a vendor, so it is
 * tried first. Most OEM firmware ships 0x2A00 read-only, in which case [isApplicable] returns
 * false and the flow moves on -- but when it is writable this is a single round trip.
 *
 * Caveat worth repeating: changing 0x2A00 does not necessarily change the advertisement
 * payload. Verification by re-scanning is not optional.
 */
class GapNameStrategy : RenameStrategy {

    override val id: String = "gap-0x2a00"
    override val label: String = "GAP Device Name (0x2A00) write"

    override fun isApplicable(snapshot: GattSnapshot): Boolean = snapshot.isGapNameWritable

    override suspend fun rename(client: BleGattClient, snapshot: GattSnapshot, newName: String) {
        val characteristic = client.findCharacteristic(BleUuids.GENERIC_ACCESS, BleUuids.DEVICE_NAME)
            ?: throw BleException("Generic Access 0x2A00 not present on this device")

        val writeType = if (
            characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0
        ) {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        }

        client.write(characteristic, newName.toByteArray(Charsets.UTF_8), writeType)
    }
}
