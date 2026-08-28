package com.careplix.ringprovisioner.ble.rename

import com.careplix.ringprovisioner.ble.BleUuids

/**
 * Pre-filled vendor strategies offered in the picker.
 *
 * IMPORTANT: none of these opcodes has been confirmed against CarePlix ring firmware. They are
 * plausible shapes for the command channel, not documented commands, and exist so an engineer
 * with a ring on the bench can try the common layouts quickly instead of hand-typing frames.
 * Once the real command is known -- from the ring SDK or from the OEM -- replace this list with
 * the confirmed entry and delete the speculative ones.
 */
object VendorPresets {

    /**
     * Nordic UART is by far the most common command channel on rings and bands in this class.
     * The opcode is a placeholder and must be replaced with the vendor's real "set name" value.
     */
    fun nordicUart(opcode: Byte): VendorFrameStrategy = VendorFrameStrategy(
        id = "nus-opcode-${opcode.toUByte()}",
        label = "Nordic UART, opcode 0x${opcode.toUByte().toString(16).uppercase()}",
        serviceUuid = BleUuids.NUS_SERVICE,
        writeCharacteristicUuid = BleUuids.NUS_RX_WRITE,
        opcode = opcode,
        framing = Framing.OPCODE_THEN_NAME,
    )

    /** Same channel, 16-byte checksummed packet layout. */
    fun nordicUartFixed16(opcode: Byte): VendorFrameStrategy = VendorFrameStrategy(
        id = "nus-fixed16-${opcode.toUByte()}",
        label = "Nordic UART, 16-byte frame, opcode 0x${opcode.toUByte().toString(16).uppercase()}",
        serviceUuid = BleUuids.NUS_SERVICE,
        writeCharacteristicUuid = BleUuids.NUS_RX_WRITE,
        opcode = opcode,
        framing = Framing.FIXED_16_CHECKSUM,
    )
}
