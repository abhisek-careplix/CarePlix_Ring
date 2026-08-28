package com.careplix.ringprovisioner

import com.careplix.ringprovisioner.ble.DeviceId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceIdTest {

    @Test
    fun `parses a colon separated mac`() {
        val id = DeviceId.parse("AA:BB:CC:DD:EE:FF")
        assertTrue(id is DeviceId.Mac)
        assertEquals("AA:BB:CC:DD:EE:FF", (id as DeviceId.Mac).value)
    }

    @Test
    fun `upper cases a lower case mac`() {
        val id = DeviceId.parse("aa:bb:cc:dd:ee:ff") as DeviceId.Mac
        assertEquals("AA:BB:CC:DD:EE:FF", id.value)
    }

    @Test
    fun `accepts dash separators`() {
        val id = DeviceId.parse("AA-BB-CC-DD-EE-FF") as DeviceId.Mac
        assertEquals("AA:BB:CC:DD:EE:FF", id.value)
    }

    @Test
    fun `accepts a bare 12 hex mac and inserts colons`() {
        val id = DeviceId.parse("AABBCCDDEEFF") as DeviceId.Mac
        assertEquals("AA:BB:CC:DD:EE:FF", id.value)
    }

    @Test
    fun `strips a mac prefix`() {
        val id = DeviceId.parse("MAC:AABBCCDDEEFF") as DeviceId.Mac
        assertEquals("AA:BB:CC:DD:EE:FF", id.value)
    }

    @Test
    fun `extracts a mac from a uri payload`() {
        val id = DeviceId.parse("careplix://ring/AABBCCDDEEFF") as DeviceId.Mac
        assertEquals("AA:BB:CC:DD:EE:FF", id.value)
    }

    @Test
    fun `extracts a mac from a query parameter`() {
        val id = DeviceId.parse("https://careplix.com/r?mac=AABBCCDDEEFF") as DeviceId.Mac
        assertEquals("AA:BB:CC:DD:EE:FF", id.value)
    }

    @Test
    fun `trims surrounding whitespace from a scan`() {
        val id = DeviceId.parse("  AA:BB:CC:DD:EE:FF \n") as DeviceId.Mac
        assertEquals("AA:BB:CC:DD:EE:FF", id.value)
    }

    @Test
    fun `mixed separators are not a mac`() {
        // A half-dashed, half-coloned string is a mangled label, not an address worth trusting.
        assertTrue(DeviceId.parse("AA-BB:CC-DD:EE-FF") is DeviceId.Serial)
    }

    @Test
    fun `a non mac string is kept as a serial`() {
        val id = DeviceId.parse("CPR24A0007731")
        assertTrue(id is DeviceId.Serial)
        assertEquals("CPR24A0007731", (id as DeviceId.Serial).value)
    }

    @Test
    fun `eleven hex digits is not a mac`() {
        assertTrue(DeviceId.parse("AABBCCDDEEF") is DeviceId.Serial)
    }

    @Test
    fun `blank input parses to null`() {
        assertNull(DeviceId.parse(""))
        assertNull(DeviceId.parse("   "))
    }

    @Test
    fun `short code is the last four hex of the mac`() {
        val id = DeviceId.parse("AA:BB:CC:DD:E5:FF") as DeviceId.Mac
        assertEquals("E5FF", id.shortCode)
    }

    @Test
    fun `serial short code drops punctuation and upper cases`() {
        val id = DeviceId.parse("cpr-24a-00b2") as DeviceId.Serial
        assertEquals("00B2", id.shortCode)
    }
}
