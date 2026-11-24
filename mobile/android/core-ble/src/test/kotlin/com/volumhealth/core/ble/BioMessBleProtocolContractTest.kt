package com.volumhealth.core.ble

import java.util.UUID
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BioMessBleProtocolContractTest {

    @Test
    fun uuidsMatchFirmwareContract() {
        assertEquals(UUID.fromString("0000af00-0000-1000-8000-00805f9b34fb"), BioMessBleUuids.CONTROL_SERVICE)
        assertEquals(UUID.fromString("0000af01-0000-1000-8000-00805f9b34fb"), BioMessBleUuids.CONFIG_SERVICE)
        assertEquals(UUID.fromString("0000af02-0000-1000-8000-00805f9b34fb"), BioMessBleUuids.DATA_SERVICE)
        assertEquals(UUID.fromString("0000af03-0000-1000-8000-00805f9b34fb"), BioMessBleUuids.ENV_SERVICE)

        assertEquals(UUID.fromString("0000c000-0000-1000-8000-00805f9b34fb"), BioMessBleUuids.CONTROL_COMMAND)
        assertEquals(UUID.fromString("0000c011-0000-1000-8000-00805f9b34fb"), BioMessBleUuids.RCAL)
        assertEquals(UUID.fromString("0000c012-0000-1000-8000-00805f9b34fb"), BioMessBleUuids.SWEEP_ENABLE)
        assertEquals(UUID.fromString("0000c013-0000-1000-8000-00805f9b34fb"), BioMessBleUuids.SWEEP_START_FREQ)
        assertEquals(UUID.fromString("0000c014-0000-1000-8000-00805f9b34fb"), BioMessBleUuids.SWEEP_STOP_FREQ)
        assertEquals(UUID.fromString("0000c015-0000-1000-8000-00805f9b34fb"), BioMessBleUuids.SWEEP_POINTS)
        assertEquals(UUID.fromString("0000c017-0000-1000-8000-00805f9b34fb"), BioMessBleUuids.NUM_REPETITIONS)
        assertEquals(UUID.fromString("0000c202-0000-1000-8000-00805f9b34fb"), BioMessBleUuids.BATTERY_LEVEL)
    }

    @Test
    fun commandOpcodesMatchFirmwareContract() {
        val expected = mapOf(
            BioMessCommand.MEASUREMENT to 0x01,
            BioMessCommand.BATTERY_MANUAL to 0x02,
            BioMessCommand.IMU_SINGLE to 0x03,
            BioMessCommand.IMU_STATS to 0x04,
            BioMessCommand.START_AUTO_MODE to 0x05,
            BioMessCommand.STOP_AUTO_MODE to 0x06,
            BioMessCommand.GET_STORED_COUNT to 0x07,
            BioMessCommand.GET_STORED_BATCH to 0x08,
            BioMessCommand.CLEAR_STORED to 0x09,
            BioMessCommand.HEALTH_CHECK to 0x0A,
            BioMessCommand.LED_BLINK to 0x64,
        )

        expected.forEach { (command, code) ->
            assertEquals(code.toByte(), command.code)
        }
    }

    @Test
    fun commandPayloadPrependsOpcode() {
        assertArrayEquals(
            byteArrayOf(0x08, 0x34, 0x12, 0x02),
            BioMessCommand.buildPayload(
                BioMessCommand.GET_STORED_BATCH,
                byteArrayOf(0x34, 0x12, 0x02),
            ),
        )

        assertArrayEquals(byteArrayOf(0x0A), BioMessCommand.buildPayload(BioMessCommand.HEALTH_CHECK))
        assertArrayEquals(byteArrayOf(0x64), BioMessCommand.buildPayload(BioMessCommand.LED_BLINK))
    }

    @Test
    fun advertisedNameAndPrefixesMatchFirmwareHandoff() {
        assertEquals("BioMess", BioMessBleManager.ADVERTISED_DEVICE_NAME)
        assertEquals(listOf("BIOMESS"), BioMessBleManager.ACCEPTED_DEVICE_NAME_PREFIXES)
        assertEquals(BioMessBleUuids.CONTROL_SERVICE, BioMessBleManager.ADVERTISED_SERVICE_UUID)
    }
}
