package com.careplix.ringprovisioner.ble.rename

/**
 * How a name is packed into a vendor command frame.
 *
 * Kept free of Android types so the encoding can be unit tested on the JVM -- getting a
 * checksum or a length byte wrong is exactly the kind of bug that is expensive to find with a
 * ring on the bench and cheap to find here.
 */
enum class Framing {
    /** `[opcode][name bytes]` -- length implied by the ATT write length. */
    OPCODE_THEN_NAME,

    /** `[opcode][length][name bytes]` -- explicit length byte. */
    OPCODE_LENGTH_NAME,

    /**
     * Fixed 16-byte packet: `[opcode][name bytes][zero padding][checksum]`, where the checksum
     * is the low byte of the sum of the preceding 15. This layout is used by several ring
     * platforms in this class.
     */
    FIXED_16_CHECKSUM,
}

object CommandFrame {

    const val FIXED_FRAME_SIZE = 16

    /** Longest name that fits [Framing.FIXED_16_CHECKSUM], after opcode and checksum bytes. */
    const val FIXED_FRAME_MAX_NAME = FIXED_FRAME_SIZE - 2

    fun build(opcode: Byte, name: String, framing: Framing): ByteArray {
        val bytes = name.toByteArray(Charsets.UTF_8)
        return when (framing) {
            Framing.OPCODE_THEN_NAME -> byteArrayOf(opcode) + bytes

            Framing.OPCODE_LENGTH_NAME -> {
                require(bytes.size <= 0xFF) { "name too long for a single length byte" }
                byteArrayOf(opcode, bytes.size.toByte()) + bytes
            }

            Framing.FIXED_16_CHECKSUM -> {
                require(bytes.size <= FIXED_FRAME_MAX_NAME) {
                    "name of ${bytes.size} bytes does not fit a $FIXED_FRAME_SIZE-byte frame " +
                        "(max $FIXED_FRAME_MAX_NAME)"
                }
                val frame = ByteArray(FIXED_FRAME_SIZE)
                frame[0] = opcode
                bytes.copyInto(frame, destinationOffset = 1)
                frame[FIXED_FRAME_SIZE - 1] = checksum(frame, FIXED_FRAME_SIZE - 1)
                frame
            }
        }
    }

    /** Low byte of the unsigned sum of the first [length] bytes. */
    fun checksum(frame: ByteArray, length: Int): Byte {
        var sum = 0
        for (i in 0 until length) sum += frame[i].toInt() and 0xFF
        return (sum and 0xFF).toByte()
    }
}
