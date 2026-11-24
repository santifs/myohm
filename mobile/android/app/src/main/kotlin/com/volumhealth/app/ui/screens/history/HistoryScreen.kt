package com.volumhealth.app.ui.screens.history

import android.content.ClipData
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.SelectAll
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.volumhealth.app.R
import com.volumhealth.app.ui.components.QualityIndicator
import com.volumhealth.app.ui.theme.VolumColors
import com.volumhealth.core.model.ColeParameters
import com.volumhealth.core.model.ProcessingState
import com.volumhealth.core.model.RawMeasurement
import java.util.Locale
import kotlinx.coroutines.launch
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(
    viewModel: HistoryViewModel = hiltViewModel(),
    onMeasurementSelected: (String) -> Unit = {},
    onRawMeasurementSelected: (String) -> Unit = {}
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isSelectionMode by rememberSaveable { mutableStateOf(false) }
    var selectedIds by rememberSaveable { mutableStateOf(setOf<String>()) }

    val noMeasurementsText = stringResource(R.string.no_measurements_to_export)
    val exportSubject = stringResource(R.string.volumhealth_export)
    val exportTitle = stringResource(R.string.export_measurements)
    val exportFailedText = stringResource(R.string.failed_to_export)

    val exportMeasurements: (List<RawMeasurement>) -> Unit = export@{ measurements ->
        if (measurements.isEmpty()) {
            Toast.makeText(context, noMeasurementsText, Toast.LENGTH_SHORT).show()
            return@export
        }
        scope.launch {
            runCatching { viewModel.exportMeasurements(measurements) }
                .onSuccess { result ->
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = result.mimeType
                        putExtra(Intent.EXTRA_SUBJECT, exportSubject)
                        putExtra(Intent.EXTRA_STREAM, result.uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        clipData = ClipData.newUri(context.contentResolver, result.fileName, result.uri)
                    }
                    context.startActivity(Intent.createChooser(shareIntent, exportTitle))
                }
                .onFailure {
                    Toast.makeText(context, exportFailedText, Toast.LENGTH_SHORT).show()
                }
        }
    }

    val selectedMeasurements = remember(selectedIds, state.filteredMeasurements) {
        state.filteredMeasurements.filter { selectedIds.contains(it.id) }
    }

    LaunchedEffect(state.filteredMeasurements) {
        val validIds = state.filteredMeasurements.map { it.id }.toSet()
        val sanitized = selectedIds.filter { it in validIds }.toSet()
        if (sanitized.size != selectedIds.size) {
            selectedIds = sanitized
        }
    }

    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            HistoryTopBar(
                isSelectionMode = isSelectionMode,
                selectedCount = selectedIds.size,
                scrollBehavior = scrollBehavior,
                onCloseSelection = {
                    isSelectionMode = false
                    selectedIds = emptySet()
                },
                onExportFiltered = { exportMeasurements(state.filteredMeasurements) },
                onEnterSelection = {
                    selectedIds = emptySet()
                    isSelectionMode = true
                },
                onExportSelection = { exportMeasurements(selectedMeasurements) }
            )
        },
        bottomBar = {
            if (isSelectionMode) {
                SelectionBar(
                    selectedCount = selectedIds.size,
                    onExport = { exportMeasurements(selectedMeasurements) },
                    onClear = {
                        selectedIds = emptySet()
                        isSelectionMode = false
                    }
                )
            }
        }
    ) { padding ->
        if (state.filteredMeasurements.isEmpty()) {
            EmptyHistoryPlaceholder(modifier = Modifier
                .fillMaxSize()
                .padding(padding))
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item {
                    FilterRow(
                        selected = state.filter,
                        onFilterSelected = {
                            selectedIds = emptySet()
                            viewModel.onFilterSelected(it)
                        }
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                }
                items(state.filteredMeasurements, key = { it.id }) { measurement ->
                    val annotation = state.annotationsByMeasurementId[measurement.id]
                    MeasurementRow(
                        measurement = measurement,
                        label = annotation?.label,
                        subjectName = annotation?.subjectName,
                        muscleGroup = annotation?.muscleGroup,
                        side = annotation?.side,
                        isSelectionMode = isSelectionMode,
                        isSelected = selectedIds.contains(measurement.id),
                        onToggleSelection = {
                            selectedIds = if (selectedIds.contains(measurement.id)) {
                                selectedIds - measurement.id
                            } else {
                                selectedIds + measurement.id
                            }
                        },
                        onOpenDetail = {
                            if (measurement.results != null) onMeasurementSelected(measurement.id)
                            else onRawMeasurementSelected(measurement.id)
                        },
                        onLongPress = {
                            if (!isSelectionMode) {
                                isSelectionMode = true
                                selectedIds = setOf(measurement.id)
                            }
                        }
                    )
                }
                item { Spacer(modifier = Modifier.height(48.dp)) }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HistoryTopBar(
    isSelectionMode: Boolean,
    selectedCount: Int,
    scrollBehavior: androidx.compose.material3.TopAppBarScrollBehavior,
    onCloseSelection: () -> Unit,
    onExportFiltered: () -> Unit,
    onEnterSelection: () -> Unit,
    onExportSelection: () -> Unit
) {
    if (isSelectionMode) {
        TopAppBar(
            title = { Text(stringResource(R.string.selected_count_format, selectedCount)) },
            navigationIcon = {
                IconButton(onClick = onCloseSelection) {
                    Icon(imageVector = Icons.Default.Close, contentDescription = stringResource(R.string.close_selection))
                }
            },
            actions = {
                IconButton(
                    onClick = onExportSelection,
                    enabled = selectedCount > 0
                ) {
                    Icon(imageVector = Icons.Default.Share, contentDescription = stringResource(R.string.export_selected))
                }
            }
        )
    } else {
        var menuExpanded by remember { mutableStateOf(false) }
        LargeTopAppBar(
            title = { Text(stringResource(R.string.history_title)) },
            scrollBehavior = scrollBehavior,
            actions = {
                IconButton(onClick = onEnterSelection) {
                    Icon(imageVector = Icons.Default.SelectAll, contentDescription = stringResource(R.string.select_measurements))
                }
                Box {
                    IconButton(onClick = { menuExpanded = true }) {
                        Icon(imageVector = Icons.Default.Share, contentDescription = stringResource(R.string.export))
                    }
                    DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.export_current_filter)) },
                            onClick = {
                                menuExpanded = false
                                onExportFiltered()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.select_and_export)) },
                            onClick = {
                                menuExpanded = false
                                onEnterSelection()
                            }
                        )
                    }
                }
            }
        )
    }
}

