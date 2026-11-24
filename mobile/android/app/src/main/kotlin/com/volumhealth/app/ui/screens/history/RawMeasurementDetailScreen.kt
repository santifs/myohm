package com.volumhealth.app.ui.screens.history

import android.graphics.Paint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Cyclone
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.volumhealth.app.R
import com.volumhealth.app.ui.components.QualityIndicator
import com.volumhealth.app.ui.theme.VolumColors
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.MeasurementPoint
import com.volumhealth.core.model.RawMeasurement
import com.volumhealth.core.processing.unwrapPhaseDegrees
import java.util.Locale
import kotlin.math.absoluteValue
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.roundToInt
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RawMeasurementDetailScreen(
    viewModel: RawMeasurementDetailViewModel = hiltViewModel(),
    onNavigateBack: () -> Unit
) {
    val measurement by viewModel.measurement.collectAsStateWithLifecycle()
    val data = measurement ?: return
    val selectedRep by viewModel.selectedRepetition.collectAsStateWithLifecycle()
    val repetitions = data.repetitions ?: data.rawData.repetitions.map { repetition ->
        ImpedanceData.fromSingleRepetition(
            measurements = repetition,
            timestamp = data.rawData.timestamp,
            deviceInfo = data.rawData.deviceInfo
        )
    }
    val displayData = repetitions.getOrNull(selectedRep) ?: data.rawData

    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text(stringResource(R.string.raw_measurement_title)) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = stringResource(R.string.raw_measurement_back))
                    }
                },
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
            item { RawHeader(measurement = data) }
            if (repetitions.size > 1) {
                item {
                    RepetitionSelector(
                        total = repetitions.size,
                        selected = selectedRep,
                        signalQuality = data.signalQuality ?: data.results?.quality?.score ?: 0f,
                        onRepetitionSelected = { index ->
                            viewModel.selectedRepetition.value = index
                        }
                    )
                }
            }
            item { SummaryCard(data = displayData) }
            item { ProcessingStatusCard(measurement = data) }
            item {
                PlotCard(
                    title = stringResource(R.string.raw_measurement_magnitude),
                    data = displayData,
                    useMagnitude = true
                )
            }
            item {
                PlotCard(
                    title = stringResource(R.string.raw_measurement_phase),
                    data = displayData,
                    useMagnitude = false
                )
            }
            item { Spacer(modifier = Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun RawHeader(measurement: RawMeasurement) {
    val timestamp = measurement.captureTimestamp.toLocalDateTime(TimeZone.currentSystemDefault())
    val qualityScore = measurement.signalQuality ?: measurement.results?.quality?.score
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        tonalElevation = 2.dp
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Column {
                Text(
                    stringResource(R.string.raw_measurement_bioimpedance),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    "${timestamp.date} ${timestamp.time.hour}:${timestamp.time.minute.toString().padStart(2, '0')}",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            qualityScore?.let { QualityIndicator(score = it) }
        }
    }
}

@Composable
private fun RepetitionSelector(
    total: Int,
    selected: Int,
    signalQuality: Float,
    onRepetitionSelected: (Int) -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        tonalElevation = 1.dp
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.raw_measurement_repetitions), style = MaterialTheme.typography.titleMedium)
                Text(
                    stringResource(R.string.raw_measurement_quality_percent, (signalQuality * 100).roundToInt()),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Row(
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                IconButton(onClick = { if (selected > 0) onRepetitionSelected(selected - 1) }, enabled = selected > 0) {
                    Icon(Icons.Default.Cyclone, contentDescription = stringResource(R.string.raw_measurement_previous_repetition))
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        stringResource(R.string.raw_measurement_repetition_number, selected + 1),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        stringResource(R.string.raw_measurement_of_total, total),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                IconButton(onClick = { if (selected < total - 1) onRepetitionSelected(selected + 1) }, enabled = selected < total - 1) {
                    Icon(Icons.Default.Cyclone, contentDescription = stringResource(R.string.raw_measurement_next_repetition))
                }
            }
            Row(horizontalArrangement = Arrangement.Center, modifier = Modifier.fillMaxWidth()) {
                repeat(total) { index ->
                    val color = if (index == selected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.2f)
                    }
                    Spacer(
                        modifier = Modifier
                            .padding(horizontal = 4.dp)
                            .height(6.dp)
                            .weight(1f)
                            .background(color, shape = MaterialTheme.shapes.extraSmall)
                    )
                }
            }
        }
    }
}

@Composable
private fun SummaryCard(data: ImpedanceData) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        tonalElevation = 1.dp
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.raw_measurement_summary), style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                SummaryItem(
                    icon = Icons.Default.Speed,
                    label = stringResource(R.string.raw_measurement_points),
                    value = data.measurements.size.toString()
                )
                SummaryItem(
                    icon = Icons.Default.BarChart,
                    label = stringResource(R.string.raw_measurement_sweep_range),
                    value = stringResource(
                        R.string.raw_measurement_sweep_range_value,
                        data.frequencies.firstOrNull()?.toInt() ?: 0,
                        data.frequencies.lastOrNull()?.toInt() ?: 0
                    )
                )
            }
        }
    }
}

