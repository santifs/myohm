package com.volumhealth.app.ui.screens.subjects

import android.graphics.Paint
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.volumhealth.app.R
import com.volumhealth.app.ui.theme.VolumColors
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.MeasurementPoint
import com.volumhealth.core.processing.unwrapPhaseDegrees
import java.util.Locale
import kotlin.math.absoluteValue
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeasurementResultScreen(
    viewModel: MeasurementResultViewModel = hiltViewModel(),
    onNewMeasurement: () -> Unit,
    onChangeSubject: () -> Unit
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text(stringResource(R.string.result_title)) },
                scrollBehavior = scrollBehavior
            )
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            when {
                state.isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                state.impedance == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(stringResource(R.string.result_no_data))
                }
                else -> Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 20.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp)
                ) {
                    ImpedanceCharts(impedance = state.impedance!!)

                    Spacer(Modifier.height(4.dp))

                    Button(
                        onClick = onNewMeasurement,
                        modifier = Modifier.fillMaxWidth().height(56.dp),
                        shape = RoundedCornerShape(20.dp),
                        elevation = ButtonDefaults.buttonElevation(defaultElevation = 4.dp)
                    ) {
                        Text(
                            stringResource(R.string.result_new_measurement),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold
                        )
                    }

                    OutlinedButton(
                        onClick = onChangeSubject,
                        modifier = Modifier.fillMaxWidth().height(48.dp),
                        shape = RoundedCornerShape(16.dp)
                    ) {
                        Text(stringResource(R.string.result_change_subject))
                    }

                    Spacer(Modifier.height(8.dp))
                }
            }
        }
    }
}

@Composable
private fun ImpedanceCharts(impedance: ImpedanceData) {
    val rawPoints = impedance.measurements
    if (rawPoints.isEmpty()) return

    // Sort by frequency so the line connects ascending and the unwrap walks
    // through samples in the order phase actually evolves.
    val points = rawPoints.sortedBy { it.frequency }
    val unwrappedPhases = unwrapPhaseDegrees(points.map { it.phase })
    val phasePoints = points.mapIndexed { i, p -> p.copy(phase = unwrappedPhases[i]) }

    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                stringResource(R.string.result_chart_magnitude),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            InteractiveSpectralChart(
                points = points,
                transform = { it.magnitude },
                yUnit = "Ω",
                lineColor = VolumColors.BrandPrimary,
                modifier = Modifier.fillMaxWidth().height(220.dp)
            )
        }
    }

    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                stringResource(R.string.result_chart_phase),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            InteractiveSpectralChart(
                points = phasePoints,
                transform = { it.phase },
                yUnit = "°",
                lineColor = VolumColors.SystemOrange,
                modifier = Modifier.fillMaxWidth().height(220.dp)
            )
        }
    }
}

/**
 * Interactive log-frequency chart with y-axis tick labels, x-axis frequency labels,
 * and tap/drag to select a point. Crosshair + header text showing (f, y) for the
 * selected point.
 */
