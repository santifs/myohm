package com.volumhealth.core.database.util

import com.volumhealth.core.model.ImpedanceData

/** Public JSON codec for sweep data stored in `measurements.raw_data_json`. */
object ImpedanceJson {
    fun encode(data: ImpedanceData): String = Serialization.encodeImpedance(data)
    fun decode(value: String): ImpedanceData? = runCatching { Serialization.decodeImpedance(value) }.getOrNull()
}
