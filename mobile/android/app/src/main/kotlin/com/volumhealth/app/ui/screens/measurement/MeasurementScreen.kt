package com.volumhealth.app.ui.screens.measurement

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Battery0Bar
import androidx.compose.material.icons.filled.Battery2Bar
import androidx.compose.material.icons.filled.Battery4Bar
import androidx.compose.material.icons.filled.Battery6Bar
import androidx.compose.material.icons.filled.BatteryFull
import androidx.compose.material.icons.filled.Bluetooth
import androidx.compose.material.icons.filled.BluetoothConnected
import androidx.compose.material.icons.filled.BluetoothDisabled
import androidx.compose.material.icons.filled.BluetoothSearching
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.volumhealth.app.R
import com.volumhealth.app.study.Study
import com.volumhealth.app.ui.components.BluetoothPermissionHandler
import com.volumhealth.app.ui.components.BorgScalePicker
import com.volumhealth.app.ui.theme.VolumColors
import com.volumhealth.core.ble.ConnectionState
import com.volumhealth.core.model.BatteryData
import com.volumhealth.core.model.BodySide
import com.volumhealth.core.model.Gender
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.MuscleGroup
import kotlinx.coroutines.delay
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeasurementScreen(
    viewModel: MeasurementViewModel = hiltViewModel(),
    sessionId: String = "",
    laboratoryMode: Boolean = false,
    onConfigure: () -> Unit = {},
    onNavigateBack: () -> Unit = {},
    onMeasurementComplete: () -> Unit = {},
    onNavigateToHistory: () -> Unit = {}
) {
    LaunchedEffect(sessionId) {
        if (sessionId.isNotEmpty()) {
            viewModel.setSessionContext(sessionId)
        }
    }

    DisposableEffect(sessionId) {
        onDispose {
            viewModel.cleanupIfEmpty(sessionId)
        }
    }

    val hasSessionContext = sessionId.isNotEmpty()

    val viewState by viewModel.viewState.collectAsStateWithLifecycle()
    val patientForm by viewModel.patientForm.collectAsStateWithLifecycle()
    val battery by viewModel.battery.collectAsStateWithLifecycle()
    val discoveredDevices by viewModel.discoveredDevices.collectAsStateWithLifecycle()
    val connectionState by viewModel.connectionState.collectAsStateWithLifecycle()
    val isDeviceReady by viewModel.isDeviceReady.collectAsStateWithLifecycle()
    val athleteName by viewModel.athleteName.collectAsStateWithLifecycle()

    val bluetoothEnableLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) {
        viewModel.retryAfterPermissions()
    }

    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text(if (laboratoryMode) stringResource(R.string.nav_laboratory) else athleteName.ifEmpty { stringResource(R.string.measurement_screen_title) }) },
                actions = {
                    if (laboratoryMode && viewState !is MeasurementViewState.Measuring) {
                        androidx.compose.material3.TextButton(onClick = onConfigure) {
                            Text(stringResource(R.string.lab_configure))
                        }
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = null)
                    }
                },
                scrollBehavior = scrollBehavior
            )
        }
    ) { padding ->
    Box(modifier = Modifier.fillMaxSize().padding(padding)) {
        when (val state = viewState) {
            is MeasurementViewState.Disconnected -> {
                DisconnectedView(
                    onScanForDevices = viewModel::startScan
                )
            }

            is MeasurementViewState.PermissionsRequired -> {
                BluetoothPermissionHandler(
                    onPermissionsGranted = viewModel::retryAfterPermissions,
                    onBluetoothEnableRequest = {
                        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                        bluetoothEnableLauncher.launch(intent)
                    },
                    modifier = Modifier.padding(16.dp)
                )
            }

            is MeasurementViewState.BluetoothDisabled -> {
                BluetoothDisabledView(
                    onEnableBluetooth = {
                        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                        bluetoothEnableLauncher.launch(intent)
                    }
                )
            }

            is MeasurementViewState.DeviceSelection -> {
                DeviceSelectionView(
                    devices = discoveredDevices,
                    connectionState = connectionState,
                    onDeviceSelected = viewModel::connectToDevice,
                    onCancel = viewModel::stopScan
                )
            }

            is MeasurementViewState.Connected -> {
                val activeStudy by viewModel.activeStudy.collectAsStateWithLifecycle()
                val selectedMuscle by viewModel.selectedMuscleGroup.collectAsStateWithLifecycle()
                val selectedSide by viewModel.selectedSide.collectAsStateWithLifecycle()

                ConnectedView(
                    battery = battery,
                    patientForm = patientForm,
                    hasSessionContext = hasSessionContext,
                    laboratoryMode = laboratoryMode,
                    isDeviceReady = isDeviceReady,
                    activeStudy = if (laboratoryMode) null else activeStudy,
                    selectedMuscle = selectedMuscle,
                    selectedSide = selectedSide,
                    onPatientFormChange = viewModel::updatePatientForm,
                    onStartMeasurement = viewModel::startMeasurement,
                    onOpenSync = viewModel::syncStoredMeasurements,
                    onDisconnect = viewModel::disconnect,
                    onSelectMuscle = viewModel::selectMuscleGroup,
                    onSelectSide = viewModel::selectSide
                )
            }

            is MeasurementViewState.Measuring -> {
                MeasuringView(onCancel = viewModel::cancelMeasurement)
            }

            is MeasurementViewState.AwaitingFatigueRating -> {
                FatigueRatingView(
                    onConfirm = viewModel::confirmFatigue
                )
            }

            is MeasurementViewState.Results -> {
                ResultsView(
                    data = state.data,
                    onTakeAnother = viewModel::resetToConnected,
                    onMeasurementComplete = if (laboratoryMode) onNavigateToHistory else onMeasurementComplete,
                    onViewHistory = onNavigateToHistory
                )
            }

            is MeasurementViewState.Error -> {
                val errorText = when (val error = state.errorMessage) {
                    is ErrorMessage.Text -> error.message
                    is ErrorMessage.Resource -> stringResource(error.resId)
                }
                ErrorView(
                    message = errorText,
                    onRetry = viewModel::startScan,
                    onDismiss = viewModel::disconnect
                )
            }
        }
    }
    }
}

