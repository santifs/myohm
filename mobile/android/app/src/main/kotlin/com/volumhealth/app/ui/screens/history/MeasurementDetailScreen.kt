package com.volumhealth.app.ui.screens.history

import android.content.ClipData
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Button
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
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.patrykandpatrick.vico.compose.chart.Chart
import com.patrykandpatrick.vico.compose.chart.line.lineChart
import com.patrykandpatrick.vico.core.entry.ChartEntry
import com.patrykandpatrick.vico.core.entry.ChartEntryModelProducer
import com.patrykandpatrick.vico.core.entry.entryOf
import com.volumhealth.app.R
import com.volumhealth.app.ui.components.ParameterCard
import com.volumhealth.app.ui.components.QualityIndicator
import com.volumhealth.app.ui.theme.VolumColors
import com.volumhealth.core.model.ColeParameters
import com.volumhealth.core.model.RawMeasurement
import com.volumhealth.core.processing.ColeModel
import java.util.Locale
import kotlin.math.PI
import kotlinx.coroutines.launch
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeasurementDetailScreen(
    viewModel: MeasurementDetailViewModel = hiltViewModel(),
    onNavigateBack: () -> Unit = {}
) {
    val measurement by viewModel.measurement.collectAsStateWithLifecycle()
    val data = measurement ?: return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val bodeCharts = rememberBodeCharts(data)
    val exportSubject = stringResource(R.string.measurement_detail_export_subject, data.id)
    val exportChooserTitle = stringResource(R.string.measurement_detail_export_chooser)
    val exportErrorMessage = stringResource(R.string.measurement_detail_export_error)

    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text(stringResource(R.string.measurement_detail_title)) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = stringResource(R.string.measurement_detail_back))
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
            item { MeasurementHeader(data) }
            item { ParameterSection(data.results) }
            item {
                ChartCard(
                    title = stringResource(R.string.measurement_detail_resistance),
                    description = stringResource(R.string.measurement_detail_resistance_desc),
                    chartModelProducer = bodeCharts.resistance
                )
            }
            item {
                ChartCard(
                    title = stringResource(R.string.measurement_detail_reactance),
                    description = stringResource(R.string.measurement_detail_reactance_desc),
                    chartModelProducer = bodeCharts.reactance
                )
            }
            item {
                Button(
                    onClick = {
                        scope.launch {
                            runCatching { viewModel.exportMeasurement(data) }
                                .onSuccess { result ->
                                    val intent = Intent(Intent.ACTION_SEND).apply {
                                        type = result.mimeType
                                        putExtra(Intent.EXTRA_SUBJECT, exportSubject)
                                        putExtra(Intent.EXTRA_STREAM, result.uri)
                                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        clipData = ClipData.newUri(context.contentResolver, result.fileName, result.uri)
                                    }
                                    context.startActivity(Intent.createChooser(intent, exportChooserTitle))
                                }
                                .onFailure {
                                    Toast.makeText(context, exportErrorMessage, Toast.LENGTH_SHORT).show()
                                }
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.measurement_detail_export_button))
                }
            }
            item {
                PointsSection(data)
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun MeasurementHeader(measurement: RawMeasurement) {
    val timestamp = measurement.captureTimestamp.toLocalDateTime(TimeZone.currentSystemDefault())
    val patient = measurement.patientSnapshot
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        tonalElevation = 2.dp
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "${timestamp.date}",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "%02d:%02d".format(Locale.getDefault(), timestamp.hour, timestamp.minute),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                QualityIndicator(score = measurement.results?.quality?.score ?: 0.5f)
            }
            Text(
                text = patient?.let {
                    val genderText = when (it.gender) {
                        com.volumhealth.core.model.Gender.MALE -> stringResource(R.string.gender_male)
                        com.volumhealth.core.model.Gender.FEMALE -> stringResource(R.string.gender_female)
                        com.volumhealth.core.model.Gender.OTHER -> ""
                    }
                    "${it.name}, ${it.age}y, $genderText"
                }
                    ?: stringResource(R.string.measurement_detail_no_patient),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = stringResource(R.string.measurement_detail_processing_tier, measurement.results?.processingTier?.displayName ?: stringResource(R.string.measurement_detail_pending)),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun ParameterSection(results: ColeParameters?) {
    if (results == null) return
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ParameterCard(
            label = "Re",
            value = formatValue(results.Re),
            unit = "Ω",
            description = stringResource(R.string.measurement_detail_extracellular),
            color = VolumColors.SystemIndigo,
            modifier = Modifier.fillMaxWidth()
        )
        ParameterCard(
            label = "Ri",
            value = formatValue(results.Ri),
            unit = "Ω",
            description = stringResource(R.string.measurement_detail_intracellular),
            color = VolumColors.SystemTeal,
            modifier = Modifier.fillMaxWidth()
        )
        ParameterCard(
            label = "Cm",
            value = formatValue(results.Cm, 2),
            unit = "nF",
            description = stringResource(R.string.measurement_detail_membrane_capacitance),
            color = VolumColors.QualityFair,
            modifier = Modifier.fillMaxWidth()
        )
        ParameterCard(
            label = "fc",
            value = formatValue(results.fc),
            unit = "kHz",
            description = stringResource(R.string.measurement_detail_characteristic_frequency),
            color = VolumColors.SystemMint,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
private fun ChartCard(
    title: String,
    description: String,
    chartModelProducer: ChartEntryModelProducer
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        tonalElevation = 2.dp
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(text = title, style = MaterialTheme.typography.titleMedium)
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Chart(
                chart = lineChart(),
                chartModelProducer = chartModelProducer,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(220.dp)
            )
        }
    }
}

@Composable
private fun PointsSection(measurement: RawMeasurement) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        tonalElevation = 1.dp
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(stringResource(R.string.measurement_detail_raw_points), style = MaterialTheme.typography.titleMedium)
            measurement.rawData.measurements.forEach { point ->
                Text(
                    text = "${point.frequency.toInt()} Hz • ${formatValue(point.magnitude, 3)} Ω • ${formatValue(point.phase, 2)}°",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

private data class BodeCharts(
    val resistance: ChartEntryModelProducer,
    val reactance: ChartEntryModelProducer
)

@Composable
private fun rememberBodeCharts(measurement: RawMeasurement): BodeCharts {
    return remember(measurement.id, measurement.results) {
        val frequencies = measurement.rawData.measurements.map { it.frequency }
        val measuredResistance = measurement.rawData.measurements.map {
            entryOf(it.frequency, it.complexImpedance.real)
        }
        val measuredReactance = measurement.rawData.measurements.map {
            entryOf(it.frequency, -it.complexImpedance.imaginary)
        }
        val results = measurement.results
        val resistanceEntries = mutableListOf<List<ChartEntry>>(measuredResistance)
        val reactanceEntries = mutableListOf<List<ChartEntry>>(measuredReactance)
        if (results != null) {
            val tau = calculateTau(results)
            val modelResistance = frequencies.map { freq ->
                val z = ColeModel.calculateImpedance(results.Re, results.Rinf, tau, results.alpha, freq)
                entryOf(freq, z.real)
            }
            val modelReactance = frequencies.map { freq ->
                val z = ColeModel.calculateImpedance(results.Re, results.Rinf, tau, results.alpha, freq)
                entryOf(freq, -z.imaginary)
            }
            resistanceEntries += modelResistance
            reactanceEntries += modelReactance
        }
        BodeCharts(
            resistance = ChartEntryModelProducer(*resistanceEntries.toTypedArray()),
            reactance = ChartEntryModelProducer(*reactanceEntries.toTypedArray())
        )
    }
}

private fun calculateTau(parameters: ColeParameters): Float {
    val fcHz = (parameters.fc * 1000f).coerceAtLeast(1f)
    return (1f / (2f * PI.toFloat() * fcHz)).coerceAtLeast(1e-7f)
}

private fun formatValue(value: Float, decimals: Int = 1): String =
    "%.${decimals}f".format(Locale.getDefault(), value)
