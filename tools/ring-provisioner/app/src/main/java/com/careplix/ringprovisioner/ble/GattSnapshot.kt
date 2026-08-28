package com.careplix.ringprovisioner.ble

import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattService
import java.util.UUID

/**
 * A flattened, printable view of a peripheral's GATT table.
 *
 * This is the point of the diagnostics mode: before any rename can be designed, someone has to
 * see whether 0x2A00 is writable and what the vendor service looks like. Capturing that as a
 * plain data structure means it can be rendered, copied out of the app, and pasted into a
 * ticket for the OEM.
 */
data class GattSnapshot(
    val address: String,
    val advertisedName: String?,
    val services: List<ServiceInfo>,
    val deviceInfo: Map<String, String> = emptyMap(),
) {

    data class ServiceInfo(
        val uuid: UUID,
        val characteristics: List<CharacteristicInfo>,
        val isVendorCandidate: Boolean,
    )

    data class CharacteristicInfo(
        val uuid: UUID,
        val properties: Int,
        val hasCccd: Boolean,
    ) {
        val isReadable: Boolean
            get() = properties and BluetoothGattCharacteristic.PROPERTY_READ != 0

        /** True for either write-with-response or write-without-response. */
        val isWritable: Boolean
            get() = properties and (
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE
                ) != 0

        val isNotifiable: Boolean
            get() = properties and (
                BluetoothGattCharacteristic.PROPERTY_NOTIFY or
                    BluetoothGattCharacteristic.PROPERTY_INDICATE
                ) != 0

        fun propertyLabels(): List<String> = buildList {
            val p = properties
            if (p and BluetoothGattCharacteristic.PROPERTY_READ != 0) add("READ")
            if (p and BluetoothGattCharacteristic.PROPERTY_WRITE != 0) add("WRITE")
            if (p and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0) add("WRITE_NR")
            if (p and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) add("NOTIFY")
            if (p and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0) add("INDICATE")
            if (p and BluetoothGattCharacteristic.PROPERTY_BROADCAST != 0) add("BROADCAST")
            if (p and BluetoothGattCharacteristic.PROPERTY_SIGNED_WRITE != 0) add("SIGNED_WRITE")
            if (p and BluetoothGattCharacteristic.PROPERTY_EXTENDED_PROPS != 0) add("EXTENDED")
        }
    }

    /** The single fact that decides whether the simple rename path is available. */
    val isGapNameWritable: Boolean
        get() = services
            .firstOrNull { it.uuid == BleUuids.GENERIC_ACCESS }
            ?.characteristics
            ?.firstOrNull { it.uuid == BleUuids.DEVICE_NAME }
            ?.isWritable
            ?: false

    /** Services that look like they could carry a proprietary command set. */
    val vendorCandidates: List<ServiceInfo>
        get() = services.filter { it.isVendorCandidate }

    /** Plain-text dump, suitable for sharing with the firmware vendor. */
    fun toReport(): String = buildString {
        appendLine("Ring GATT report")
        appendLine("Address:   $address")
        appendLine("Advertised name: ${advertisedName ?: "(none)"}")
        if (deviceInfo.isNotEmpty()) {
            appendLine()
            appendLine("Device Information Service:")
            deviceInfo.forEach { (key, value) -> appendLine("  $key: $value") }
        }
        appendLine()
        appendLine("GAP device name (0x2A00) writable: $isGapNameWritable")
        appendLine()
        services.forEach { service ->
            val marker = if (service.isVendorCandidate) "  <- vendor candidate" else ""
            appendLine("Service ${service.uuid}$marker")
            service.characteristics.forEach { char ->
                val props = char.propertyLabels().joinToString(",").ifEmpty { "NONE" }
                val cccd = if (char.hasCccd) " +CCCD" else ""
                appendLine("    ${char.uuid}  [$props]$cccd")
            }
        }
    }

    companion object {

        fun from(
            address: String,
            advertisedName: String?,
            services: List<BluetoothGattService>,
            deviceInfo: Map<String, String> = emptyMap(),
        ): GattSnapshot {
            val mapped = services.map { service ->
                ServiceInfo(
                    uuid = service.uuid,
                    isVendorCandidate = service.uuid in BleUuids.VENDOR_CANDIDATES,
                    characteristics = service.characteristics.orEmpty().map { char ->
                        CharacteristicInfo(
                            uuid = char.uuid,
                            properties = char.properties,
                            hasCccd = char.getDescriptor(BleUuids.CCCD) != null,
                        )
                    },
                )
            }
            // Float the likely command channel to the top; operators read this list on a phone.
            val ordered = mapped.sortedByDescending { it.isVendorCandidate }
            return GattSnapshot(address, advertisedName, ordered, deviceInfo)
        }
    }
}
