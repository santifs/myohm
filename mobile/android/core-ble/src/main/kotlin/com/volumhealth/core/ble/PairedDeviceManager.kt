package com.volumhealth.core.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.content.Context
import javax.inject.Singleton

@Singleton
class PairedDeviceManager(
    context: Context
) {
    private val prefs = context.getSharedPreferences("biomess_ble_paired", Context.MODE_PRIVATE)

    @SuppressLint("MissingPermission")
    fun save(device: BluetoothDevice) {
        prefs.edit()
            .putString(KEY_ADDRESS, device.address)
            .putString(KEY_NAME, device.name)
            .apply()
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    fun getPairedDevice(): PairedDevice? {
        val address = prefs.getString(KEY_ADDRESS, null) ?: return null
        val name = prefs.getString(KEY_NAME, null)
        return PairedDevice(name = name, address = address)
    }

    data class PairedDevice(val name: String?, val address: String)

    private companion object {
        const val KEY_ADDRESS = "address"
        const val KEY_NAME = "name"
    }
}