@Composable
private fun SummaryItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String
) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Column {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun ProcessingStatusCard(measurement: RawMeasurement) {
    val isProcessed = measurement.results != null
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = if (isProcessed) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = stringResource(
                    if (isProcessed) R.string.raw_measurement_processing_complete
                    else R.string.raw_measurement_processing_status
                ),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(
                    if (isProcessed) R.string.raw_measurement_processing_complete_desc
                    else R.string.raw_measurement_processing_desc
                ),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun PlotCard(title: String, data: ImpedanceData, useMagnitude: Boolean) {
    val sorted = data.measurements.sortedBy { it.frequency }
    val plotPoints = if (useMagnitude) {
        sorted
    } else {
        val unwrapped = unwrapPhaseDegrees(sorted.map { it.phase })
        sorted.mapIndexed { i, p -> p.copy(phase = unwrapped[i]) }
    }
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(260.dp),
        shape = MaterialTheme.shapes.large,
        tonalElevation = 1.dp
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            RawLineChart(
                measurements = plotPoints,
                transform = { point -> if (useMagnitude) point.magnitude else point.phase },
                color = if (useMagnitude) VolumColors.SystemIndigo else VolumColors.SystemMint,
                valueLabel = stringResource(
                    if (useMagnitude) R.string.raw_measurement_value_ohms
                    else R.string.raw_measurement_value_degrees
                ),
                interactionHint = stringResource(R.string.raw_measurement_touch_hint)
            )
        }
    }
}

