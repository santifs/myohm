package com.volumhealth.app.ui.screens.settings

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowRight
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
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.volumhealth.app.R
import com.volumhealth.app.locale.AppLanguage
import com.volumhealth.app.study.Study
import com.volumhealth.app.ui.components.SyncStatusBar
import com.volumhealth.app.ui.theme.VolumColors
import com.volumhealth.core.ble.ConnectionState
import com.volumhealth.core.model.BatteryData

@OptIn(ExperimentalMaterial3Api::class)
@SuppressLint("MissingPermission")
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel(),
    onNavigateToFrequencyConfig: () -> Unit = {}
) {
    val connectionState by viewModel.connectionState.collectAsStateWithLifecycle()
    val battery by viewModel.battery.collectAsStateWithLifecycle()
    val devices by viewModel.devices.collectAsStateWithLifecycle()
    val currentLanguage by viewModel.currentLanguage.collectAsStateWithLifecycle()
    val activeStudy by viewModel.activeStudy.collectAsStateWithLifecycle()

    // Sync state
    val isSyncing by viewModel.isSyncing.collectAsState()
    val pendingCount by viewModel.pendingCount.collectAsState()
    val lastSyncError by viewModel.lastSyncError.collectAsState()

    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text(stringResource(R.string.nav_settings)) },
                scrollBehavior = scrollBehavior
            )
        }
    ) { padding ->
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.myohm_local_storage), modifier = Modifier.padding(16.dp))
            }
        }

        // Device Connection Section
        item {
            Spacer(modifier = Modifier.height(8.dp))
            SectionHeader(title = stringResource(R.string.device_connection))
        }

        item {
            DeviceStatusCard(
                connectionState = connectionState,
                battery = battery,
                onConnect = viewModel::startScan,
                onDisconnect = viewModel::disconnect
            )
        }

        // Available Devices (when scanning)
        if (connectionState is ConnectionState.Scanning || devices.isNotEmpty()) {
            item {
                AvailableDevicesSection(
                    devices = devices,
                    isScanning = connectionState is ConnectionState.Scanning,
                    onDeviceSelected = viewModel::connect,
                    onStopScan = viewModel::stopScan
                )
            }
        }

        // Measurement configuration
        item {
            Spacer(modifier = Modifier.height(8.dp))
            SectionHeader(title = stringResource(R.string.settings_measurement_section))
        }

        item {
            SettingsMenuCard {
                SettingsMenuItem(
                    icon = Icons.Default.Speed,
                    title = stringResource(R.string.settings_frequency_sweep),
                    subtitle = stringResource(R.string.settings_frequency_sweep_subtitle),
                    showArrow = true,
                    onClick = onNavigateToFrequencyConfig
                )
            }
        }

        // Active Study Section
        item {
            Spacer(modifier = Modifier.height(8.dp))
            SectionHeader(title = stringResource(R.string.settings_active_study))
        }

        item {
            StudySelectorCard(
                activeStudy = activeStudy,
                onStudySelected = viewModel::selectStudy
            )
        }

        // Language Section
        item {
            Spacer(modifier = Modifier.height(8.dp))
            SectionHeader(title = stringResource(R.string.language))
        }

        item {
            LanguageSelectorCard(
                currentLanguage = currentLanguage,
                onLanguageSelected = viewModel::setLanguage
            )
        }

        // About Section
        item {
            Spacer(modifier = Modifier.height(8.dp))
            SectionHeader(title = stringResource(R.string.about))
        }

        item {
            SettingsMenuCard {
                SettingsMenuItem(
                    icon = Icons.Default.Info,
                    title = stringResource(R.string.app_name),
                    subtitle = stringResource(R.string.version_format, "0.1.0"),
                    showArrow = false,
                    onClick = {}
                )
            }
        }

        item {
            Spacer(modifier = Modifier.height(32.dp))
        }
    }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(vertical = 4.dp)
    )
}

