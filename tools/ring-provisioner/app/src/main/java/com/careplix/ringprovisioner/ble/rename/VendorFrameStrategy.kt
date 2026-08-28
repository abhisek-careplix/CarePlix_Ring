package com.careplix.ringprovisioner.ble.rename

import android.bluetooth.BluetoothGattCharacteristic
import com.careplix.ringprovisioner.ble.BleException
import com.careplix.ringprovisioner.ble.BleGattClient
import com.careplix.ringprovisioner.ble.GattSnapshot
import java.util.UUID

/**
 * Sends a vendor command frame to a characteristic chosen by the operator.
 *
 * Deliberately not hard-coded to any particular ring. The CarePlix ring's command set is not
 * available to this project, and guessing opcodes against unknown firmware risks writing
 * something destructive to a device on a production line. Instead the operator reads the
 * diagnostics dump, gets the real service/characteristic/opcode from the firmware vendor, and
 * enters them here; once confirmed on hardware, the values can be promoted to a preset in
 * [VendorPresets] so line staff never have to type them again.
 */
class VendorFrameStrategy(
    override val id: String,
    override val label: String,
    private val serviceUuid: UUID,
    private val writeCharacteristicUuid: UUID,
    private val opcode: Byte,
    private val framing: Framing,
) : RenameStrategy {

    override fun isApplicable(snapshot: GattSnapshot): Boolean =
        snapshot.services
            .firstOrNull { it.uuid == serviceUuid }
            ?.characteristics
            ?.any { it.uuid == writeCharacteristicUuid && it.isWritable }
            ?: false

    override suspend fun rename(client: BleGattClient, snapshot: GattSnapshot, newName: String) {
        val characteristic = client.findCharacteristic(serviceUuid, writeCharacteristicUuid)
            ?: throw BleException("$serviceUuid / $writeCharacteristicUuid not present")

        val frame = CommandFrame.build(opcode, newName, framing)

        val writeType = if (
            characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0
        ) {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        }

        client.write(characteristic, frame, writeType)
    }
}
