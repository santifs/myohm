package com.volumhealth.core.ble

import com.volumhealth.core.model.BatteryData
import com.volumhealth.core.model.MeasurementPoint
import com.volumhealth.core.model.QuaternionData
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Binary parsing helpers for BLE payloads. */
object BleDataParser {

    fun parseMeasurementPoint(data: ByteArray): MeasurementPoint? {
        if (data.size != 12) return null

        return try {
            val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
            MeasurementPoint(
                frequency = buffer.float,
                magnitude = buffer.float,
                phase = buffer.float
            )
        } catch (ex: Exception) {
            null
        }
    }

    fun parseBatteryData(data: ByteArray): BatteryData? {
        if (data.size != 4) return null
        val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        val voltageMv = buffer.short.toUShort()
        val percentage = buffer.short.toUShort()
        return BatteryData(voltageMillivolts = voltageMv, percentage = percentage)
    }

    fun parseQuaternionData(data: ByteArray): QuaternionData? {
        if (data.size != 16) return null
        val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        return QuaternionData(
            w = buffer.float,
            x = buffer.float,
            y = buffer.float,
            z = buffer.float
        )
    }
}