@Composable
private fun DisconnectedView(
    onScanForDevices: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.Bolt,
            contentDescription = null,
            modifier = Modifier.size(80.dp),
            tint = VolumColors.SystemBlue
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = stringResource(R.string.ready_to_measure),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = stringResource(R.string.connect_to_device_description),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(32.dp))

        Button(
            onClick = onScanForDevices,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(containerColor = VolumColors.SystemBlue)
        ) {
            Icon(
                imageVector = Icons.Default.BluetoothSearching,
                contentDescription = null,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.size(8.dp))
            Text(
                text = stringResource(R.string.scan_for_devices),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(vertical = 8.dp)
            )
        }
    }
}

@Composable
private fun BluetoothDisabledView(
    onEnableBluetooth: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.BluetoothDisabled,
            contentDescription = null,
            modifier = Modifier.size(80.dp),
            tint = VolumColors.SystemRed
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = stringResource(R.string.bluetooth_disabled),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = stringResource(R.string.bluetooth_disabled_description),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(32.dp))

        Button(
            onClick = onEnableBluetooth,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        ) {
            Icon(
                imageVector = Icons.Default.Bluetooth,
                contentDescription = null,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.size(8.dp))
            Text(stringResource(R.string.enable_bluetooth))
        }
    }
}

@SuppressLint("MissingPermission")
@Composable
private fun DeviceSelectionView(
    devices: List<BluetoothDevice>,
    connectionState: ConnectionState,
    onDeviceSelected: (BluetoothDevice) -> Unit,
    onCancel: () -> Unit
) {
    val isConnecting = connectionState is ConnectionState.Connecting

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (connectionState is ConnectionState.Scanning) {
                CircularProgressIndicator(
                    modifier = Modifier.size(48.dp),
                    color = VolumColors.SystemBlue
                )
            } else if (isConnecting) {
                CircularProgressIndicator(
                    modifier = Modifier.size(48.dp),
                    color = VolumColors.SystemGreen
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = if (isConnecting) stringResource(R.string.connecting) else stringResource(R.string.available_devices),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )

            Text(
                text = if (isConnecting) stringResource(R.string.please_wait) else stringResource(R.string.select_device_description),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        // Device list
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (devices.isEmpty() && connectionState is ConnectionState.Scanning) {
                Text(
                    text = stringResource(R.string.searching_devices),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(16.dp)
                )
                EmptyScanHelp()
            }

            devices.forEach { device ->
                DeviceCard(
                    device = device,
                    onConnect = { onDeviceSelected(device) },
                    isEnabled = !isConnecting
                )
            }
        }

        // Cancel button
        TextButton(
            onClick = onCancel,
            modifier = Modifier.align(Alignment.CenterHorizontally)
        ) {
            Text(stringResource(R.string.cancel))
        }
    }
}

