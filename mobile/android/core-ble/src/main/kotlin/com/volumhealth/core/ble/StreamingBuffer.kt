package com.volumhealth.core.ble

import java.io.ByteArrayOutputStream

/** Simple byte buffer helper used to reassemble fragmented BLE packets. */
class StreamingBuffer {
    private val buffer = ByteArrayOutputStream()

    fun write(data: ByteArray) {
        buffer.write(data)
    }

    fun size(): Int = buffer.size()

    fun clear() {
        buffer.reset()
    }

    fun read(count: Int): ByteArray {
        val current = buffer.toByteArray()
        require(count <= current.size) { "Requested $count bytes but buffer has ${current.size}" }
        val head = current.copyOfRange(0, count)
        buffer.reset()
        if (count < current.size) {
            buffer.write(current, count, current.size - count)
        }
        return head
    }

    fun toByteArray(): ByteArray = buffer.toByteArray()
}
