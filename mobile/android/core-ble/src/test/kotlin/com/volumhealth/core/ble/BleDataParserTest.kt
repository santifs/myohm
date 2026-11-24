package com.volumhealth.core.ble

import com.volumhealth.core.model.BatteryData
import com.volumhealth.core.model.QuaternionData
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class BleDataParserTest {

    @Test
    fun parseMeasurementPoint() {
        val buffer = ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN)
            .putFloat(1000f)
            .putFloat(42.5f)
            .putFloat(-15f)
            .array()

        val point = BleDataParser.parseMeasurementPoint(buffer)
        assertNotNull(point)
        point!!
        assertEquals(1000f, point.frequency, 1e-3f)
        assertEquals(42.5f, point.magnitude, 1e-3f)
        assertEquals(-15f, point.phase, 1e-3f)
    }

    @Test
    fun parseBatteryData() {
        val buffer = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
            .putShort(3800)
            .putShort(95)
            .array()

        val battery = BleDataParser.parseBatteryData(buffer)
        assertEquals(BatteryData(3800u, 95u), battery)
    }

    @Test
    fun parseQuaternion() {
        val buffer = ByteBuffer.allocate(16).order(ByteOrder.LITTLE_ENDIAN)
            .putFloat(1f)
            .putFloat(0f)
            .putFloat(0f)
            .putFloat(0f)
            .array()

        val quaternion = BleDataParser.parseQuaternionData(buffer)
        assertEquals(QuaternionData(1f, 0f, 0f, 0f), quaternion)
    }

    @Test
    fun rejectInvalidPayloads() {
        assertNull(BleDataParser.parseMeasurementPoint(ByteArray(4)))
        assertNull(BleDataParser.parseBatteryData(ByteArray(1)))
        assertNull(BleDataParser.parseQuaternionData(ByteArray(2)))
    }
}
