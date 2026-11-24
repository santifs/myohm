package com.volumhealth.core.ble

sealed class ConnectionState {
    object Disconnected : ConnectionState()
    object Scanning : ConnectionState()
    object Connecting : ConnectionState()
    object Connected : ConnectionState()
    object Measuring : ConnectionState()
    data class Error(val message: String) : ConnectionState()
}