@SuppressLint("MissingPermission")
@Composable
private fun DeviceCard(
    device: BluetoothDevice,
    onConnect: () -> Unit,
    isEnabled: Boolean
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        tonalElevation = 2.dp
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = device.name ?: stringResource(R.string.unknown_device),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = device.address,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Button(
                onClick = onConnect,
                enabled = isEnabled,
                shape = RoundedCornerShape(8.dp)
            ) {
                Text(stringResource(R.string.connect))
            }
        }
    }
}

/**
 * Diagnostic helper shown after ~5 s of empty scanning. The most common cause
 * of "no devices found" on Android ≤ 11 is that the user granted the location
 * permission but the system Location toggle is OFF — Android then makes BLE
 * scan return an empty list silently. On Android 12+ the typical cause is
 * the BLUETOOTH_SCAN permission being denied or the device just not being
 * powered / advertising.
 */
@Composable
private fun EmptyScanHelp() {
    var visible by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(5_000)
        visible = true
    }
    if (!visible) return

    val context = LocalContext.current
    val isOldAndroid = Build.VERSION.SDK_INT < Build.VERSION_CODES.S
    val isLocationOn = remember(isOldAndroid) {
        if (!isOldAndroid) true
        else {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true ||
                lm?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true
        }
    }

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.45f)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Warning,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onErrorContainer
                )
                Text(
                    text = stringResource(R.string.scan_empty_title),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onErrorContainer
                )
            }
            Text(
                text = if (isOldAndroid)
                    stringResource(R.string.scan_empty_old_android)
                else
                    stringResource(R.string.scan_empty_new_android),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onErrorContainer
            )
            if (isOldAndroid && !isLocationOn) {
                Button(
                    onClick = {
                        runCatching {
                            context.startActivity(
                                Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Text(stringResource(R.string.scan_empty_open_location))
                }
            }
            OutlinedButton(
                onClick = {
                    runCatching {
                        context.startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(Uri.fromParts("package", context.packageName, null))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp)
            ) {
                Text(stringResource(R.string.scan_empty_open_app_settings))
            }
        }
    }
}

@Composable
private fun ConnectedView(
    battery: BatteryData?,
    patientForm: PatientFormData,
    hasSessionContext: Boolean = false,
    laboratoryMode: Boolean = false,
    isDeviceReady: Boolean = true,
    activeStudy: Study?,
    selectedMuscle: MuscleGroup?,
    selectedSide: BodySide?,
    onPatientFormChange: (PatientFormData) -> Unit,
    onStartMeasurement: () -> Unit,
    onOpenSync: () -> Unit,
    @Suppress("UNUSED_PARAMETER") onDisconnect: () -> Unit,
    onSelectMuscle: (MuscleGroup) -> Unit,
    onSelectSide: (BodySide) -> Unit
) {
    // Auto-start when the protocol leaves the operator nothing to choose
    // (1 muscle × 1 side, e.g. BICEPS_TFG): the previous screen already picked
    // the session_type and tapped "Medir"; making the user tap again here on a
    // page that only shows instructions is friction. Sentadilla TFM still needs
    // this view because the pickers go here.
    val isSingleTarget =
        activeStudy != null &&
        activeStudy.muscleGroups.size == 1 &&
        activeStudy.sides.size == 1
    var didAutoStart by remember { mutableStateOf(false) }
    LaunchedEffect(isSingleTarget, hasSessionContext, isDeviceReady) {
        if (
            !didAutoStart &&
            isSingleTarget &&
            hasSessionContext &&
            isDeviceReady
        ) {
            didAutoStart = true
            onStartMeasurement()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        BatteryPill(battery = battery)

        // Muscle picker — only when the study declares >1 option
        if ((activeStudy?.muscleGroups?.size ?: 0) > 1) {
            SegmentedPicker(
                label = stringResource(R.string.measurement_pick_muscle),
                options = activeStudy!!.muscleGroups.map { it to it.displayName },
                selected = selectedMuscle,
                onSelect = onSelectMuscle
            )
        }

        // Side picker — only when the study declares >1 option
        if ((activeStudy?.sides?.size ?: 0) > 1) {
            SegmentedPicker(
                label = stringResource(R.string.measurement_pick_side),
                options = activeStudy!!.sides.map { side ->
                    side to when (side) {
                        BodySide.RIGHT -> stringResource(R.string.measurement_side_right)
                        BodySide.LEFT -> stringResource(R.string.measurement_side_left)
                    }
                },
                selected = selectedSide,
                onSelect = onSelectSide
            )
        }

        if (!isDeviceReady) {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                color = VolumColors.SystemOrange.copy(alpha = 0.12f)
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = VolumColors.SystemOrange
                    )
                    Text(
                        text = stringResource(R.string.device_preparing),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                        color = VolumColors.SystemOrange
                    )
                }
            }
        }

        if (laboratoryMode) {
            Text(stringResource(R.string.lab_description), style = MaterialTheme.typography.bodyMedium)
        }
        if (!hasSessionContext && !laboratoryMode) {
            PatientFormCard(
                form = patientForm,
                onFormChange = onPatientFormChange
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        if (!laboratoryMode) InstructionsCard()

        Spacer(modifier = Modifier.weight(1f))

        val canStart = isDeviceReady && (laboratoryMode || hasSessionContext || patientForm.isValid)
        Button(
            onClick = onStartMeasurement,
            modifier = Modifier
                .fillMaxWidth()
                .height(72.dp),
            enabled = canStart,
            shape = RoundedCornerShape(24.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.primary,
                disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant
            ),
            elevation = ButtonDefaults.buttonElevation(
                defaultElevation = 6.dp,
                pressedElevation = 2.dp,
                disabledElevation = 0.dp
            )
        ) {
            Icon(
                imageVector = Icons.Default.PlayArrow,
                contentDescription = null,
                modifier = Modifier.size(28.dp)
            )
            Spacer(modifier = Modifier.size(12.dp))
            Text(
                text = if (isDeviceReady) stringResource(R.string.start_measurement) else stringResource(R.string.device_waiting),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
        }

        TextButton(
            onClick = onOpenSync,
            modifier = Modifier.align(Alignment.CenterHorizontally)
        ) {
            Text(stringResource(R.string.stored_data))
        }

        Spacer(modifier = Modifier.height(4.dp))
    }
}

@Composable
private fun <T> SegmentedPicker(
    label: String,
    options: List<Pair<T, String>>,
    selected: T?,
    onSelect: (T) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            options.forEach { (value, displayLabel) ->
                FilterChip(
                    selected = selected == value,
                    onClick = { onSelect(value) },
                    label = { Text(displayLabel) },
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun BatteryPill(battery: BatteryData?) {
    if (battery == null) {
        Spacer(modifier = Modifier.height(0.dp))
        return
    }
    val pct = battery.percentage.toInt()
    val icon = when {
        pct >= 90 -> Icons.Default.BatteryFull
        pct >= 60 -> Icons.Default.Battery6Bar
        pct >= 40 -> Icons.Default.Battery4Bar
        pct >= 20 -> Icons.Default.Battery2Bar
        else -> Icons.Default.Battery0Bar
    }
    val tint = if (pct < 20) VolumColors.SystemOrange else MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            shape = RoundedCornerShape(50),
            color = MaterialTheme.colorScheme.surfaceContainerLow
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(16.dp))
                Text(
                    text = "$pct%",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = tint
                )
            }
        }
    }
}

@Composable
private fun DeviceInfoCard(battery: BatteryData?) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = VolumColors.SystemGreen.copy(alpha = 0.1f)
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = null,
                    tint = VolumColors.SystemGreen,
                    modifier = Modifier.size(24.dp)
                )
                Column {
                    Text(
                        text = stringResource(R.string.connected),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = VolumColors.SystemGreen
                    )
                    Text(
                        text = stringResource(R.string.biomess_device),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            // Battery indicator
            battery?.let { bat ->
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    val batteryIcon = when {
                        bat.percentage >= 90u -> Icons.Default.BatteryFull
                        bat.percentage >= 60u -> Icons.Default.Battery6Bar
                        bat.percentage >= 40u -> Icons.Default.Battery4Bar
                        bat.percentage >= 20u -> Icons.Default.Battery2Bar
                        else -> Icons.Default.Battery0Bar
                    }
                    val batteryColor = when {
                        bat.percentage >= 50u -> VolumColors.SystemGreen
                        bat.percentage >= 20u -> VolumColors.SystemOrange
                        else -> VolumColors.SystemRed
                    }

                    Icon(
                        imageVector = batteryIcon,
                        contentDescription = null,
                        tint = batteryColor,
                        modifier = Modifier.size(20.dp)
                    )
                    Text(
                        text = "${bat.percentage}%",
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = batteryColor
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PatientFormCard(
    form: PatientFormData,
    onFormChange: (PatientFormData) -> Unit
) {
    var genderExpanded by remember { mutableStateOf(false) }

    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        tonalElevation = 1.dp
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.patient_information),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )

            OutlinedTextField(
                value = form.name,
                onValueChange = { onFormChange(form.copy(name = it)) },
                label = { Text(stringResource(R.string.patient_name_label)) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            OutlinedTextField(
                value = form.exerciseName,
                onValueChange = { onFormChange(form.copy(exerciseName = it)) },
                label = { Text(stringResource(R.string.exercise_name_label)) },
                placeholder = { Text(stringResource(R.string.exercise_placeholder)) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedTextField(
                    value = form.age,
                    onValueChange = { onFormChange(form.copy(age = it)) },
                    label = { Text(stringResource(R.string.age_label)) },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )

                ExposedDropdownMenuBox(
                    expanded = genderExpanded,
                    onExpandedChange = { genderExpanded = it },
                    modifier = Modifier.weight(1f)
                ) {
                    OutlinedTextField(
                        value = when (form.gender) {
                            Gender.MALE -> stringResource(R.string.gender_male)
                            Gender.FEMALE -> stringResource(R.string.gender_female)
                            Gender.OTHER -> stringResource(R.string.gender_other)
                        },
                        onValueChange = {},
                        readOnly = true,
                        label = { Text(stringResource(R.string.gender_label)) },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = genderExpanded) },
                        modifier = Modifier.menuAnchor()
                    )
                    ExposedDropdownMenu(
                        expanded = genderExpanded,
                        onDismissRequest = { genderExpanded = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.gender_male)) },
                            onClick = {
                                onFormChange(form.copy(gender = Gender.MALE))
                                genderExpanded = false
                            }
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.gender_female)) },
                            onClick = {
                                onFormChange(form.copy(gender = Gender.FEMALE))
                                genderExpanded = false
                            }
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.gender_other)) },
                            onClick = {
                                onFormChange(form.copy(gender = Gender.OTHER))
                                genderExpanded = false
                            }
                        )
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedTextField(
                    value = form.height,
                    onValueChange = { onFormChange(form.copy(height = it)) },
                    label = { Text(stringResource(R.string.height_label)) },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )

                OutlinedTextField(
                    value = form.weight,
                    onValueChange = { onFormChange(form.copy(weight = it)) },
                    label = { Text(stringResource(R.string.weight_label)) },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )
            }

            // BMI display
            form.bmi?.let { bmi ->
                val bmiCategory = stringResource(form.bmiCategoryResId)
                Text(
                    text = stringResource(R.string.bmi_format, bmi, bmiCategory),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // Validation status
            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = if (form.isValid) Icons.Default.CheckCircle else Icons.Default.Warning,
                    contentDescription = null,
                    tint = if (form.isValid) VolumColors.SystemGreen else VolumColors.SystemOrange,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = if (form.isValid) stringResource(R.string.patient_data_complete) else stringResource(R.string.please_complete_fields),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (form.isValid) VolumColors.SystemGreen else VolumColors.SystemOrange
                )
            }
        }
    }
}