@Composable
private fun RawLineChart(
    measurements: List<MeasurementPoint>,
    transform: (MeasurementPoint) -> Float,
    color: Color,
    valueLabel: String,
    @Suppress("UNUSED_PARAMETER") interactionHint: String
) {
    var selectedIndex by remember(measurements) { mutableIntStateOf(measurements.lastIndex.coerceAtLeast(0)) }
    val selectedPoint = measurements.getOrNull(selectedIndex)
    val outlineColor = MaterialTheme.colorScheme.outline
    val tertiaryColor = MaterialTheme.colorScheme.tertiary
    val labelColor = MaterialTheme.colorScheme.onSurface

    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxSize()) {
        Surface(
            shape = MaterialTheme.shapes.medium,
            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        ) {
            Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)) {
                if (selectedPoint != null) {
                    Text(
                        text = stringResource(
                            R.string.raw_measurement_selected_point,
                            formatFrequency(selectedPoint.frequency),
                            formatChartValue(transform(selectedPoint))
                        ),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = valueLabel,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    Text(
                        text = interactionHint,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        Box(modifier = Modifier.fillMaxSize()) {
            Canvas(
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(measurements) {
                        detectTapGestures { offset ->
                            selectedIndex = nearestPointIndex(measurements, offset.x, size.width.toFloat())
                        }
                    }
                    .pointerInput(measurements) {
                        detectDragGestures { change, _ ->
                            selectedIndex = nearestPointIndex(measurements, change.position.x, size.width.toFloat())
                        }
                    }
            ) {
                if (measurements.size < 2) return@Canvas

                val frequencies = measurements.map { it.frequency }
                val values = measurements.map(transform)
                val minValue = values.minOrNull() ?: 0f
                val maxValue = values.maxOrNull() ?: 0f
                val valueRange = max(0.0001f, maxValue - minValue)
                val tickFrequencies = listOf(1000f, 5000f, 10000f, 50000f, 100000f, 150000f)

                val leftPadding = 44.dp.toPx()
                val rightPadding = 12.dp.toPx()
                val topPadding = 8.dp.toPx()
                val bottomPadding = 22.dp.toPx()
                val chartWidth = size.width - leftPadding - rightPadding
                val chartHeight = size.height - topPadding - bottomPadding

                val minLog = ln((frequencies.minOrNull() ?: 1f).toDouble()).toFloat()
                val maxLog = ln((frequencies.maxOrNull() ?: 1f).toDouble()).toFloat()
                val logRange = max(0.0001f, maxLog - minLog)

                fun xForFrequency(frequency: Float): Float {
                    val logFrequency = ln(frequency.toDouble()).toFloat()
                    return leftPadding + ((logFrequency - minLog) / logRange) * chartWidth
                }

                fun pointOffset(point: MeasurementPoint): Offset {
                    val x = xForFrequency(point.frequency)
                    val normalizedY = (transform(point) - minValue) / valueRange
                    val y = topPadding + chartHeight - normalizedY * chartHeight
                    return Offset(x, y)
                }

                tickFrequencies
                    .filter { it in (frequencies.minOrNull() ?: it)..(frequencies.maxOrNull() ?: it) }
                    .forEach { frequency ->
                        val x = xForFrequency(frequency)
                        drawLine(
                            color = outlineColor.copy(alpha = 0.15f),
                            start = Offset(x, topPadding),
                            end = Offset(x, topPadding + chartHeight),
                            strokeWidth = 1.dp.toPx()
                        )
                    }

                repeat(4) { index ->
                    val ratio = index / 3f
                    val y = topPadding + ratio * chartHeight
                    drawLine(
                        color = outlineColor.copy(alpha = 0.15f),
                        start = Offset(leftPadding, y),
                        end = Offset(leftPadding + chartWidth, y),
                        strokeWidth = 1.dp.toPx()
                    )
                }

                drawLine(
                    color = outlineColor.copy(alpha = 0.4f),
                    start = Offset(leftPadding, topPadding + chartHeight),
                    end = Offset(leftPadding + chartWidth, topPadding + chartHeight),
                    strokeWidth = 1.dp.toPx()
                )
                drawLine(
                    color = outlineColor.copy(alpha = 0.4f),
                    start = Offset(leftPadding, topPadding),
                    end = Offset(leftPadding, topPadding + chartHeight),
                    strokeWidth = 1.dp.toPx()
                )

                val path = Path()
                measurements.forEachIndexed { index, point ->
                    val offset = pointOffset(point)
                    if (index == 0) path.moveTo(offset.x, offset.y) else path.lineTo(offset.x, offset.y)
                }
                drawPath(path, color = color, style = Stroke(width = 3.dp.toPx()))

                measurements.forEachIndexed { index, point ->
                    val offset = pointOffset(point)
                    val isSelected = index == selectedIndex
                    drawCircle(
                        color = if (isSelected) tertiaryColor else color,
                        radius = if (isSelected) 5.dp.toPx() else 3.dp.toPx(),
                        center = offset
                    )
                }

                selectedPoint?.let { point ->
                    val offset = pointOffset(point)
                    drawLine(
                        color = tertiaryColor.copy(alpha = 0.45f),
                        start = Offset(offset.x, topPadding),
                        end = Offset(offset.x, topPadding + chartHeight),
                        strokeWidth = 1.dp.toPx()
                    )
                    drawLine(
                        color = tertiaryColor.copy(alpha = 0.45f),
                        start = Offset(leftPadding, offset.y),
                        end = Offset(leftPadding + chartWidth, offset.y),
                        strokeWidth = 1.dp.toPx()
                    )
                }

                val textRed = (labelColor.red * 255).roundToInt()
                val textGreen = (labelColor.green * 255).roundToInt()
                val textBlue = (labelColor.blue * 255).roundToInt()
                val xLabelPaint = Paint().apply {
                    this.color = android.graphics.Color.argb(180, textRed, textGreen, textBlue)
                    textSize = 10.sp.toPx()
                    textAlign = Paint.Align.CENTER
                    isAntiAlias = true
                }
                val yLabelPaint = Paint().apply {
                    this.color = android.graphics.Color.argb(180, textRed, textGreen, textBlue)
                    textSize = 10.sp.toPx()
                    textAlign = Paint.Align.RIGHT
                    isAntiAlias = true
                }

                tickFrequencies
                    .filter { it in (frequencies.minOrNull() ?: it)..(frequencies.maxOrNull() ?: it) }
                    .forEach { frequency ->
                        drawContext.canvas.nativeCanvas.drawText(
                            formatFrequency(frequency),
                            xForFrequency(frequency),
                            size.height - 4.dp.toPx(),
                            xLabelPaint
                        )
                    }

                repeat(4) { i ->
                    val ratio = i / 3f
                    val value = minValue + (1f - ratio) * valueRange
                    val y = topPadding + ratio * chartHeight + 4.dp.toPx()
                    drawContext.canvas.nativeCanvas.drawText(
                        formatChartValue(value),
                        leftPadding - 6.dp.toPx(),
                        y,
                        yLabelPaint
                    )
                }
            }

        }
    }
}

private fun nearestPointIndex(
    measurements: List<MeasurementPoint>,
    rawX: Float,
    canvasWidth: Float
): Int {
    if (measurements.isEmpty()) return 0
    val clampedX = rawX.coerceIn(0f, canvasWidth)
    val minLog = ln((measurements.minOf { it.frequency }.coerceAtLeast(1f)).toDouble()).toFloat()
    val maxLog = ln((measurements.maxOf { it.frequency }.coerceAtLeast(1f)).toDouble()).toFloat()
    val logRange = max(0.0001f, maxLog - minLog)
    return measurements.indices.minByOrNull { index ->
        val point = measurements[index]
        val pointX = ((ln(point.frequency.toDouble()).toFloat() - minLog) / logRange) * canvasWidth
        (pointX - clampedX).absoluteValue
    } ?: 0
}

private fun formatFrequency(frequency: Float): String {
    return if (frequency >= 1000f) {
        String.format(Locale.getDefault(), "%.0fk", frequency / 1000f)
    } else {
        String.format(Locale.getDefault(), "%.0f", frequency)
    }
}

private fun formatChartValue(value: Float): String {
    return if (value.absoluteValue >= 100f) {
        String.format(Locale.getDefault(), "%.0f", value)
    } else {
        String.format(Locale.getDefault(), "%.2f", value)
    }
}
