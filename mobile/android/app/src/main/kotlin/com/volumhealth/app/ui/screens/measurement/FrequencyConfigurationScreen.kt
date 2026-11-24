package com.volumhealth.app.ui.screens.measurement

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.Button
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.volumhealth.app.R
import com.volumhealth.app.ui.theme.VolumColors
import com.volumhealth.core.ble.ConnectionState
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FrequencyConfigurationScreen(
    viewModel: FrequencyConfigurationViewModel = hiltViewModel(),
    onNavigateBack: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val connectionState by viewModel.connectionState.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { viewModel.refreshConfiguration() }
    LaunchedEffect(connectionState) {
        if (connectionState is ConnectionState.Connected) {
            viewModel.refreshConfiguration()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.freq_config_title)) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = stringResource(R.string.freq_config_back))
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            contentPadding = PaddingValues(bottom = 32.dp)
        ) {
            item {
                HeaderCard(connectionState = connectionState, status = uiState.statusMessage)
            }
            item {
                PresetSection(
                    selected = uiState.selectedPreset,
                    onPresetSelected = viewModel::applyPreset
                )
            }
            item {
                RepetitionCard(
                    repetitions = uiState.repetitions,
                    quality = uiState.repetitionQuality,
                    description = uiState.repetitionDescription,
                    estimatedDuration = uiState.estimatedDurationText,
                    onRepetitionsChanged = viewModel::setRepetitions
                )
            }
            item {
                FrequencyCard(
                    startFrequency = uiState.startFrequency,
                    stopFrequency = uiState.stopFrequency,
                    onStartChanged = viewModel::setStartFrequency,
                    onStopChanged = viewModel::setStopFrequency,
                    rangeSummary = uiState.rangeDescription
                )
            }
            item {
                PointsCard(
                    points = uiState.points,
                    onPointsChanged = viewModel::setPoints
                )
            }
            item {
                SummaryCard(uiState = uiState)
            }
            item {
                ApplySection(
                    isApplying = uiState.isApplying,
                    isConnected = connectionState is ConnectionState.Connected,
                    status = uiState.statusMessage,
                    onApply = viewModel::applyConfiguration
                )
            }
        }
    }
}

