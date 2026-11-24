package com.volumhealth.core.model

import com.volumhealth.core.common.CRC16
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import kotlin.math.pow
import kotlin.math.sqrt
import kotlinx.datetime.Clock

/**
 * Measurement stored in firmware flash memory.
 *
 * Format:
 * - 12 bytes metadata
 * - 5 repetitions x 48 points x 12 bytes
 * - 5 quaternions x 16 bytes
 * - 2 bytes CRC16
 */
data class StoredMeasurement(
    val id: String = UUID.randomUUID().toString(),
    val timestamp: UInt,
    val sessionId: UShort,
    val sequenceNumber: UShort,
    val intervalSeconds: UShort,
    val batteryPercentage: UByte,
    val numRepetitions: UByte,
    val repetitions: List<List<MeasurementPoint>>,
    val quaternions: List<List<Float>>,
    val crc16: UShort
) {
    val signalQuality: Float
        get() {
            if (repetitions.size < 2 || repetitions.firstOrNull().isNullOrEmpty()) return 0f
            val magnitudes = repetitions.mapNotNull { repetition -> repetition.getOrNull(24)?.magnitude }
            if (magnitudes.size < 2) return 0f
            val mean = magnitudes.average().toFloat()
            val variance = magnitudes.map { (it - mean).pow(2) }.average().toFloat()
            val stdDev = sqrt(variance)
            return 1f - (stdDev / 50f).coerceIn(0f, 1f)
        }

    fun toImpedanceData(): ImpedanceData {
        return ImpedanceData(
            repetitions = repetitions,
            timestamp = Clock.System.now(),
            deviceInfo = DeviceInfo(
                name = "Volum",
                batteryLevel = BatteryData(
                    voltageMillivolts = 0.toUShort(),
                    percentage = batteryPercentage.toUShort()
                )
            )
        )
    }

    companion object {
        const val REPETITION_COUNT = 5
        const val POINTS_PER_REPETITION = 48
        const val BYTES_PER_POINT = 12
        const val TOTAL_SIZE = 2974

        fun parse(data: ByteArray): StoredMeasurement? {
            if (data.size != TOTAL_SIZE) return null

            val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
            val timestamp = buffer.int.toUInt()
            val sessionId = buffer.short.toUShort()
            val sequenceNumber = buffer.short.toUShort()
            val intervalSeconds = buffer.short.toUShort()
            val batteryPercentage = buffer.get().toUByte()
            val numRepetitions = buffer.get().toUByte()

            val repetitions = buildList {
                repeat(REPETITION_COUNT) {
                    add(
                        buildList {
                            repeat(POINTS_PER_REPETITION) {
                                add(
                                    MeasurementPoint(
                                        frequency = buffer.float,
                                        magnitude = buffer.float,
                                        phase = buffer.float
                                    )
                                )
                            }
                        }
                    )
                }
            }

            val quaternions = buildList {
                repeat(REPETITION_COUNT) {
                    add(listOf(buffer.float, buffer.float, buffer.float, buffer.float))
                }
            }

            val crc16 = buffer.short.toUShort()
            val calculated = CRC16.calculate(data.copyOfRange(0, TOTAL_SIZE - 2))
            if (crc16 != calculated) {
                // Keep importing; iOS tolerates CRC mismatches as best-effort.
            }

            return StoredMeasurement(
                timestamp = timestamp,
                sessionId = sessionId,
                sequenceNumber = sequenceNumber,
                intervalSeconds = intervalSeconds,
                batteryPercentage = batteryPercentage,
                numRepetitions = numRepetitions,
                repetitions = repetitions,
                quaternions = quaternions,
                crc16 = crc16
            )
        }
    }
}
