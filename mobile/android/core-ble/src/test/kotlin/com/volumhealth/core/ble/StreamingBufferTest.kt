package com.volumhealth.core.ble

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class StreamingBufferTest {

    @Test
    fun writesAndReadsData() {
        val buffer = StreamingBuffer()
        buffer.write(byteArrayOf(1, 2, 3))
        buffer.write(byteArrayOf(4, 5))
        assertEquals(5, buffer.size())

        val first = buffer.read(3)
        assertArrayEquals(byteArrayOf(1, 2, 3), first)
        assertEquals(2, buffer.size())

        val second = buffer.read(2)
        assertArrayEquals(byteArrayOf(4, 5), second)
        assertEquals(0, buffer.size())
    }

    @Test(expected = IllegalArgumentException::class)
    fun readMoreThanAvailableThrows() {
        val buffer = StreamingBuffer()
        buffer.write(byteArrayOf(1))
        buffer.read(2)
    }
}
