package com.volumhealth.core.model

import kotlin.math.sqrt

data class DeviceInfo(
    val name: String,
    val serialNumber: String? = null,
    val batteryLevel: BatteryData? = null,
    val quaternion: QuaternionData? = null,
    val quaternionVariance: QuaternionData? = null
)

data class BatteryData(
    val voltageMillivolts: UShort,
    val percentage: UShort
) {
    val voltage: Double get() = voltageMillivolts.toDouble() / 1000.0
}

data class QuaternionData(
    val w: Float,
    val x: Float,
    val y: Float,
    val z: Float
) {
    val magnitude: Float get() = sqrt(w * w + x * x + y * y + z * z)
}
