package com.volumhealth.core.ble

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat

/**
 * Helper class for managing BLE-related permissions across different Android versions.
 */
object BlePermissionHelper {

    /**
     * Returns the list of permissions required for BLE scanning based on Android version.
     */
    fun getRequiredPermissions(): List<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ (API 31+)
            listOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT
            )
        } else {
            // Android 11 and below
            listOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
        }
    }

    /**
     * Checks if all required BLE permissions are granted.
     */
    fun hasAllPermissions(context: Context): Boolean {
        return getRequiredPermissions().all { permission ->
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * Returns the list of permissions that are not yet granted.
     */
    fun getMissingPermissions(context: Context): List<String> {
        return getRequiredPermissions().filter { permission ->
            ContextCompat.checkSelfPermission(context, permission) != PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * Checks if Bluetooth is available and enabled on the device.
     */
    fun isBluetoothEnabled(context: Context): Boolean {
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager
        return bluetoothManager?.adapter?.isEnabled == true
    }
}

/**
 * Sealed class representing the result of a permission check.
 */
sealed class PermissionResult {
    data object Granted : PermissionResult()
    data class Denied(val permissions: List<String>) : PermissionResult()
    data object BluetoothDisabled : PermissionResult()
}

/**
 * Sealed class representing the result of attempting to start a BLE scan.
 */
sealed class ScanStartResult {
    data object Success : ScanStartResult()
    data class MissingPermissions(val permissions: List<String>) : ScanStartResult()
    data object BluetoothDisabled : ScanStartResult()
    data object BluetoothNotAvailable : ScanStartResult()
}
