package com.careplix.ringprovisioner

import com.careplix.ringprovisioner.ble.DeviceId
import com.careplix.ringprovisioner.ble.RingNaming
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RingNamingTest {

    @Test
    fun `suffixed name appends the mac short code`() {
        val id = DeviceId.parse("AA:BB:CC:DD:E5:FF") as DeviceId.Mac
        assertEquals("LOOP-E5FF", RingNaming.suffixed(id))
    }

    @Test
    fun `plain name is the bare brand`() {
        assertEquals("LOOP", RingNaming.plain())
    }

    @Test
    fun `a name inside the budget is unchanged`() {
        assertEquals("LOOP-E5FF", RingNaming.clamp("LOOP-E5FF"))
    }

    @Test
    fun `an over long name is truncated to the budget`() {
        val long = "L".repeat(40)
        assertEquals(RingNaming.MAX_ADV_NAME_BYTES, RingNaming.clamp(long).length)
    }

    @Test
    fun `truncation never splits a multi byte character`() {
        // Each of these is 3 UTF-8 bytes, so a naive byte cut at 20 would land mid-character.
        val name = "é".repeat(30)
        val clamped = RingNaming.clamp(name)
        val bytes = clamped.toByteArray(Charsets.UTF_8)
        assertTrue(bytes.size <= RingNaming.MAX_ADV_NAME_BYTES)
        // Round-tripping proves no invalid sequence was produced.
        assertEquals(clamped, String(bytes, Charsets.UTF_8))
    }

    @Test
    fun `fits reports the advertisement budget`() {
        assertTrue(RingNaming.fits("LOOP-E5FF"))
        assertFalse(RingNaming.fits("L".repeat(40)))
    }
}
