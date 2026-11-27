package com.volumhealth.core.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.os.ParcelUuid
import android.os.SystemClock
import android.util.Log
import com.volumhealth.core.model.BatteryData
import com.volumhealth.core.model.DeviceInfo
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.MeasurementPoint
import com.volumhealth.core.model.QuaternionData
import com.volumhealth.core.model.StoredMeasurement
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import javax.inject.Singleton
import kotlin.math.pow
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.datetime.Clock
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

private const val TAG = "BioMessBLE"

data class SweepConfiguration(
    val startFrequency: Float,
    val stopFrequency: Float,
    val points: Int,
    val repetitions: Int
)

@Singleton
class BioMessBleManager(
    private val context: Context,
    private val pairedDeviceManager: PairedDeviceManager
) {
    companion object {
        private const val BYTES_PER_MEASUREMENT_POINT = 12  // sizeof(BioimpedanceMeasurement) = 3 floats × 4 bytes
        const val MAX_SWEEP_FREQUENCY_HZ = 198_000f
        const val ADVERTISED_DEVICE_NAME = "BioMess"
        val ACCEPTED_DEVICE_NAME_PREFIXES = listOf("BIOMESS")
        val ADVERTISED_SERVICE_UUID: UUID = BioMessBleUuids.CONTROL_SERVICE
    }

    private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val bluetoothAdapter: BluetoothAdapter?
        get() = bluetoothManager.adapter

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private val _discoveredDevices = MutableStateFlow<List<BluetoothDevice>>(emptyList())
    val discoveredDevices: StateFlow<List<BluetoothDevice>> = _discoveredDevices.asStateFlow()

    private val _currentBatteryLevel = MutableStateFlow<BatteryData?>(null)
    val currentBatteryLevel: StateFlow<BatteryData?> = _currentBatteryLevel.asStateFlow()

    private val _isDeviceReady = MutableStateFlow(false)
    val isDeviceReady: StateFlow<Boolean> = _isDeviceReady.asStateFlow()

    /** Fraction (0–1) of the bytes of the current sweep received so far. */
    private val _liveSweepProgress = MutableStateFlow(0.0)
    val liveSweepProgress: StateFlow<Double> = _liveSweepProgress.asStateFlow()

    /** Points received so far, one per frequency; later repetitions overwrite earlier ones. */
    private val _liveSweepPoints = MutableStateFlow<List<MeasurementPoint>>(emptyList())
    val liveSweepPoints: StateFlow<List<MeasurementPoint>> = _liveSweepPoints.asStateFlow()

    @Volatile private var bluetoothGatt: BluetoothGatt? = null
    private val characteristicMap = mutableMapOf<UUID, BluetoothGattCharacteristic>()

    private val measurementLock = Any()
    private val measurementBuffer = StreamingBuffer()
    private var expectedStreamingBytes: Int? = null
    private var expectedMeasurementPoints = 48
    private var measurementContinuation: CancellableContinuation<ImpedanceData>? = null
    private var lastDataReceivedTime = 0L
    private var measurementTimeoutJob: Job? = null

    private var currentDeviceInfo: DeviceInfo? = null

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device ?: return
            val name = result.scanRecord?.deviceName ?: device.name
            val serviceUuids = result.scanRecord?.serviceUuids.orEmpty()
            val advertisesBioMessService = serviceUuids.contains(ParcelUuid(ADVERTISED_SERVICE_UUID))
            val hasBioMessName = name
                ?.uppercase()
                ?.let { upper -> ACCEPTED_DEVICE_NAME_PREFIXES.any { upper.startsWith(it) } }
                ?: false
            if (!hasBioMessName && !advertisesBioMessService) {
                Log.v(TAG, "Scan: skipping '${name ?: "unknown"}' (${device.address}) - not BioMess")
                return
            }
            val devices = _discoveredDevices.value
            if (devices.any { it.address == device.address }) return
            Log.i(TAG, "Scan: discovered '${name ?: ADVERTISED_DEVICE_NAME}' (${device.address}) RSSI=${result.rssi}")
            _discoveredDevices.value = devices + device
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "Scan failed with error code: $errorCode")
            _connectionState.value = ConnectionState.Error("Scan failed (error $errorCode)")
        }
    }

    private val readMutex = Mutex()
    private val writeMutex = Mutex()
    private var pendingRead: CompletableDeferred<ByteArray>? = null
    private var pendingWrite: CompletableDeferred<Boolean>? = null
    private var pendingDescriptor: CompletableDeferred<Boolean>? = null
    private var pendingStoredCount: CompletableDeferred<Int>? = null
    private var pendingStoredBatch: CompletableDeferred<List<StoredMeasurement>>? = null

    private enum class DataMode { Idle, Measurement, StoredSync }
    @Volatile private var dataMode: DataMode = DataMode.Idle
    private var storedChunkListener: ((ByteArray) -> Unit)? = null
    private val storedReassemblyBuffer = ByteArrayOutputStream()
    private var expectedStoredBatchCount = 0
    private val receivedStoredMeasurements = mutableListOf<StoredMeasurement>()

    @Suppress("DEPRECATION")
    private val gattCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (gatt !== bluetoothGatt) return
            Log.d(TAG, "onConnectionStateChange: status=$status newState=$newState (0=disconnected, 2=connected)")
            if (status != BluetoothGatt.GATT_SUCCESS && newState != BluetoothProfile.STATE_CONNECTED) {
                Log.e(TAG, "Connection failed: GATT status=$status")
                handleDisconnect(gatt)
                return
            }
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    Log.i(TAG, "Connected to ${gatt.device?.name ?: gatt.device?.address}")
                    _connectionState.value = ConnectionState.Connected
                    reconnectAttempts = 0
                    reconnectJob?.cancel()
                    Log.d(TAG, "Discovering services...")
                    gatt.discoverServices()
                    pairedDeviceManager.save(gatt.device)
                    // Safety timeout: if device isn't ready after 3s, mark as ready anyway
                    scope.launch {
                        delay(3.seconds)
                        if (!_isDeviceReady.value) {
                            Log.w(TAG, "Safety timeout: marking device ready after 3s")
                            _isDeviceReady.value = true
                        }
                    }
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    Log.i(TAG, "Disconnected (GATT status=$status)")
                    handleDisconnect(gatt)
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            Log.d(TAG, "onServicesDiscovered: status=$status")
            if (status != BluetoothGatt.GATT_SUCCESS) {
                Log.e(TAG, "Service discovery failed: status=$status")
                return
            }
            cacheCharacteristics(gatt)
            Log.d(TAG, "Cached ${characteristicMap.size} characteristics")
            for ((uuid, _) in characteristicMap) {
                Log.v(TAG, "  Characteristic: $uuid")
            }
            scope.launch {
                try {
                    Log.d(TAG, "Enabling notifications for CONTROL_COMMAND...")
                    enableNotifications(BioMessBleUuids.CONTROL_COMMAND)
                    Log.d(TAG, "Enabling notifications for BATTERY_LEVEL...")
                    enableNotifications(BioMessBleUuids.BATTERY_LEVEL)
                    Log.d(TAG, "Enabling notifications for IMU_QUATERNION...")
                    enableNotifications(BioMessBleUuids.IMU_QUATERNION)
                    Log.d(TAG, "Enabling notifications for IMU_Q_VARIANCE...")
                    enableNotifications(BioMessBleUuids.IMU_Q_VARIANCE)
                    Log.d(TAG, "Reading serial number...")
                    readSerialNumber()
                    _isDeviceReady.value = true
                    Log.i(TAG, "Device setup complete — ready for measurements")
                } catch (e: Exception) {
                    Log.e(TAG, "Error during device setup: ${e.message}", e)
                    // Still mark as ready so the user can attempt operations
                    _isDeviceReady.value = true
                }
            }
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            if (gatt !== bluetoothGatt) return
            Log.d(TAG, "onCharacteristicRead: uuid=${characteristic.uuid} status=$status size=${characteristic.value?.size ?: 0}")
            pendingRead?.apply {
                if (!isCompleted) {
                    if (status == BluetoothGatt.GATT_SUCCESS) complete(characteristic.value)
                    else completeExceptionally(IllegalStateException("Read failed for ${characteristic.uuid}"))
                }
            }
            pendingRead = null
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            if (gatt !== bluetoothGatt) return
            Log.d(TAG, "onCharacteristicWrite: uuid=${characteristic.uuid} status=$status")
            pendingWrite?.apply {
                if (!isCompleted) {
                    if (status == BluetoothGatt.GATT_SUCCESS) complete(true)
                    else completeExceptionally(IllegalStateException("Write failed for ${characteristic.uuid}"))
                }
            }
            pendingWrite = null
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int
        ) {
            if (gatt !== bluetoothGatt) return
            Log.d(TAG, "onDescriptorWrite: char=${descriptor.characteristic.uuid} status=$status")
            pendingDescriptor?.apply {
                if (!isCompleted) {
                    if (status == BluetoothGatt.GATT_SUCCESS) complete(true)
                    else completeExceptionally(IllegalStateException("Descriptor write failed"))
                }
            }
            pendingDescriptor = null
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic
        ) {
            if (gatt !== bluetoothGatt) return
            val data = characteristic.value ?: return
            Log.d(TAG, "onCharacteristicChanged: uuid=${characteristic.uuid} size=${data.size} mode=$dataMode")
            handleCharacteristicData(gatt, characteristic.uuid, data)
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            Log.d(TAG, "MTU changed to $mtu (status=$status)")
        }
    }

    var isAutoConnectEnabled: Boolean = true
    private var reconnectJob: Job? = null
    private var reconnectAttempts = 0
    private val maxReconnectAttempts = 3

    /** Name and address of the device currently linked, if any. */
    val connectedDeviceName: String?
        @SuppressLint("MissingPermission")
        get() = try { bluetoothGatt?.device?.name } catch (_: SecurityException) { null }

    val connectedDeviceAddress: String?
        get() = bluetoothGatt?.device?.address

    fun pairedDevice(): PairedDeviceManager.PairedDevice? = pairedDeviceManager.getPairedDevice()

    fun forgetPairedDevice() {
        pairedDeviceManager.clear()
    }

    fun hasRequiredPermissions(): Boolean = BlePermissionHelper.hasAllPermissions(context)
    fun getMissingPermissions(): List<String> = BlePermissionHelper.getMissingPermissions(context)
    fun isBluetoothEnabled(): Boolean = BlePermissionHelper.isBluetoothEnabled(context)

    /**
     * Attempt to reconnect to the last-paired device without user interaction.
     * Safe to call at any time — silently fails if permissions are missing,
     * Bluetooth is off, no device has been paired yet, or we are already
     * connected or connecting.
     */
    @SuppressLint("MissingPermission")
    fun reconnectLastKnown(): Boolean {
        val state = _connectionState.value
        if (state is ConnectionState.Connected ||
            state is ConnectionState.Connecting ||
            state is ConnectionState.Measuring
        ) return false
        if (!hasRequiredPermissions() || !isBluetoothEnabled()) return false
        val paired = pairedDeviceManager.getPairedDevice() ?: return false
        val adapter = bluetoothAdapter ?: return false
        return try {
            val device = adapter.getRemoteDevice(paired.address)
            connect(device)
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "reconnectLastKnown: invalid address ${paired.address}")
            false
        }
    }

    fun checkPermissionStatus(): PermissionResult {
        if (!isBluetoothEnabled()) return PermissionResult.BluetoothDisabled
        val missing = getMissingPermissions()
        return if (missing.isEmpty()) PermissionResult.Granted else PermissionResult.Denied(missing)
    }

    /**
     * Force-cancel any pending auto-reconnect attempt and tear down stale GATT state.
     * Call when the user explicitly wants to start fresh (change device, manual scan).
     */
    @SuppressLint("MissingPermission")
    fun cancelAutoReconnectAndReset() {
        Log.i(TAG, "cancelAutoReconnectAndReset()")
        reconnectJob?.cancel()
        reconnectJob = null
        reconnectAttempts = 0
        try {
            bluetoothGatt?.disconnect()
            bluetoothGatt?.close()
        } catch (_: SecurityException) { }
        bluetoothGatt = null
        _isDeviceReady.value = false
        _discoveredDevices.value = emptyList()
        if (_connectionState.value !is ConnectionState.Disconnected) {
            _connectionState.value = ConnectionState.Disconnected
        }
    }

    @SuppressLint("MissingPermission")
    fun startScan(): ScanStartResult {
        Log.i(TAG, "startScan() called")

        // User-initiated scan: kill any in-flight auto-reconnect that may be holding
        // the state in Connecting and clear the stale discovered list.
        cancelAutoReconnectAndReset()

        if (!hasRequiredPermissions()) {
            val missing = getMissingPermissions()
            Log.e(TAG, "Missing permissions: $missing")
            _connectionState.value = ConnectionState.Error("Missing permissions: ${missing.joinToString()}")
            return ScanStartResult.MissingPermissions(missing)
        }

        if (!isBluetoothEnabled()) {
            Log.e(TAG, "Bluetooth is disabled")
            _connectionState.value = ConnectionState.Error("Bluetooth is disabled")
            return ScanStartResult.BluetoothDisabled
        }

        val adapter = bluetoothAdapter
        if (adapter == null) {
            Log.e(TAG, "Bluetooth adapter is null")
            _connectionState.value = ConnectionState.Error("Bluetooth not available")
            return ScanStartResult.BluetoothNotAvailable
        }

        val scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            Log.e(TAG, "BLE scanner is null (Bluetooth may be off)")
            _connectionState.value = ConnectionState.Error("BLE scanner not available")
            return ScanStartResult.BluetoothNotAvailable
        }

        _connectionState.value = ConnectionState.Scanning
        _discoveredDevices.value = emptyList()

        try {
            scanner.startScan(scanCallback)
            Log.i(TAG, "BLE scan started (filter: BioMess only)")
        } catch (e: SecurityException) {
            Log.e(TAG, "Scan SecurityException: ${e.message}")
            _connectionState.value = ConnectionState.Error("Permission denied: ${e.message}")
            return ScanStartResult.MissingPermissions(getMissingPermissions())
        }

        scope.launch {
            delay(10.seconds)
            Log.d(TAG, "Scan timeout (10s) — stopping scan")
            stopScan()
        }

        return ScanStartResult.Success
    }

    @SuppressLint("MissingPermission")
    fun stopScan() {
        Log.d(TAG, "stopScan() called")
        val adapter = bluetoothAdapter
        val scanner = adapter?.bluetoothLeScanner
        if (scanner != null) {
            try {
                scanner.stopScan(scanCallback)
            } catch (_: SecurityException) { }
        }
        // If the user cancels mid-Connecting (typically auto-reconnect in flight),
        // tear it all down so they aren't stuck. Also handles the Scanning case.
        when (_connectionState.value) {
            is ConnectionState.Scanning, is ConnectionState.Connecting -> {
                cancelAutoReconnectAndReset()
            }
            else -> { /* leave Connected/Disconnected/Error untouched */ }
        }
    }

    @SuppressLint("MissingPermission")
    fun connect(device: BluetoothDevice): Boolean {
        Log.i(TAG, "connect() to ${device.name ?: device.address}")
        if (!hasRequiredPermissions()) {
            Log.e(TAG, "connect(): missing permissions")
            _connectionState.value = ConnectionState.Error("Missing Bluetooth permissions")
            return false
        }

        stopScan()
        _connectionState.value = ConnectionState.Connecting
        _isDeviceReady.value = false
        bluetoothGatt?.close()
        reconnectAttempts = 0

        try {
            bluetoothGatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            Log.d(TAG, "connectGatt() initiated")
            return true
        } catch (e: SecurityException) {
            Log.e(TAG, "connect() SecurityException: ${e.message}")
            _connectionState.value = ConnectionState.Error("Permission denied: ${e.message}")
            return false
        }
    }

    @SuppressLint("MissingPermission")
    fun disconnect() {
        Log.i(TAG, "disconnect() called")
        synchronized(measurementLock) {
            val pending = clearMeasurement()
            dataMode = DataMode.Idle
            _isDeviceReady.value = false
            reconnectJob?.cancel()
            val gatt = bluetoothGatt
            bluetoothGatt = null
            try {
                gatt?.disconnect()
                gatt?.close()
            } catch (_: SecurityException) { }
            _connectionState.value = ConnectionState.Disconnected
            pending?.resumeWithException(IllegalStateException("Device disconnected during measurement"))
        }
    }

    suspend fun readSweepConfiguration(): SweepConfiguration {
        val points = readSweepPoints()
        val start = readSweepStartFrequency()
        val stop = readSweepStopFrequency()
        val repetitions = readNumRepetitions()
        Log.d(TAG, "Sweep config: points=$points start=$start stop=$stop reps=$repetitions")
        return SweepConfiguration(
            startFrequency = start,
            stopFrequency = stop,
            points = points,
            repetitions = repetitions
        )
    }

    suspend fun configureRepetitions(count: Int) {
        val sanitized = count.coerceIn(1, 10)
        Log.d(TAG, "configureRepetitions($sanitized)")
        val buffer = byteArrayOf(sanitized.toByte())
        writeCharacteristic(BioMessBleUuids.NUM_REPETITIONS, buffer)
    }

    suspend fun performMeasurement(
        numPoints: Int? = null,
        startFreq: Float? = null,
        stopFreq: Float? = null,
        repetitions: Int? = null
    ): ImpedanceData = suspendCancellableCoroutine { continuation ->
        require(startFreq == null || startFreq.isFinite() && startFreq > 0 && startFreq < MAX_SWEEP_FREQUENCY_HZ)
        require(stopFreq == null || stopFreq.isFinite() && stopFreq > 0 && stopFreq <= MAX_SWEEP_FREQUENCY_HZ)
        require(startFreq == null || stopFreq == null || startFreq < stopFreq)

        synchronized(measurementLock) {
            if (measurementContinuation != null || dataMode != DataMode.Idle) {
                continuation.resumeWithException(IllegalStateException("A BLE operation is already active"))
                return@suspendCancellableCoroutine
            }
            measurementContinuation = continuation
            _liveSweepProgress.value = 0.0
            _liveSweepPoints.value = emptyList()
        }

        val setupJob = scope.launch {
            try {
                withTimeout(30.seconds) {
                    if (!_isDeviceReady.value) {
                        withTimeout(5.seconds) { _isDeviceReady.first { it } }
                    }
                    numPoints?.let { configureSweepPoints(it) }
                    startFreq?.let { configureSweepStartFreq(it) }
                    stopFreq?.let { configureSweepStopFreq(it) }
                    repetitions?.let { configureRepetitions(it) }

                    val configuration = readSweepConfiguration()
                    check(configuration.points in 2..100 && configuration.repetitions in 1..10)
                    check(configuration.startFrequency.isFinite() && configuration.startFrequency > 0 &&
                        configuration.stopFrequency > configuration.startFrequency &&
                        configuration.stopFrequency <= MAX_SWEEP_FREQUENCY_HZ) {
                        "Invalid device sweep frequency range"
                    }

                    synchronized(measurementLock) {
                        if (measurementContinuation !== continuation || !continuation.isActive) {
                            return@withTimeout
                        }
                        expectedMeasurementPoints = configuration.points
                        expectedStreamingBytes = configuration.points * configuration.repetitions * BYTES_PER_MEASUREMENT_POINT
                        dataMode = DataMode.Measurement
                        _liveSweepProgress.value = 0.0
                        _liveSweepPoints.value = emptyList()
                        _connectionState.value = ConnectionState.Measuring
                        lastDataReceivedTime = SystemClock.elapsedRealtime()
                        startMeasurementTimeout(continuation)
                    }
                    sendCommand(BioMessCommand.MEASUREMENT, byteArrayOf())
                }
            } catch (error: Exception) {
                synchronized(measurementLock) {
                    if (measurementContinuation === continuation) {
                        val failure = if (error is TimeoutCancellationException) {
                            IllegalStateException("El dispositivo no respondió al preparar el barrido.", error)
                        } else {
                            error
                        }
                        failMeasurement(failure)
                    }
                }
            }
        }

        continuation.invokeOnCancellation {
            setupJob.cancel()
            synchronized(measurementLock) {
                if (measurementContinuation === continuation) {
                    val streaming = dataMode == DataMode.Measurement
                    clearMeasurement()
                    if (streaming) disconnect()
                }
            }
        }
    }

    private fun startMeasurementTimeout(continuation: CancellableContinuation<ImpedanceData>) {
        measurementTimeoutJob = scope.launch {
            while (true) {
                delay(1.seconds)
                val finished = synchronized(measurementLock) {
                    if (measurementContinuation !== continuation) return@synchronized true

                    val received = measurementBuffer.size()
                    val expected = checkNotNull(expectedStreamingBytes)
                    val timeout = if (received == 0) 30_000L else 5_000L
                    if (SystemClock.elapsedRealtime() - lastDataReceivedTime < timeout) {
                        return@synchronized false
                    }

                    failMeasurement(IllegalStateException(
                        "Barrido incompleto ($received/$expected bytes). Vuelve a conectar el dispositivo."
                    ))
                    true
                }
                if (finished) break
            }
        }
    }

    // Once the unframed stream starts, reconnect before retrying so late packets
    // from the aborted sweep cannot be mistaken for the next one.
    private fun failMeasurement(error: Exception) {
        val streaming = dataMode == DataMode.Measurement
        val pending = clearMeasurement()
        if (streaming) disconnect()
        pending?.resumeWithException(error)
    }

    private fun clearMeasurement(): CancellableContinuation<ImpedanceData>? {
        measurementTimeoutJob?.cancel()
        measurementTimeoutJob = null
        measurementBuffer.clear()
        expectedStreamingBytes = null
        if (dataMode == DataMode.Measurement) dataMode = DataMode.Idle
        val pending = measurementContinuation
        measurementContinuation = null
        return pending
    }

    suspend fun requestStoredCount(): Int {
        Log.d(TAG, "requestStoredCount()")
        val deferred = CompletableDeferred<Int>()
        pendingStoredCount = deferred
        try {
            sendCommand(BioMessCommand.GET_STORED_COUNT, byteArrayOf())
            return withTimeout(5.seconds) { deferred.await() }
        } catch (e: Exception) {
            Log.e(TAG, "requestStoredCount failed: ${e.message}")
            pendingStoredCount = null
            throw e
        }
    }

    suspend fun startAutomaticMode(intervalSeconds: UShort) {
        Log.i(TAG, "startAutomaticMode(interval=${intervalSeconds}s)")
        val payload = ByteBuffer.allocate(2)
            .order(ByteOrder.LITTLE_ENDIAN)
            .putShort(intervalSeconds.toShort())
            .array()
        sendCommand(BioMessCommand.START_AUTO_MODE, payload)
    }

    suspend fun stopAutomaticMode() {
        Log.i(TAG, "stopAutomaticMode()")
        sendCommand(BioMessCommand.STOP_AUTO_MODE, byteArrayOf())
    }

    suspend fun getStoredMeasurementCount(): Int = requestStoredCount()

    suspend fun getStoredMeasurementBatch(offset: Int, count: Int): List<StoredMeasurement> {
        require(count in 1..255) { "count must be between 1 and 255" }

        val payload = ByteBuffer.allocate(3)
            .order(ByteOrder.LITTLE_ENDIAN)
            .putShort(offset.toShort())
            .put(count.toByte())
            .array()

        val deferred = CompletableDeferred<List<StoredMeasurement>>()
        pendingStoredBatch = deferred
        expectedStoredBatchCount = count
        receivedStoredMeasurements.clear()
        storedReassemblyBuffer.reset()
        beginStoredSync(::handleStoredSyncChunk)

        return try {
            sendCommand(BioMessCommand.GET_STORED_BATCH, payload)
            withTimeout(30.seconds) { deferred.await() }
        } finally {
            if (pendingStoredBatch === deferred) {
                pendingStoredBatch = null
            }
            receivedStoredMeasurements.clear()
            expectedStoredBatchCount = 0
            storedReassemblyBuffer.reset()
            endStoredSync()
        }
    }

    suspend fun clearStoredMeasurements() {
        sendCommand(BioMessCommand.CLEAR_STORED, byteArrayOf())
    }

    fun beginStoredSync(listener: (ByteArray) -> Unit) {
        Log.d(TAG, "beginStoredSync()")
        storedChunkListener = listener
        dataMode = DataMode.StoredSync
    }

    fun endStoredSync() {
        Log.d(TAG, "endStoredSync()")
        storedChunkListener = null
        if (dataMode == DataMode.StoredSync) {
            dataMode = DataMode.Idle
        }
    }

    private fun handleStoredSyncChunk(data: ByteArray) {
        storedReassemblyBuffer.write(data)

        while (storedReassemblyBuffer.size() >= StoredMeasurement.TOTAL_SIZE) {
            val buffer = storedReassemblyBuffer.toByteArray()
            val measurementBytes = buffer.copyOfRange(0, StoredMeasurement.TOTAL_SIZE)
            StoredMeasurement.parse(measurementBytes)?.let { receivedStoredMeasurements += it }

            storedReassemblyBuffer.reset()
            if (buffer.size > StoredMeasurement.TOTAL_SIZE) {
                storedReassemblyBuffer.write(buffer, StoredMeasurement.TOTAL_SIZE, buffer.size - StoredMeasurement.TOTAL_SIZE)
            }

            if (receivedStoredMeasurements.size >= expectedStoredBatchCount) {
                pendingStoredBatch?.complete(receivedStoredMeasurements.toList())
                pendingStoredBatch = null
                return
            }
        }
    }

    @SuppressLint("MissingPermission")
    suspend fun sendCommand(command: BioMessCommand, payload: ByteArray) {
        val gatt = bluetoothGatt
        if (gatt == null) {
            Log.e(TAG, "sendCommand(${command.name}): no GATT connection")
            throw IllegalStateException("Not connected")
        }
        val characteristic = characteristicMap[BioMessBleUuids.CONTROL_COMMAND]
        if (characteristic == null) {
            Log.e(TAG, "sendCommand(${command.name}): CONTROL_COMMAND characteristic not found")
            throw IllegalStateException("CONTROL_COMMAND characteristic not found")
        }
        val data = BioMessCommand.buildPayload(command, payload)
        Log.d(TAG, "sendCommand(${command.name}) payload=${data.joinToString { "0x%02x".format(it) }}")
        writeMutex.withLock {
            val deferred = CompletableDeferred<Boolean>()
            pendingWrite = deferred
            characteristic.value = data
            if (!gatt.writeCharacteristic(characteristic)) {
                pendingWrite = null
                Log.e(TAG, "sendCommand(${command.name}): writeCharacteristic returned false")
                deferred.completeExceptionally(IllegalStateException("Unable to write command"))
            }
            deferred.await()
            Log.d(TAG, "sendCommand(${command.name}): write confirmed")
        }
    }

    @SuppressLint("MissingPermission")
    private fun handleDisconnect(gatt: BluetoothGatt) {
        Log.i(TAG, "handleDisconnect()")
        synchronized(measurementLock) {
            if (gatt !== bluetoothGatt) return
            val pending = clearMeasurement()
            bluetoothGatt = null
            gatt.close()
            _isDeviceReady.value = false
            _connectionState.value = ConnectionState.Disconnected
            dataMode = DataMode.Idle
            pending?.resumeWithException(IllegalStateException("Device disconnected during measurement"))
        }
        if (isAutoConnectEnabled) {
            Log.d(TAG, "Auto-reconnect enabled, scheduling reconnect...")
            startAutoReconnect()
        }
    }

    private fun startAutoReconnect() {
        if (reconnectAttempts >= maxReconnectAttempts) {
            Log.w(TAG, "Max reconnect attempts ($maxReconnectAttempts) reached")
            return
        }
        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            val delaySeconds = minOf(5.0 * 2.0.pow(reconnectAttempts), 30.0)
            Log.d(TAG, "Reconnect attempt ${reconnectAttempts + 1}/$maxReconnectAttempts in ${delaySeconds}s")
            delay(delaySeconds.seconds)
            reconnectAttempts++
            pairedDeviceManager.getPairedDevice()?.let { paired ->
                val adapter = bluetoothAdapter ?: return@launch
                val device = adapter.getRemoteDevice(paired.address)
                connect(device)
            }
        }
    }

    private fun cacheCharacteristics(gatt: BluetoothGatt) {
        characteristicMap.clear()
        gatt.services.forEach { service ->
            Log.d(TAG, "Service: ${service.uuid} (${service.characteristics.size} chars)")
            service.characteristics.forEach { characteristic ->
                characteristicMap[characteristic.uuid] = characteristic
            }
        }
    }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    private suspend fun enableNotifications(uuid: UUID) {
        val gatt = bluetoothGatt
        if (gatt == null) {
            Log.w(TAG, "enableNotifications($uuid): no GATT")
            return
        }
        val characteristic = characteristicMap[uuid]
        if (characteristic == null) {
            Log.w(TAG, "enableNotifications($uuid): characteristic not found")
            return
        }
        gatt.setCharacteristicNotification(characteristic, true)
        val descriptor = characteristic.getDescriptor(BioMessBleUuids.CLIENT_CHARACTERISTIC_CONFIG)
        if (descriptor == null) {
            Log.w(TAG, "enableNotifications($uuid): CCCD descriptor not found")
            return
        }
        val deferred = CompletableDeferred<Boolean>()
        pendingDescriptor = deferred
        descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        if (!gatt.writeDescriptor(descriptor)) {
            pendingDescriptor = null
            Log.e(TAG, "enableNotifications($uuid): writeDescriptor returned false")
            return
        }
        deferred.await()
        Log.d(TAG, "enableNotifications($uuid): OK")
    }

    private suspend fun readNumRepetitions(): Int {
        val data = readCharacteristic(BioMessBleUuids.NUM_REPETITIONS)
        val reps = data.firstOrNull()?.toInt()?.coerceAtLeast(1) ?: 1
        Log.d(TAG, "readNumRepetitions: $reps")
        return reps
    }

    private suspend fun readSweepPoints(): Int {
        val data = readCharacteristic(BioMessBleUuids.SWEEP_POINTS)
        val pts = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN).int
        Log.d(TAG, "readSweepPoints: $pts")
        return pts
    }

    private suspend fun readSweepStartFrequency(): Float {
        val data = readCharacteristic(BioMessBleUuids.SWEEP_START_FREQ)
        return ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN).float
    }

    private suspend fun readSweepStopFrequency(): Float {
        val data = readCharacteristic(BioMessBleUuids.SWEEP_STOP_FREQ)
        return ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN).float
    }

    suspend fun configureSweepPoints(points: Int) {
        val sanitized = points.coerceIn(2, 100)
        val buffer = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(sanitized).array()
        writeCharacteristic(BioMessBleUuids.SWEEP_POINTS, buffer)
    }

    suspend fun configureSweepStartFreq(freq: Float) {
        val buffer = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putFloat(freq).array()
        writeCharacteristic(BioMessBleUuids.SWEEP_START_FREQ, buffer)
    }

    suspend fun configureSweepStopFreq(freq: Float) {
        require(freq.isFinite() && freq > 0 && freq <= MAX_SWEEP_FREQUENCY_HZ)
        val buffer = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putFloat(freq).array()
        writeCharacteristic(BioMessBleUuids.SWEEP_STOP_FREQ, buffer)
    }

    @Suppress("DEPRECATION")
    @SuppressLint("MissingPermission")
    private suspend fun writeCharacteristic(uuid: UUID, data: ByteArray) {
        val gatt = bluetoothGatt ?: throw IllegalStateException("Not connected")
        val characteristic = characteristicMap[uuid] ?: throw IllegalStateException("Characteristic $uuid missing")
        Log.d(TAG, "writeCharacteristic($uuid) size=${data.size}")
        writeMutex.withLock {
            val deferred = CompletableDeferred<Boolean>()
            pendingWrite = deferred
            characteristic.value = data
            if (!gatt.writeCharacteristic(characteristic)) {
                pendingWrite = null
                Log.e(TAG, "writeCharacteristic($uuid): writeCharacteristic returned false")
                deferred.completeExceptionally(IllegalStateException("Unable to write $uuid"))
            }
            deferred.await()
        }
    }

    @SuppressLint("MissingPermission")
    private suspend fun readCharacteristic(uuid: UUID): ByteArray {
        val gatt = bluetoothGatt ?: throw IllegalStateException("Not connected")
        val characteristic = characteristicMap[uuid] ?: throw IllegalStateException("Characteristic $uuid missing")
        return readMutex.withLock {
            val deferred = CompletableDeferred<ByteArray>()
            pendingRead = deferred
            if (!gatt.readCharacteristic(characteristic)) {
                pendingRead = null
                Log.e(TAG, "readCharacteristic($uuid): readCharacteristic returned false")
                deferred.completeExceptionally(IllegalStateException("Unable to read $uuid"))
            }
            deferred.await()
        }
    }

    private fun handleCharacteristicData(gatt: BluetoothGatt, uuid: UUID, data: ByteArray) {
        when (uuid) {
            BioMessBleUuids.CONTROL_COMMAND -> handleControlNotification(gatt, data)
            BioMessBleUuids.BATTERY_LEVEL -> {
                Log.d(TAG, "Battery notification: ${data.size} bytes")
                BleDataParser.parseBatteryData(data)?.let { updateBatteryLevel(it) }
            }
            BioMessBleUuids.IMU_QUATERNION -> BleDataParser.parseQuaternionData(data)?.let { updateQuaternion(it) }
            BioMessBleUuids.IMU_Q_VARIANCE -> BleDataParser.parseQuaternionData(data)?.let { updateQuaternionVariance(it) }
            else -> Log.d(TAG, "Unhandled notification from uuid=$uuid size=${data.size}")
        }
    }

    private fun handleControlNotification(gatt: BluetoothGatt, data: ByteArray) {
        Log.d(TAG, "Control notification: ${data.size} bytes, dataMode=$dataMode, hex=${data.joinToString { "0x%02x".format(it) }}")
        val countDeferred = pendingStoredCount
        if (countDeferred != null && countDeferred.isActive) {
            if (data.size >= 2) {
                val count = ByteBuffer.wrap(data.copyOfRange(0, 2)).order(ByteOrder.LITTLE_ENDIAN).short.toInt()
                Log.d(TAG, "Stored count response: $count")
                countDeferred.complete(count)
                pendingStoredCount = null
            }
            return
        }
        // Clear stale deferred if it was cancelled/completed
        if (countDeferred != null) {
            Log.w(TAG, "Clearing stale pendingStoredCount (isActive=${countDeferred.isActive})")
            pendingStoredCount = null
        }
        when (dataMode) {
            DataMode.StoredSync -> storedChunkListener?.invoke(data)
            DataMode.Measurement -> {
                Log.v(TAG, "Measurement data chunk: ${data.size} bytes, buffer total: ${measurementBuffer.size() + data.size}")
                handleStreamingMeasurementData(gatt, data)
            }
            else -> Log.d(TAG, "Control notification in Idle mode (ignored): ${data.size} bytes")
        }
    }

    private fun handleStreamingMeasurementData(gatt: BluetoothGatt, chunk: ByteArray) {
        synchronized(measurementLock) {
            if (gatt !== bluetoothGatt || dataMode != DataMode.Measurement) return
            val expected = expectedStreamingBytes ?: return
            val received = measurementBuffer.size() + chunk.size
            if (received > expected) {
                failMeasurement(IllegalStateException("Unexpected sweep length: $received/$expected bytes"))
                return
            }

            measurementBuffer.write(chunk)
            lastDataReceivedTime = SystemClock.elapsedRealtime()
            updateLiveSweep(expected)
            if (received == expected) {
                val result = compileStreamingMeasurement(expected)
                val pending = clearMeasurement()
                _connectionState.value = ConnectionState.Connected
                pending?.resume(result)
            }
        }
    }

    private fun updateLiveSweep(expectedBytes: Int) {
        val bytes = measurementBuffer.toByteArray()
        _liveSweepProgress.value = (bytes.size.toDouble() / expectedBytes).coerceIn(0.0, 1.0)
        val count = bytes.size / BYTES_PER_MEASUREMENT_POINT
        if (count == 0 || expectedMeasurementPoints <= 0) return
        val buffer = ByteBuffer.wrap(bytes, 0, count * BYTES_PER_MEASUREMENT_POINT).order(ByteOrder.LITTLE_ENDIAN)
        val byIndex = arrayOfNulls<MeasurementPoint>(expectedMeasurementPoints)
        for (i in 0 until count) {
            val point = MeasurementPoint(frequency = buffer.float, magnitude = buffer.float, phase = buffer.float)
            byIndex[i % expectedMeasurementPoints] = point
        }
        _liveSweepPoints.value = byIndex.filterNotNull()
            .filter { it.frequency.isFinite() && it.magnitude.isFinite() && it.phase.isFinite() }
            .sortedBy { it.frequency }
    }

    private fun compileStreamingMeasurement(expectedBytes: Int): ImpedanceData {
        val buffer = ByteBuffer.wrap(measurementBuffer.read(expectedBytes)).order(ByteOrder.LITTLE_ENDIAN)
        val points = List(expectedBytes / BYTES_PER_MEASUREMENT_POINT) {
            MeasurementPoint(frequency = buffer.float, magnitude = buffer.float, phase = buffer.float)
        }
        return ImpedanceData(
            repetitions = points.chunked(expectedMeasurementPoints) { repetition ->
                repetition.sortedBy { it.frequency }
            },
            timestamp = Clock.System.now(),
            deviceInfo = currentDeviceInfo
        )
    }

    @SuppressLint("MissingPermission")
    private fun updateBatteryLevel(data: BatteryData) {
        Log.d(TAG, "Battery: ${data.voltageMillivolts}mV (${data.percentage}%)")
        _currentBatteryLevel.value = data
        val info = currentDeviceInfo ?: DeviceInfo(name = bluetoothGatt?.device?.name.orEmpty())
        currentDeviceInfo = info.copy(batteryLevel = data)
    }

    @SuppressLint("MissingPermission")
    private fun updateQuaternion(quaternion: QuaternionData) {
        val info = currentDeviceInfo ?: DeviceInfo(name = bluetoothGatt?.device?.name.orEmpty())
        currentDeviceInfo = info.copy(quaternion = quaternion)
    }

    @SuppressLint("MissingPermission")
    private fun updateQuaternionVariance(quaternion: QuaternionData) {
        val info = currentDeviceInfo ?: DeviceInfo(name = bluetoothGatt?.device?.name.orEmpty())
        currentDeviceInfo = info.copy(quaternionVariance = quaternion)
    }

    @SuppressLint("MissingPermission")
    private suspend fun readSerialNumber() {
        try {
            val data = readCharacteristic(BioMessBleUuids.SERIAL_NUMBER)
            val serial = data.toString(Charsets.UTF_8).trim()
            val device = bluetoothGatt?.device
            currentDeviceInfo = DeviceInfo(name = device?.name.orEmpty(), serialNumber = serial)
            Log.i(TAG, "Serial number: '$serial' (device: ${device?.name})")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read serial number: ${e.message}")
        }
    }
}