@Composable
private fun InstructionsCard() {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        tonalElevation = 0.dp
    ) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.measurement_instructions),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )

            listOf(
                "1" to stringResource(R.string.instruction_1),
                "2" to stringResource(R.string.instruction_2),
                "3" to stringResource(R.string.instruction_3),
                "4" to stringResource(R.string.instruction_4)
            ).forEach { (number, text) ->
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Surface(
                        shape = RoundedCornerShape(50),
                        color = VolumColors.SystemBlue
                    ) {
                        Text(
                            text = number,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                    }
                    Text(
                        text = text,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        }
    }
}

@Composable
private fun MeasuringView(
    onCancel: () -> Unit = {}
) {
    var progress by remember { mutableFloatStateOf(0f) }
    var phaseIndex by remember { mutableIntStateOf(0) }
    var phasesComplete by remember { mutableStateOf(false) }

    val phaseInitializing = stringResource(R.string.phase_initializing)
    val phaseStarting = stringResource(R.string.phase_starting)
    val phaseCollecting = stringResource(R.string.phase_collecting)
    val phaseProcessing = stringResource(R.string.phase_processing)

    val phases = remember {
        listOf(
            0.0f to 0,
            0.3f to 1,
            0.7f to 2,
            1.0f to 3
        )
    }

    val phaseText = if (phasesComplete) {
        "Esperando datos..."
    } else {
        when (phaseIndex) {
            0 -> phaseStarting
            1 -> phaseCollecting
            2 -> phaseProcessing
            3 -> phaseProcessing
            else -> phaseInitializing
        }
    }

    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.6f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(500, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulse"
    )

    LaunchedEffect(Unit) {
        for ((targetProgress, index) in phases) {
            phaseIndex = index
            while (progress < targetProgress) {
                progress += 0.02f
                delay(50)
            }
        }
        phasesComplete = true
    }

    val haloScale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.4f,
        animationSpec = infiniteRepeatable(
            animation = tween(900, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "halo"
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier.size(180.dp),
            contentAlignment = Alignment.Center
        ) {
            // Outer pulsing halo
            Box(
                modifier = Modifier
                    .size(180.dp)
                    .scale(haloScale)
                    .clip(androidx.compose.foundation.shape.CircleShape)
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.10f))
            )
            // Inner solid disc
            Box(
                modifier = Modifier
                    .size(120.dp)
                    .clip(androidx.compose.foundation.shape.CircleShape)
                    .background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Bolt,
                    contentDescription = null,
                    modifier = Modifier.size(56.dp),
                    tint = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = pulseAlpha)
                )
            }
        }

        Spacer(modifier = Modifier.height(40.dp))

        Text(
            text = stringResource(R.string.measuring_bioimpedance),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(6.dp))

        Text(
            text = phaseText,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(28.dp))

        if (phasesComplete) {
            LinearProgressIndicator(
                modifier = Modifier
                    .fillMaxWidth(0.7f)
                    .height(6.dp)
                    .clip(RoundedCornerShape(3.dp)),
                color = MaterialTheme.colorScheme.primary,
                trackColor = MaterialTheme.colorScheme.surfaceContainerLow
            )
        } else {
            LinearProgressIndicator(
                progress = progress.coerceIn(0f, 1f),
                modifier = Modifier
                    .fillMaxWidth(0.7f)
                    .height(6.dp)
                    .clip(RoundedCornerShape(3.dp)),
                color = MaterialTheme.colorScheme.primary,
                trackColor = MaterialTheme.colorScheme.surfaceContainerLow
            )
        }

        Spacer(modifier = Modifier.height(28.dp))

        Surface(
            shape = RoundedCornerShape(50),
            color = MaterialTheme.colorScheme.surfaceContainerLow
        ) {
            Text(
                text = stringResource(R.string.please_remain_still),
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.Medium
            )
        }

        Spacer(modifier = Modifier.height(40.dp))

        TextButton(onClick = onCancel) {
            Text(stringResource(R.string.cancel))
        }
    }
}