@Composable
private fun InteractiveSpectralChart(
    points: List<MeasurementPoint>,
    transform: (MeasurementPoint) -> Float,
    yUnit: String,
    lineColor: Color,
    modifier: Modifier = Modifier
) {
    if (points.size < 2) return

    var selectedIndex by remember(points) {
        mutableIntStateOf(points.lastIndex.coerceAtLeast(0))
    }
    val selected = points.getOrNull(selectedIndex)

    val outlineColor = MaterialTheme.colorScheme.outline
    val tertiaryColor = MaterialTheme.colorScheme.tertiary
    val labelColor = MaterialTheme.colorScheme.onSurface
    val surfaceVariantColor = MaterialTheme.colorScheme.surfaceVariant

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Surface(
            shape = MaterialTheme.shapes.small,
            color = surfaceVariantColor.copy(alpha = 0.5f)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = if (selected != null) {
                        "f = ${formatFrequency(selected.frequency)}Hz"
                    } else "—",
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    text = if (selected != null) {
                        "${formatChartValue(transform(selected))} $yUnit"
                    } else "—",
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }

        Canvas(
            modifier = modifier
                .pointerInput(points) {
                    detectTapGestures { offset ->
                        selectedIndex = nearestPointIndex(points, offset.x, size.width.toFloat())
                    }
                }
                .pointerInput(points) {
                    detectDragGestures { change, _ ->
                        selectedIndex = nearestPointIndex(points, change.position.x, size.width.toFloat())
                    }
                }
        ) {
            val values = points.map(transform)
            val minValue = values.min()
            val maxValue = values.max()
            val valueRange = max(0.0001f, maxValue - minValue)

            val frequencies = points.map { it.frequency }
            val freqMin = frequencies.min()
            val freqMax = frequencies.max()
            val minLog = ln(freqMin.coerceAtLeast(1f).toDouble()).toFloat()
            val maxLog = ln(freqMax.coerceAtLeast(1f).toDouble()).toFloat()
            val logRange = max(0.0001f, maxLog - minLog)

            val leftPadding = 44.dp.toPx()
            val rightPadding = 12.dp.toPx()
            val topPadding = 8.dp.toPx()
            val bottomPadding = 22.dp.toPx()
            val chartWidth = size.width - leftPadding - rightPadding
            val chartHeight = size.height - topPadding - bottomPadding

            fun xForFrequency(freq: Float): Float {
                val lf = ln(freq.coerceAtLeast(1f).toDouble()).toFloat()
                return leftPadding + ((lf - minLog) / logRange) * chartWidth
            }

            fun pointOffset(p: MeasurementPoint): Offset {
                val normalizedY = (transform(p) - minValue) / valueRange
                return Offset(
                    x = xForFrequency(p.frequency),
                    y = topPadding + chartHeight - normalizedY * chartHeight
                )
            }

            // Standard frequency ticks
            val allTicks = listOf(1_000f, 5_000f, 10_000f, 50_000f, 100_000f, 150_000f, 200_000f)
            val visibleTicks = allTicks.filter { it in freqMin..freqMax }

            // Gridlines: vertical at tick frequencies
            visibleTicks.forEach { f ->
                val x = xForFrequency(f)
                drawLine(
                    color = outlineColor.copy(alpha = 0.15f),
                    start = Offset(x, topPadding),
                    end = Offset(x, topPadding + chartHeight),
                    strokeWidth = 1.dp.toPx()
                )
            }
            // Gridlines: 4 horizontals
            repeat(4) { i ->
                val y = topPadding + (i / 3f) * chartHeight
                drawLine(
                    color = outlineColor.copy(alpha = 0.15f),
                    start = Offset(leftPadding, y),
                    end = Offset(leftPadding + chartWidth, y),
                    strokeWidth = 1.dp.toPx()
                )
            }
            // Axes
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

            // Line path
            val path = Path()
            points.forEachIndexed { i, p ->
                val o = pointOffset(p)
                if (i == 0) path.moveTo(o.x, o.y) else path.lineTo(o.x, o.y)
            }
            drawPath(path, color = lineColor, style = Stroke(width = 3.dp.toPx()))

            // Point markers
            points.forEachIndexed { i, p ->
                val o = pointOffset(p)
                val isSel = i == selectedIndex
                drawCircle(
                    color = if (isSel) tertiaryColor else lineColor,
                    radius = if (isSel) 5.dp.toPx() else 2.5f.dp.toPx(),
                    center = o
                )
            }

            // Crosshair for selection
            selected?.let { p ->
                val o = pointOffset(p)
                drawLine(
                    color = tertiaryColor.copy(alpha = 0.45f),
                    start = Offset(o.x, topPadding),
                    end = Offset(o.x, topPadding + chartHeight),
                    strokeWidth = 1.dp.toPx()
                )
                drawLine(
                    color = tertiaryColor.copy(alpha = 0.45f),
                    start = Offset(leftPadding, o.y),
                    end = Offset(leftPadding + chartWidth, o.y),
                    strokeWidth = 1.dp.toPx()
                )
            }

            // Text paints
            val textRed = (labelColor.red * 255).roundToInt()
            val textGreen = (labelColor.green * 255).roundToInt()
            val textBlue = (labelColor.blue * 255).roundToInt()

            val xPaint = Paint().apply {
                color = android.graphics.Color.argb(180, textRed, textGreen, textBlue)
                textSize = 10.sp.toPx()
                textAlign = Paint.Align.CENTER
                isAntiAlias = true
            }
            val yPaint = Paint().apply {
                color = android.graphics.Color.argb(180, textRed, textGreen, textBlue)
                textSize = 10.sp.toPx()
                textAlign = Paint.Align.RIGHT
                isAntiAlias = true
            }

            // X-axis labels
            visibleTicks.forEach { f ->
                drawContext.canvas.nativeCanvas.drawText(
                    formatFrequency(f),
                    xForFrequency(f),
                    size.height - 4.dp.toPx(),
                    xPaint
                )
            }

            // Y-axis labels: min, 1/3, 2/3, max
            repeat(4) { i ->
                val ratio = i / 3f
                val value = minValue + (1f - ratio) * valueRange
                val y = topPadding + ratio * chartHeight + 4.dp.toPx()
                drawContext.canvas.nativeCanvas.drawText(
                    formatChartValue(value),
                    leftPadding - 6.dp.toPx(),
                    y,
                    yPaint
                )
            }
        }
    }
}

private fun nearestPointIndex(
    points: List<MeasurementPoint>,
    rawX: Float,
    canvasWidth: Float
): Int {
    if (points.isEmpty()) return 0
    val clampedX = rawX.coerceIn(0f, canvasWidth)
    val minLog = ln(points.minOf { it.frequency }.coerceAtLeast(1f).toDouble()).toFloat()
    val maxLog = ln(points.maxOf { it.frequency }.coerceAtLeast(1f).toDouble()).toFloat()
    val logRange = max(0.0001f, maxLog - minLog)
    return points.indices.minByOrNull { idx ->
        val p = points[idx]
        val pointX = ((ln(p.frequency.toDouble()).toFloat() - minLog) / logRange) * canvasWidth
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
    return when {
        value.absoluteValue >= 100f -> String.format(Locale.getDefault(), "%.0f", value)
        value.absoluteValue >= 10f -> String.format(Locale.getDefault(), "%.1f", value)
        else -> String.format(Locale.getDefault(), "%.2f", value)
    }
}
