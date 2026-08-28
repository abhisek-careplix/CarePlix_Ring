package com.careplix.ringprovisioner

import com.careplix.ringprovisioner.ble.rename.CommandFrame
import com.careplix.ringprovisioner.ble.rename.Framing
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class CommandFrameTest {

    @Test
    fun `opcode then name concatenates the utf8 bytes`() {
        val frame = CommandFrame.build(0x11, "AB", Framing.OPCODE_THEN_NAME)
        assertArrayEquals(byteArrayOf(0x11, 0x41, 0x42), frame)
    }

    @Test
    fun `opcode length name inserts the byte count`() {
        val frame = CommandFrame.build(0x11, "AB", Framing.OPCODE_LENGTH_NAME)
        assertArrayEquals(byteArrayOf(0x11, 0x02, 0x41, 0x42), frame)
    }

    @Test
    fun `fixed frame is padded to sixteen bytes`() {
        val frame = CommandFrame.build(0x11, "AB", Framing.FIXED_16_CHECKSUM)
        assertEquals(16, frame.size)
        assertEquals(0x11.toByte(), frame[0])
        assertEquals(0x41.toByte(), frame[1])
        assertEquals(0x42.toByte(), frame[2])
        // Bytes between the name and the trailing checksum stay zero.
        for (i in 3 until 15) assertEquals(0.toByte(), frame[i])
    }

    @Test
    fun `fixed frame checksum is the low byte of the preceding sum`() {
        val frame = CommandFrame.build(0x11, "AB", Framing.FIXED_16_CHECKSUM)
        val expected = (0x11 + 0x41 + 0x42) and 0xFF
        assertEquals(expected.toByte(), frame[15])
    }

    @Test
    fun `checksum wraps rather than overflowing`() {
        // 0xFF * 4 = 0x3FC, so only 0xFC survives in a single byte.
        val bytes = ByteArray(4) { 0xFF.toByte() }
        assertEquals(0xFC.toByte(), CommandFrame.checksum(bytes, 4))
    }

    @Test
    fun `a name too long for the fixed frame is rejected`() {
        val tooLong = "L".repeat(CommandFrame.FIXED_FRAME_MAX_NAME + 1)
        assertThrows(IllegalArgumentException::class.java) {
            CommandFrame.build(0x11, tooLong, Framing.FIXED_16_CHECKSUM)
        }
    }

    @Test
    fun `the longest fitting name is accepted`() {
        val exact = "L".repeat(CommandFrame.FIXED_FRAME_MAX_NAME)
        assertEquals(16, CommandFrame.build(0x11, exact, Framing.FIXED_16_CHECKSUM).size)
    }
}