@SuppressLint("MissingPermission")
@Composable
private fun DeviceStatusCard(
    connectionState: ConnectionState,
    battery: BatteryData?,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit
) {
    val isConnected = connectionState is ConnectionState.Connected
    val isConnecting = connectionState is ConnectionState.Connecting
    val isScanning = connectionState is ConnectionState.Scanning

    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = when {
            isConnected -> VolumColors.SystemGreen.copy(alpha = 0.1f)
            isConnecting || isScanning -> VolumColors.SystemBlue.copy(alpha = 0.1f)
            else -> MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        }
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    val (icon, color) = when {
                        isConnected -> Icons.Default.BluetoothConnected to VolumColors.SystemGreen
                        isConnecting || isScanning -> Icons.Default.BluetoothSearching to VolumColors.SystemBlue
                        else -> Icons.Default.BluetoothDisabled to MaterialTheme.colorScheme.onSurfaceVariant
                    }

                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = color,
                        modifier = Modifier.size(32.dp)
                    )

                    Column {
                        Text(
                            text = when {
                                isConnected -> stringResource(R.string.connected)
                                isConnecting -> stringResource(R.string.connecting)
                                isScanning -> stringResource(R.string.scanning)
                                else -> stringResource(R.string.not_connected)
                            },
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = when {
                                isConnected -> stringResource(R.string.biomess_device)
                                isConnecting -> stringResource(R.string.please_wait)
                                isScanning -> stringResource(R.string.searching_for_devices)
                                else -> stringResource(R.string.tap_to_connect)
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                // Battery indicator for connected state
                if (isConnected && battery != null) {
                    BatteryIndicator(battery = battery)
                }

                if (isConnecting || isScanning) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        strokeWidth = 2.dp,
                        color = VolumColors.SystemBlue
                    )
                }
            }

            // Action buttons
            if (isConnected) {
                OutlinedButton(
                    onClick = onDisconnect,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.BluetoothDisabled,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.size(8.dp))
                    Text(stringResource(R.string.disconnect))
                }
            } else if (!isScanning && !isConnecting) {
                Button(
                    onClick = onConnect,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = VolumColors.SystemBlue
                    )
                ) {
                    Icon(
                        imageVector = Icons.Default.Bluetooth,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.size(8.dp))
                    Text(stringResource(R.string.scan_for_devices))
                }
            }
        }
    }
}

@Composable
private fun BatteryIndicator(battery: BatteryData) {
    val batteryIcon = when {
        battery.percentage >= 90u -> Icons.Default.BatteryFull
        battery.percentage >= 60u -> Icons.Default.Battery6Bar
        battery.percentage >= 40u -> Icons.Default.Battery4Bar
        battery.percentage >= 20u -> Icons.Default.Battery2Bar
        else -> Icons.Default.Battery0Bar
    }
    val batteryColor = when {
        battery.percentage >= 50u -> VolumColors.SystemGreen
        battery.percentage >= 20u -> VolumColors.SystemOrange
        else -> VolumColors.SystemRed
    }

    Surface(
        shape = RoundedCornerShape(8.dp),
        color = batteryColor.copy(alpha = 0.1f)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = batteryIcon,
                contentDescription = null,
                tint = batteryColor,
                modifier = Modifier.size(18.dp)
            )
            Text(
                text = "${battery.percentage}%",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = batteryColor
            )
        }
    }
}