@Composable
private fun FatigueRatingView(onConfirm: (Int) -> Unit) {
    var selected by remember { mutableStateOf<Int?>(null) }
    BorgScalePicker(
        selected = selected,
        onSelected = { selected = it },
        onConfirm = { selected?.let(onConfirm) },
        title = stringResource(R.string.borg_question),
        confirmLabel = stringResource(R.string.borg_continue)
    )
}

@Composable
private fun ResultsView(
    data: ImpedanceData,
    onTakeAnother: () -> Unit,
    onMeasurementComplete: () -> Unit,
    onViewHistory: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Success header
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = VolumColors.SystemGreen
            )

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = stringResource(R.string.measurement_captured),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
        }

        // Raw data info
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            color = VolumColors.SystemGreen.copy(alpha = 0.1f)
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.Check,
                        contentDescription = null,
                        tint = VolumColors.SystemGreen,
                        modifier = Modifier.size(20.dp)
                    )
                    Text(
                        text = stringResource(R.string.raw_data_captured),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }

                val measurements = data.measurements
                DataRow(stringResource(R.string.data_points), measurements.size.toString())
                DataRow(stringResource(R.string.frequency_range), "%.0f - %.0f Hz".format(
                    Locale.getDefault(),
                    measurements.minOfOrNull { it.frequency } ?: 0f,
                    measurements.maxOfOrNull { it.frequency } ?: 0f
                ))
                DataRow(stringResource(R.string.impedance_range), "%.1f - %.1f Ω".format(
                    Locale.getDefault(),
                    measurements.minOfOrNull { it.magnitude } ?: 0f,
                    measurements.maxOfOrNull { it.magnitude } ?: 0f
                ))
            }
        }

        // Actions
        Button(
            onClick = onMeasurementComplete,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(containerColor = VolumColors.SystemGreen)
        ) {
            Icon(
                imageVector = Icons.Default.Check,
                contentDescription = null,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.size(8.dp))
            Text(
                text = stringResource(R.string.done),
                modifier = Modifier.padding(vertical = 4.dp)
            )
        }

        OutlinedButton(
            onClick = onTakeAnother,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        ) {
            Text(stringResource(R.string.take_another_measurement))
        }

        OutlinedButton(
            onClick = onViewHistory,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        ) {
            Text(stringResource(R.string.view_history))
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}

@Composable
private fun DataRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium
        )
    }
}

@Composable
private fun ErrorView(
    message: String,
    onRetry: () -> Unit,
    onDismiss: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.Error,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = VolumColors.SystemRed
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = stringResource(R.string.connection_error),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = message,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(32.dp))

        Button(
            onClick = onRetry,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        ) {
            Icon(
                imageVector = Icons.Default.Refresh,
                contentDescription = null,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.size(8.dp))
            Text(stringResource(R.string.try_again))
        }

        Spacer(modifier = Modifier.height(8.dp))

        TextButton(onClick = onDismiss) {
            Text(stringResource(R.string.back_to_main_menu))
        }
    }
}