@Composable
private fun SelectionBar(
    selectedCount: Int,
    onExport: () -> Unit,
    onClear: () -> Unit
) {
    Surface(tonalElevation = 3.dp) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = stringResource(R.string.selected_count_format, selectedCount),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onClear) {
                    Text(stringResource(R.string.cancel))
                }
                Button(
                    onClick = onExport,
                    enabled = selectedCount > 0
                ) {
                    Text(stringResource(R.string.export))
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FilterRow(
    selected: HistoryFilter,
    onFilterSelected: (HistoryFilter) -> Unit
) {
    val filterLabels = mapOf(
        HistoryFilter.ALL to stringResource(R.string.filter_all),
        HistoryFilter.COMPLETED to stringResource(R.string.status_complete),
        HistoryFilter.PENDING to stringResource(R.string.status_pending),
        HistoryFilter.FAILED to stringResource(R.string.status_failed)
    )
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        HistoryFilter.values().forEach { filter ->
            FilterChip(
                selected = filter == selected,
                onClick = { onFilterSelected(filter) },
                label = { Text(filterLabels[filter] ?: filter.name) }
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MeasurementRow(
    measurement: RawMeasurement,
    label: String?,
    subjectName: String?,
    muscleGroup: String?,
    side: String?,
    isSelectionMode: Boolean,
    isSelected: Boolean,
    onToggleSelection: () -> Unit,
    onOpenDetail: () -> Unit,
    onLongPress: () -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = {
                    if (isSelectionMode) onToggleSelection() else onOpenDetail()
                },
                onLongClick = onLongPress
            ),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top
        ) {
            if (isSelectionMode) {
                IconButton(onClick = onToggleSelection) {
                    Icon(
                        imageVector = if (isSelected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                        contentDescription = null,
                        tint = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = subjectName ?: stringResource(R.string.history_unknown_subject),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    if (label != null) {
                        Surface(
                            shape = RoundedCornerShape(50),
                            color = MaterialTheme.colorScheme.primaryContainer
                        ) {
                            Text(
                                text = label.uppercase(Locale.getDefault()),
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 3.dp)
                            )
                        }
                    }
                }
                val muscleSideText = formatMuscleSide(muscleGroup, side)
                if (muscleSideText.isNotEmpty()) {
                    Text(
                        text = muscleSideText,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "${formatDate(measurement)} · ${formatTime(measurement)}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    measurement.results?.quality?.score?.let { quality ->
                        QualityIndicator(score = quality)
                    }
                }
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.Top) {
                StatusBadge(state = measurement.processingState)
            }
        }
    }
}

@Composable
private fun ProcessedMeasurementContent(results: ColeParameters) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        QualityIndicator(score = results.quality.score)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ParameterBadge(
                label = "Re",
                value = formatValue(results.Re),
                unit = "Ω",
                color = VolumColors.SystemIndigo,
                modifier = Modifier.weight(1f)
            )
            ParameterBadge(
                label = "Ri",
                value = formatValue(results.Ri),
                unit = "Ω",
                color = VolumColors.SystemTeal,
                modifier = Modifier.weight(1f)
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ParameterBadge(
                label = "Cm",
                value = formatValue(results.Cm, 2),
                unit = "nF",
                color = VolumColors.QualityFair,
                modifier = Modifier.weight(1f)
            )
            ParameterBadge(
                label = "fc",
                value = formatValue(results.fc),
                unit = "kHz",
                color = VolumColors.SystemMint,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun RawMeasurementContent(measurement: RawMeasurement) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = stringResource(R.string.awaiting_processing),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = stringResource(R.string.frequency_points_format, measurement.rawData.measurements.size),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun StatusBadge(state: ProcessingState) {
    val labelComplete = stringResource(R.string.status_complete)
    val labelProcessing = stringResource(R.string.status_processing)
    val labelPending = stringResource(R.string.status_pending)
    val labelFailed = stringResource(R.string.status_failed)

    val (label, color) = when (state) {
        ProcessingState.COMPLETED -> labelComplete to VolumColors.SystemGreen
        ProcessingState.PROCESSING, ProcessingState.RETRYING -> labelProcessing to VolumColors.SystemOrange
        ProcessingState.PENDING -> labelPending to VolumColors.BrandPrimary
        ProcessingState.FAILED -> labelFailed to VolumColors.SystemRed
    }
    Surface(
        shape = CircleShape,
        color = color.copy(alpha = 0.16f)
    ) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Medium,
            color = color
        )
    }
}

@Composable
private fun ParameterBadge(
    label: String,
    value: String,
    unit: String,
    color: Color,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
        color = color.copy(alpha = 0.12f)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(text = label, style = MaterialTheme.typography.labelSmall, color = color)
            Row(verticalAlignment = Alignment.Bottom) {
                Text(text = value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = color)
                Spacer(modifier = Modifier.width(4.dp))
                Text(text = unit, style = MaterialTheme.typography.labelSmall, color = color)
            }
        }
    }
}

