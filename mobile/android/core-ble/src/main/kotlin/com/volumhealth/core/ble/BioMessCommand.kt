package com.volumhealth.core.ble

/** Firmware command opcodes. */
enum class BioMessCommand(val code: Byte) {
    MEASUREMENT(0x01),
    BATTERY_MANUAL(0x02),
    IMU_SINGLE(0x03),
    IMU_STATS(0x04),
    START_AUTO_MODE(0x05),
    STOP_AUTO_MODE(0x06),
    GET_STORED_COUNT(0x07),
    GET_STORED_BATCH(0x08),
    CLEAR_STORED(0x09),
    HEALTH_CHECK(0x0A),
    LED_BLINK(100.toByte());

    companion object {
        fun buildPayload(command: BioMessCommand, payload: ByteArray = byteArrayOf()): ByteArray {
            return byteArrayOf(command.code) + payload
        }
    }
}