@SuppressLint("MissingPermission")
@Composable
private fun AvailableDevicesSection(
    devices: List<BluetoothDevice>,
    isScanning: Boolean,
    onDeviceSelected: (BluetoothDevice) -> Unit,
    onStopScan: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        tonalElevation = 1.dp
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.available_devices),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )

                if (isScanning) {
                    TextButton(onClick = onStopScan) {
                        Text(stringResource(R.string.stop), color = VolumColors.SystemRed)
                    }
                }
            }

            if (devices.isEmpty() && isScanning) {
                Text(
                    text = stringResource(R.string.searching_devices),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            devices.forEach { device ->
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onDeviceSelected(device) },
                    shape = RoundedCornerShape(12.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(
                                text = device.name ?: stringResource(R.string.unknown_device),
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.Medium
                            )
                            Text(
                                text = device.address,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Icon(
                            imageVector = Icons.Filled.KeyboardArrowRight,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SettingsMenuCard(
    content: @Composable () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        tonalElevation = 1.dp
    ) {
        Column {
            content()
        }
    }
}

@Composable
private fun SettingsMenuItem(
    icon: ImageVector,
    title: String,
    subtitle: String,
    showArrow: Boolean = true,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            shape = RoundedCornerShape(8.dp),
            color = VolumColors.SystemBlue.copy(alpha = 0.1f)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = VolumColors.SystemBlue,
                modifier = Modifier
                    .padding(8.dp)
                    .size(24.dp)
            )
        }

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        if (showArrow) {
            Icon(
                imageVector = Icons.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun LanguageSelectorCard(
    currentLanguage: AppLanguage,
    onLanguageSelected: (AppLanguage) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        tonalElevation = 1.dp
    ) {
        Column {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { expanded = true }
                    .padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Surface(
                    shape = RoundedCornerShape(8.dp),
                    color = VolumColors.SystemIndigo.copy(alpha = 0.1f)
                ) {
                    Icon(
                        imageVector = Icons.Default.Language,
                        contentDescription = null,
                        tint = VolumColors.SystemIndigo,
                        modifier = Modifier
                            .padding(8.dp)
                            .size(24.dp)
                    )
                }

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = stringResource(R.string.language),
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = when (currentLanguage) {
                            AppLanguage.ENGLISH -> stringResource(R.string.english)
                            AppLanguage.SPANISH -> stringResource(R.string.spanish)
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Icon(
                    imageVector = Icons.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false }
            ) {
                AppLanguage.entries.forEach { language ->
                    DropdownMenuItem(
                        text = {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = when (language) {
                                        AppLanguage.ENGLISH -> stringResource(R.string.english)
                                        AppLanguage.SPANISH -> stringResource(R.string.spanish)
                                    }
                                )
                                if (language == currentLanguage) {
                                    Icon(
                                        imageVector = Icons.Default.Check,
                                        contentDescription = null,
                                        tint = VolumColors.SystemGreen,
                                        modifier = Modifier.size(18.dp)
                                    )
                                }
                            }
                        },
                        onClick = {
                            onLanguageSelected(language)
                            expanded = false
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun StudySelectorCard(
    activeStudy: Study?,
    onStudySelected: (Study) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    var pendingStudy by remember { mutableStateOf<Study?>(null) }

    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        tonalElevation = 1.dp
    ) {
        Column {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { expanded = true }
                    .padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Surface(
                    shape = RoundedCornerShape(8.dp),
                    color = VolumColors.SystemIndigo.copy(alpha = 0.1f)
                ) {
                    Icon(
                        imageVector = Icons.Default.Science,
                        contentDescription = null,
                        tint = VolumColors.SystemIndigo,
                        modifier = Modifier
                            .padding(8.dp)
                            .size(24.dp)
                    )
                }

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = stringResource(R.string.settings_active_study),
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = activeStudy?.label
                            ?: stringResource(R.string.settings_active_study_none),
                        style = MaterialTheme.typography.bodySmall,
                        color = if (activeStudy == null) VolumColors.SystemRed
                                else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Icon(
                    imageVector = Icons.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false }
            ) {
                Study.entries.forEach { study ->
                    DropdownMenuItem(
                        text = {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(study.label)
                                if (study == activeStudy) {
                                    Icon(
                                        imageVector = Icons.Default.Check,
                                        contentDescription = null,
                                        tint = VolumColors.SystemGreen,
                                        modifier = Modifier.size(18.dp)
                                    )
                                }
                            }
                        },
                        onClick = {
                            expanded = false
                            if (study == activeStudy) return@DropdownMenuItem
                            if (activeStudy == null) {
                                onStudySelected(study)
                            } else {
                                pendingStudy = study
                            }
                        }
                    )
                }
            }
        }
    }

    pendingStudy?.let { target ->
        AlertDialog(
            onDismissRequest = { pendingStudy = null },
            title = { Text(stringResource(R.string.settings_change_study_title)) },
            text = {
                Text(stringResource(R.string.settings_change_study_message, target.label))
            },
            confirmButton = {
                TextButton(onClick = {
                    onStudySelected(target)
                    pendingStudy = null
                }) {
                    Text(stringResource(R.string.action_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingStudy = null }) {
                    Text(stringResource(R.string.common_cancel))
                }
            }
        )
    }
}