@Composable
private fun EmptyHistoryPlaceholder(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = Icons.Filled.History,
            contentDescription = null,
            modifier = Modifier
                .padding(bottom = 16.dp)
                .size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = stringResource(R.string.no_measurements_yet),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = stringResource(R.string.empty_history_description),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 8.dp),
            textAlign = TextAlign.Center
        )
    }
}

private fun formatDate(measurement: RawMeasurement): String {
    val timestamp = measurement.captureTimestamp.toLocalDateTime(TimeZone.currentSystemDefault())
    return "${timestamp.date}"
}

private fun formatTime(measurement: RawMeasurement): String {
    val timestamp = measurement.captureTimestamp.toLocalDateTime(TimeZone.currentSystemDefault())
    return "%02d:%02d".format(Locale.getDefault(), timestamp.hour, timestamp.minute)
}

private fun patientSummary(measurement: RawMeasurement, noPatientInfoText: String, maleText: String, femaleText: String): String {
    val patient = measurement.patientSnapshot
    return if (patient != null) {
        val genderText = when (patient.gender) {
            com.volumhealth.core.model.Gender.MALE -> maleText
            com.volumhealth.core.model.Gender.FEMALE -> femaleText
            com.volumhealth.core.model.Gender.OTHER -> ""
        }
        "${patient.name}, ${patient.age}y, $genderText"
    } else {
        noPatientInfoText
    }
}

private fun formatValue(value: Float, decimals: Int = 1): String =
    "%.${decimals}f".format(Locale.getDefault(), value)

private fun formatMuscleSide(muscleGroup: String?, side: String?): String {
    val mg = muscleGroup
        ?.takeIf { it.isNotBlank() }
        ?.let { com.volumhealth.core.model.MuscleGroup.fromString(it)?.displayName ?: it }
    val sd = side?.takeIf { it.isNotBlank() }?.let {
        when (it.lowercase(Locale.getDefault())) {
            "right" -> "Dcho"
            "left" -> "Izdo"
            else -> it
        }
    }
    return listOfNotNull(mg, sd).joinToString(" · ")
}