@Composable
private fun HeaderCard(connectionState: ConnectionState, status: String?) {
    val (title, subtitle, color) = when (connectionState) {
        ConnectionState.Connected -> Triple(stringResource(R.string.freq_config_device_connected), stringResource(R.string.freq_config_ready_to_configure), VolumColors.SystemGreen)
        ConnectionState.Connecting -> Triple(stringResource(R.string.freq_config_connecting), stringResource(R.string.freq_config_wait_pairing), VolumColors.SystemOrange)
        ConnectionState.Scanning -> Triple(stringResource(R.string.freq_config_scanning), stringResource(R.string.freq_config_searching_devices), VolumColors.BrandPrimary)
        ConnectionState.Measuring -> Triple(stringResource(R.string.freq_config_measuring), stringResource(R.string.freq_config_active_session), VolumColors.BrandPrimary)
        ConnectionState.Disconnected -> Triple(stringResource(R.string.freq_config_device_disconnected), stringResource(R.string.freq_config_connect_to_sync), VolumColors.SystemRed)
        is ConnectionState.Error -> Triple(stringResource(R.string.freq_config_error), connectionState.message, VolumColors.SystemRed)
    }

    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        tonalElevation = 2.dp
    ) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(
                    modifier = Modifier
                        .background(color.copy(alpha = 0.15f), shape = MaterialTheme.shapes.medium)
                        .padding(12.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Cloud,
                        contentDescription = null,
                        tint = color
                    )
                }
                Column {
                    Text(text = title, style = MaterialTheme.typography.titleMedium, color = color)
                    Text(text = subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            status?.let {
                Text(text = it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun PresetSection(selected: FrequencyPreset?, onPresetSelected: (FrequencyPreset) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(text = stringResource(R.string.freq_config_quick_presets), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            FrequencyPreset.entries.chunked(2).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                    row.forEach { preset ->
                        PresetCard(
                            preset = preset,
                            isSelected = preset == selected,
                            modifier = Modifier.weight(1f),
                            onClick = { onPresetSelected(preset) }
                        )
                    }
                    if (row.size == 1) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PresetCard(
    preset: FrequencyPreset,
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val colors = if (isSelected) {
        Brush.linearGradient(listOf(VolumColors.SystemIndigo, VolumColors.SystemIndigo.copy(alpha = 0.8f)))
    } else {
        Brush.linearGradient(listOf(MaterialTheme.colorScheme.surface, MaterialTheme.colorScheme.surfaceVariant))
    }
    ElevatedCard(
        modifier = modifier,
        onClick = onClick,
        colors = CardDefaults.elevatedCardColors(containerColor = Color.Transparent)
    ) {
        Column(
            modifier = Modifier
                .background(colors, shape = MaterialTheme.shapes.medium)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            horizontalAlignment = Alignment.Start
        ) {
            Icon(
                imageVector = when (preset) {
                    FrequencyPreset.FAST -> Icons.Filled.Bolt
                    FrequencyPreset.STANDARD -> Icons.Filled.CheckCircle
                    FrequencyPreset.QUALITY, FrequencyPreset.MAXIMUM -> Icons.Filled.Speed
                },
                contentDescription = null,
                tint = if (isSelected) Color.White else MaterialTheme.colorScheme.primary
            )
            Text(
                text = preset.title,
                style = MaterialTheme.typography.titleMedium,
                color = if (isSelected) Color.White else MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = preset.description,
                style = MaterialTheme.typography.bodySmall,
                color = if (isSelected) Color.White.copy(alpha = 0.8f) else MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun RepetitionCard(
    repetitions: Int,
    quality: String,
    description: String,
    estimatedDuration: String,
    onRepetitionsChanged: (Int) -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        tonalElevation = 2.dp
    ) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(text = stringResource(R.string.freq_config_repetitions), style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text(text = "$repetitions×", style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold, color = VolumColors.SystemMint)
                Column(horizontalAlignment = Alignment.End) {
                    Text(text = quality, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(text = description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Slider(
                value = repetitions.toFloat(),
                onValueChange = { onRepetitionsChanged(it.roundToInt()) },
                valueRange = MIN_REPETITIONS.toFloat()..MAX_REPETITIONS.toFloat(),
                steps = MAX_REPETITIONS - MIN_REPETITIONS - 1
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surfaceVariant, shape = MaterialTheme.shapes.medium)
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Default.Speed, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(stringResource(R.string.freq_config_estimated_duration), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(text = estimatedDuration, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun FrequencyCard(
    startFrequency: Float,
    stopFrequency: Float,
    onStartChanged: (Float) -> Unit,
    onStopChanged: (Float) -> Unit,
    rangeSummary: String
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        tonalElevation = 2.dp
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(text = stringResource(R.string.freq_config_frequency_range), style = MaterialTheme.typography.titleMedium)
            FrequencySlider(
                label = stringResource(R.string.freq_config_start),
                value = startFrequency,
                valueRange = MIN_START_FREQ..MAX_START_FREQ,
                color = VolumColors.SystemTeal,
                onValueChange = onStartChanged
            )
            FrequencySlider(
                label = stringResource(R.string.freq_config_stop),
                value = stopFrequency,
                valueRange = MIN_STOP_FREQ..MAX_STOP_FREQ,
                color = VolumColors.SystemIndigo,
                onValueChange = onStopChanged
            )
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.medium,
                color = MaterialTheme.colorScheme.surfaceVariant
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(stringResource(R.string.freq_config_range), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(rangeSummary, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun FrequencySlider(
    label: String,
    value: Float,
    valueRange: ClosedFloatingPointRange<Float>,
    color: Color,
    onValueChange: (Float) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
            Text(text = label, style = MaterialTheme.typography.labelLarge)
            Text(text = formatFrequency(value), fontWeight = FontWeight.SemiBold, color = color)
        }
        Slider(
            value = value,
            onValueChange = onValueChange,
            valueRange = valueRange,
            colors = SliderDefaults.colors(activeTrackColor = color, thumbColor = color)
        )
        Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
            Text(text = formatFrequency(valueRange.start), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(text = formatFrequency(valueRange.endInclusive), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun PointsCard(points: Int, onPointsChanged: (Int) -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        tonalElevation = 2.dp
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(text = stringResource(R.string.freq_config_measurement_points), style = MaterialTheme.typography.titleMedium)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(text = "$points", style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold, color = VolumColors.QualityFair)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    IconButton(onClick = { onPointsChanged(points + 4) }) {
                        Text(text = "+", style = MaterialTheme.typography.titleLarge)
                    }
                    IconButton(onClick = { onPointsChanged(points - 4) }) {
                        Text(text = "-", style = MaterialTheme.typography.titleLarge)
                    }
                }
            }
            Slider(
                value = points.toFloat(),
                onValueChange = { onPointsChanged(it.roundToInt()) },
                valueRange = MIN_POINT_COUNT.toFloat()..MAX_POINT_COUNT.toFloat(),
                steps = MAX_POINT_COUNT - MIN_POINT_COUNT - 1,
                colors = SliderDefaults.colors(activeTrackColor = VolumColors.QualityFair, thumbColor = VolumColors.QualityFair)
            )
        }
    }
}

@Composable
private fun SummaryCard(uiState: FrequencyConfigurationUiState) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        tonalElevation = 1.dp
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(text = stringResource(R.string.freq_config_measurement_summary), style = MaterialTheme.typography.titleMedium)
            SummaryRow(label = stringResource(R.string.freq_config_total_points), value = uiState.totalPoints.toString())
            SummaryRow(label = stringResource(R.string.freq_config_data_per_sweep), value = stringResource(R.string.freq_config_points_value, uiState.points))
            SummaryRow(label = stringResource(R.string.freq_config_sweeps), value = "${uiState.repetitions}×")
            SummaryRow(label = stringResource(R.string.freq_config_duration), value = uiState.estimatedDurationText)
            SummaryRow(label = stringResource(R.string.freq_config_quality), value = uiState.repetitionQuality)
        }
    }
}

@Composable
private fun SummaryRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(text = value, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun ApplySection(
    isApplying: Boolean,
    isConnected: Boolean,
    status: String?,
    onApply: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Button(
            onClick = onApply,
            enabled = isConnected && !isApplying,
            modifier = Modifier.fillMaxWidth()
        ) {
            if (isApplying) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = Color.White)
                Spacer(modifier = Modifier.width(8.dp))
                Text(stringResource(R.string.freq_config_applying))
            } else {
                Text(stringResource(R.string.freq_config_apply_configuration))
            }
        }
        if (!isConnected) {
            Text(
                text = stringResource(R.string.freq_config_connect_device_hint),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall
            )
        } else {
            status?.let {
                Text(text = it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

private fun formatFrequency(value: Float): String {
    return if (value >= 1_000f) {
        String.format("%.0f kHz", value / 1_000f)
    } else {
        "${value.roundToInt()} Hz"
    }
}
