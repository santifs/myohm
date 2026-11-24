package com.volumhealth.core.common

/** Utility for computing CRC16-CCITT (0x1021 polynomial) checksums. */
object CRC16 {
    private const val POLY = 0x1021
    private const val INITIAL = 0xFFFF

    fun calculate(data: ByteArray): UShort {
        var crc = INITIAL
        data.forEach { byte ->
            crc = crc xor ((byte.toInt() shl 8) and 0xFFFF)
            repeat(8) {
                crc = if ((crc and 0x8000) != 0) {
                    ((crc shl 1) xor POLY) and 0xFFFF
                } else {
                    (crc shl 1) and 0xFFFF
                }
            }
        }
        return crc.toUShort()
    }
}
