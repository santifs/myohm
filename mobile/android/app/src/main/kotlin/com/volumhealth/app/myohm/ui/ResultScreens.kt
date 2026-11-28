package com.volumhealth.app.myohm.ui

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Functions
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.volumhealth.app.myohm.data.MyohmRecord
import com.volumhealth.app.myohm.data.MyohmViewModel
import com.volumhealth.app.myohm.domain.BodyComposition
import com.volumhealth.app.myohm.domain.BodyEquation
import com.volumhealth.app.myohm.domain.BodyInputs
import com.volumhealth.app.myohm.domain.BodyWater
import com.volumhealth.app.myohm.domain.ColeFit
import com.volumhealth.app.myohm.domain.EquationSelection
import com.volumhealth.app.myohm.domain.FatEstimate
import com.volumhealth.app.myohm.domain.MeasurementKind
import com.volumhealth.app.myohm.domain.SweepAnalysis
import com.volumhealth.app.myohm.domain.SweepPoint
import com.volumhealth.core.model.Athlete
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Loads a saved measurement and shows the matching result screen. */
@Composable
fun ResultScreen(
    vm: MyohmViewModel,
    id: String,
    onClose: () -> Unit,
    onEquation: (String) -> Unit,
    onRepeat: (MeasurementKind) -> Unit
) {
    val records by vm.records.collectAsState()
    val people by vm.people.collectAsState()
    val record = records.firstOrNull { it.id == id }
    if (record == null) {
        Box(Modifier.fillMaxSize().background(MyohmColor.background), contentAlignment = Alignment.Center) {
            Text(L("Measurement not found"), style = MyohmText.body.copy(color = MyohmColor.muted))
        }
        return
    }
    val person = people.orEmpty().firstOrNull { it.id == record.personId }
    if (record.isWholeBody) {
        BodyResultScreen(record, person, onClose, onEquation)
    } else {
        LocalResultScreen(record, records, person, onClose, onRepeat)
    }
}

/** Cole fit computed once per screen, off the main thread. */
@Composable
fun rememberColeFit(sweep: SweepAnalysis?): Pair<ColeFit?, Boolean> {
    val result by produceState<Pair<ColeFit?, Boolean>>(Pair(null, false), sweep) {
        if (sweep == null) { value = Pair(null, true); return@produceState }
        val fit = withContext(Dispatchers.Default) { ColeFit.fit(sweep) }
        value = Pair(fit, fit == null)
    }
    return result
}

@Composable
private fun ResultHeader(record: MyohmRecord, onClose: () -> Unit, trailing: (@Composable () -> Unit)? = null) {
    var kicker = MyohmDates.mediumWithTime(record.measuredAt)
    record.bandMillimeters?.let { kicker += " · " + L("band %s mm", it.toString()) }
    record.bodyWeightKg?.let { kicker += " · " + MyohmFormat.kg(it) }
    ScreenHeader(kicker, record.myohmTitle, back = onClose, backIcon = Icons.Filled.Close, trailing = trailing)
}

@Composable
fun ResultColumn(content: @Composable () -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .background(MyohmColor.background)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) { content() }
}

val heroBrush = Brush.radialGradient(listOf(MyohmColor.brandMid, MyohmColor.brand, MyohmColor.brandDeep), center = Offset.Zero, radius = 1250f)

fun Modifier.hero(): Modifier = this
    .fillMaxWidth()
    .shadow(14.dp, RoundedCornerShape(28.dp), ambientColor = MyohmColor.brand.copy(alpha = 0.25f), spotColor = MyohmColor.brand.copy(alpha = 0.35f))
    .background(heroBrush, RoundedCornerShape(28.dp))
    .padding(20.dp)

private val onDark = Color.White

// MARK: - Local result

private enum class SpectrumKind { PHASE, MODULUS, NYQUIST }

@Composable
private fun LocalResultScreen(
    record: MyohmRecord,
    all: List<MyohmRecord>,
    person: Athlete?,
    onClose: () -> Unit,
    onRepeat: (MeasurementKind) -> Unit
) {
    val context = LocalContext.current
    val sweep = record.sweep
    val (fit, failed) = rememberColeFit(sweep)
    var chart by rememberSaveable { mutableStateOf(SpectrumKind.PHASE) }
    var selectedFrequency by rememberSaveable { mutableStateOf<Double?>(null) }
    var compare by rememberSaveable { mutableStateOf(true) }
    val previous = remember(record, all) {
        all.firstOrNull {
            it.id != record.id && it.measuredAt < record.measuredAt && it.personId == record.personId &&
                it.muscleGroup == record.muscleGroup && it.side == record.side && it.bandMillimeters == record.bandMillimeters
        }
    }
    val previousSweep = previous?.sweep
    val ref = sweep?.atReference

    ResultColumn {
        ResultHeader(record, onClose)
        if (sweep == null || ref == null) {
            Text(L("No data in this measurement"), style = MyohmText.body.copy(color = MyohmColor.muted))
            return@ResultColumn
        }
        if (!sweep.looksLikeTissue) ContactWarning()

        // Hero
        Column(Modifier.hero(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(L("Phase angle at 50 kHz"), style = TextStyle(fontSize = 14.sp, color = onDark.copy(alpha = 0.8f)))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(MyohmFormat.degrees(ref.phaseAngle), style = TextStyle(fontSize = 60.sp, fontWeight = FontWeight.ExtraBold, color = onDark, letterSpacing = (-1.5).sp))
                previousSweep?.atReference?.let { prev ->
                    val delta = ref.phaseAngle - prev.phaseAngle
                    Pill((if (delta >= 0) "+" else "−") + MyohmFormat.degrees(kotlin.math.abs(delta)), onDark, onDark.copy(alpha = 0.14f))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                HeroStat(L("Resistance"), MyohmFormat.ohms(ref.resistance))
                HeroStat(L("Reactance"), MyohmFormat.ohms(ref.reactance))
                HeroStat(L("Modulus"), MyohmFormat.ohms(ref.magnitude))
            }
            previous?.let {
                Text(L("Compared with %s, same muscle, side and band.", MyohmDates.medium(it.measuredAt)), style = TextStyle(fontSize = 12.sp, color = onDark.copy(alpha = 0.75f)))
            }
        }

        // Spectrum
        val selected = selectedFrequency?.let { sweep.interpolated(it) }
        val prevPoints = if (compare) previousSweep?.points.orEmpty() else emptyList()
        CardColumn {
            PillSegmented(listOf(SpectrumKind.PHASE to L("Phase"), SpectrumKind.MODULUS to L("Modulus"), SpectrumKind.NYQUIST to "Nyquist"), chart) { chart = it }
            Row(Modifier.fillMaxWidth().height(22.dp), verticalAlignment = Alignment.CenterVertically) {
                if (selected != null) {
                    Text(MyohmFormat.frequency(selected.frequencyHz), style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.muted))
                    Spacer(Modifier.weight(1f))
                    Text(
                        when (chart) {
                            SpectrumKind.PHASE -> MyohmFormat.degrees(selected.phaseAngle)
                            SpectrumKind.MODULUS -> MyohmFormat.ohms(selected.magnitude)
                            SpectrumKind.NYQUIST -> "R " + MyohmFormat.ohms(selected.resistance) + " · Xc " + MyohmFormat.ohms(selected.reactance)
                        },
                        style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink)
                    )
                } else {
                    Text(L("Touch the chart to read any frequency"), style = MyohmText.caption)
                }
            }
            val chartModifier = Modifier.fillMaxWidth().height(220.dp)
            when (chart) {
                SpectrumKind.PHASE, SpectrumKind.MODULUS -> SpectrumChart(
                    sweep.points, prevPoints, chart == SpectrumKind.PHASE, selected, { selectedFrequency = it }, chartModifier
                )
                SpectrumKind.NYQUIST -> NyquistChart(sweep.points, prevPoints, selected, { selectedFrequency = it }, chartModifier)
            }
            if (previous != null) {
                Row(
                    Modifier.fillMaxWidth().pressable { compare = !compare },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Box(Modifier.width(18.dp).height(4.dp).background(MyohmColor.accentSoft, RoundedCornerShape(2.dp)))
                    Text(L("Show previous measurement"), style = MyohmText.caption.copy(color = MyohmColor.ink), modifier = Modifier.weight(1f))
                    Switch(compare, { compare = it }, colors = myohmSwitchColors())
                }
            }
        }

        // Cole model
        CardColumn {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(L("Cole model"), style = MyohmText.headline, modifier = Modifier.weight(1f))
                if (fit == null && !failed) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = MyohmColor.brand)
            }
            if (fit != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Tile("R₀", MyohmFormat.ohms(fit.r0), L("extracellular"), Modifier.weight(1f))
                    Tile("R∞", MyohmFormat.ohms(fit.rInf), L("total"), Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Tile("fc", MyohmFormat.number(fit.fc / 1000) + " kHz", L("characteristic frequency"), Modifier.weight(1f))
                    Tile("α", MyohmFormat.number(fit.alpha, 2), L("dispersion"), Modifier.weight(1f))
                }
            } else if (failed) {
                Text(L("The Cole model could not be fitted to this sweep."), style = MyohmText.caption)
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            MyohmSecondaryButton(
                L("Export CSV"), Modifier.weight(1f),
                leading = { Icon(Icons.Filled.IosShare, null, tint = MyohmColor.ink, modifier = Modifier.size(18.dp)) }
            ) { CsvExport.share(context, record, sweep) }
            MyohmPrimaryButton(L("Repeat"), Modifier.weight(1f)) { record.repeatKind()?.let(onRepeat) }
        }
    }
}

@Composable
private fun HeroStat(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(label, style = TextStyle(fontSize = 12.sp, color = onDark.copy(alpha = 0.75f)))
        Text(value, style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold, color = onDark))
    }
}

@Composable
private fun Tile(symbol: String, value: String, caption: String, modifier: Modifier) {
    Column(
        modifier.background(MyohmColor.background, RoundedCornerShape(14.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(symbol, style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.muted))
        Text(value, style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink))
        Text(caption, style = TextStyle(fontSize = 11.sp, color = MyohmColor.muted))
    }
}

@Composable
fun ContactWarning() {
    Row(
        Modifier.fillMaxWidth().background(MyohmColor.accentBg, RoundedCornerShape(18.dp)).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(Icons.Filled.Warning, null, tint = MyohmColor.accent, modifier = Modifier.size(20.dp))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(L("The signal does not look like tissue"), style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Bold, color = MyohmColor.accentInk))
            Text(
                L("Check that every electrode touches the skin and the cables are connected, then repeat. These values are not reliable."),
                style = MyohmText.caption.copy(color = MyohmColor.accentInk.copy(alpha = 0.85f))
            )
        }
    }
}

object CsvExport {
    fun share(context: Context, record: MyohmRecord, sweep: SweepAnalysis) {
        val lines = mutableListOf("frequency_hz,modulus_ohm,phase_deg,resistance_ohm,reactance_ohm")
        sweep.points.forEach { p ->
            lines += String.format(java.util.Locale.US, "%.1f,%.4f,%.4f,%.4f,%.4f", p.frequencyHz, p.magnitude, -p.phaseAngle, p.resistance, p.reactance)
        }
        val stamp = record.measuredAt.toString().substringBefore('.').replace(":", "")
        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(dir, "myohm-${record.muscleGroup}-$stamp.csv")
        file.writeText(lines.joinToString("\n"))
        val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/csv"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, L("Export CSV")))
    }
}

// MARK: - Whole-body result

@Composable
private fun BodyResultScreen(record: MyohmRecord, person: Athlete?, onClose: () -> Unit, onEquation: (String) -> Unit) {
    val context = LocalContext.current
    val sweep = record.sweep
    val reference = sweep?.atReference
    val inputs = if (person != null && reference != null) MeasurementValue.bodyInputs(record, person, reference) else null
    val selection = inputs?.let { BodyComposition.select(it) }
    val estimate = inputs?.let { BodyComposition.estimate(it) }
    val (fit, failed) = rememberColeFit(sweep)
    val water = if (fit != null && inputs != null) BodyWater.estimate(inputs.heightCm, inputs.weightKg, fit.r0, fit.rInf) else null
    var tab by rememberSaveable { mutableIntStateOf(if (selection == EquationSelection.HighBmi) 1 else 0) }

    ResultColumn {
        ResultHeader(record, onClose, trailing = if (record.restCompleted == false) {
            { Pill(L("Short rest"), MyohmColor.accentInk, MyohmColor.accentBg) }
        } else null)

        if (sweep != null && !sweep.looksLikeTissue) ContactWarning()
        if (inputs == null) {
            CardColumn(spacing = 8.dp) {
                Text(L("Missing data"), style = MyohmText.headline)
                Text(L("Body composition needs height, weight and biological sex. Complete the profile in People."), style = MyohmText.body.copy(color = MyohmColor.muted))
            }
        } else {
            PillSegmented(listOf(0 to L("Fat · 50 kHz"), 1 to L("Water · spectrum")), tab) { tab = it }
            if (tab == 0) {
                when (selection) {
                    EquationSelection.TooYoung -> Notice(L("No validated equation under 10 years"), L("Myohm shows only the phase angle for children under 10."))
                    EquationSelection.HighBmi -> Notice(L("BMI above 34"), L("Prediction equations are not valid with this BMI. Use the water view, calculated from the spectrum."))
                    else -> estimate?.let { FatHero(it, inputs) }
                }
                (selection as? EquationSelection.Equation)?.let { EquationCard(it.equation, inputs) { onEquation(record.id) } }
            } else {
                when {
                    water != null -> WaterHero(water)
                    failed -> Notice(L("Water not available"), L("The Cole model could not be fitted to this sweep."))
                    else -> Row(Modifier.myohmCard(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = MyohmColor.brand)
                        Text(L("Fitting the spectrum…"), style = MyohmText.body.copy(color = MyohmColor.muted))
                    }
                }
                CardColumn(spacing = 4.dp) {
                    Text(L("Spectroscopy model"), style = MyohmText.micro)
                    Text("Moissl et al. · 2006", style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink))
                    Text(L("Extra and intracellular water from R₀ and R∞, validated against isotope dilution."), style = MyohmText.caption)
                }
            }
        }

        if (reference != null) {
            Row(Modifier.myohmCard(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(L("Phase angle at 50 kHz"), style = MyohmText.micro)
                    Text(MyohmFormat.degrees(reference.phaseAngle), style = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.ExtraBold, color = MyohmColor.ink))
                    Text("R " + MyohmFormat.ohms(reference.resistance) + " · Xc " + MyohmFormat.ohms(reference.reactance), style = MyohmText.small)
                }
                Row(
                    Modifier
                        .heightIn(min = 40.dp)
                        .background(MyohmColor.brandSoft, CircleShape)
                        .pressable { CsvExport.share(context, record, sweep) }
                        .padding(horizontal = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(Icons.Filled.IosShare, null, tint = MyohmColor.brand, modifier = Modifier.size(16.dp))
                    Text(L("Export"), style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.brand))
                }
            }
        }

        Text(
            L("Estimate for monitoring, education or research. Not a diagnosis."),
            style = MyohmText.small, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
private fun Notice(title: String, text: String) {
    CardColumn(spacing = 6.dp) {
        Text(title, style = MyohmText.headline)
        Text(text, style = MyohmText.body.copy(color = MyohmColor.muted))
    }
}

@Composable
private fun FatHero(e: FatEstimate, inputs: BodyInputs) {
    Column(Modifier.hero(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(L("Estimated body fat · %s", MyohmFormat.kg(inputs.weightKg)), style = TextStyle(fontSize = 14.sp, color = onDark.copy(alpha = 0.8f)))
        Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Donut(
                listOf(e.fatMassKg to MyohmColor.accentSoft, e.fatFreeMassKg to MyohmColor.leanOnDark),
                MyohmFormat.percent(e.fatPercent),
                e.fatPercentError?.let { L("± %s points", MyohmFormat.number(it)) } ?: L("body fat"),
                Modifier.size(150.dp)
            )
            Column(Modifier.weight(1f)) {
                LegendRow(MyohmColor.accentSoft, L("Fat mass"), MyohmFormat.kg(e.fatMassKg), L("weight − fat-free mass"))
                LegendRow(MyohmColor.leanOnDark, L("Fat-free mass"), MyohmFormat.kg(e.fatFreeMassKg), e.equation.standardErrorKg?.let { "± " + MyohmFormat.kg(it) } ?: "")
            }
        }
        e.fatPercentError?.let { err ->
            ErrorBand(e.fatPercent, err)
            Text(L("The light band is the typical error of the equation. Compare measurements taken in the same conditions."), style = TextStyle(fontSize = 12.sp, color = onDark.copy(alpha = 0.75f)))
        }
    }
}

@Composable
private fun WaterHero(w: BodyWater) {
    Column(Modifier.hero(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(L("Body water · Cole fit"), style = TextStyle(fontSize = 14.sp, color = onDark.copy(alpha = 0.8f)))
        Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Donut(
                listOf(w.extracellularL to MyohmColor.waterOnDark, w.intracellularL to MyohmColor.leanOnDark),
                MyohmFormat.litres(w.totalL), L("total water"), Modifier.size(150.dp)
            )
            Column(Modifier.weight(1f)) {
                LegendRow(MyohmColor.waterOnDark, L("Extracellular"), MyohmFormat.litres(w.extracellularL), L("outside the cells"))
                LegendRow(MyohmColor.leanOnDark, L("Intracellular"), MyohmFormat.litres(w.intracellularL), L("inside the cells"))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DarkTile(L("Extra / total"), MyohmFormat.number(w.extracellularRatio, 2), Modifier.weight(1f))
            DarkTile(L("Fat-free mass (from water)"), "≈ " + MyohmFormat.kg(w.fatFreeMassKg), Modifier.weight(1f))
        }
        Text(L("Uses R₀ and R∞ from the whole spectrum instead of a single frequency."), style = TextStyle(fontSize = 12.sp, color = onDark.copy(alpha = 0.75f)))
    }
}

@Composable
private fun DarkTile(label: String, value: String, modifier: Modifier) {
    Column(modifier.background(onDark.copy(alpha = 0.08f), RoundedCornerShape(16.dp)).padding(horizontal = 12.dp, vertical = 10.dp)) {
        Text(label, style = TextStyle(fontSize = 12.sp, color = onDark.copy(alpha = 0.75f)))
        Text(value, style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = onDark))
    }
}

@Composable
private fun LegendRow(color: Color, label: String, value: String, note: String) {
    Column(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                Box(Modifier.size(9.dp).background(color, CircleShape))
                Text(label, style = TextStyle(fontSize = 12.sp, color = onDark.copy(alpha = 0.78f)))
            }
            Text(value, style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = onDark))
            if (note.isNotEmpty()) Text(note, style = TextStyle(fontSize = 11.sp, color = onDark.copy(alpha = 0.6f)))
        }
        HairlineDivider(onDark.copy(alpha = 0.12f))
    }
}

@Composable
private fun EquationCard(eq: BodyEquation, inputs: BodyInputs, onClick: () -> Unit) {
    Column(Modifier.myohmCard().pressable(onClick = onClick), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(36.dp).background(MyohmColor.brandSoft, RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Functions, null, tint = MyohmColor.brand, modifier = Modifier.size(20.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(L("Equation chosen automatically"), style = MyohmText.micro)
                Text("${eq.shortName} · ${eq.year}", style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink))
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MyohmColor.muted)
        }
        FlowChips(6.dp) {
            EquationChecks.checks(eq, inputs).forEach { check ->
                Pill(check.short, if (check.ok) MyohmColor.success else MyohmColor.accentInk, if (check.ok) MyohmColor.successBg else MyohmColor.accentBg)
            }
        }
    }
}

data class EquationCheck(val id: String, val ok: Boolean, val short: String, val label: String, val detail: String)

object EquationChecks {
    fun checks(eq: BodyEquation, inputs: BodyInputs): List<EquationCheck> {
        val result = mutableListOf<EquationCheck>()
        val age = inputs.ageYears.toInt().toString()
        eq.ageRange?.let { range ->
            val ok = inputs.ageYears in range
            result += EquationCheck(
                "age", ok,
                if (ok) L("Age %s · in range", age) else L("Age %s · out of range", age),
                L("Age %s years", age),
                L("validated %s–%s", range.start.toInt().toString(), range.endInclusive.toInt().toString())
            )
        }
        val bmi = MyohmFormat.number(inputs.bmi)
        eq.bmiRange?.let { range ->
            val ok = inputs.bmi in range
            result += EquationCheck(
                "bmi", ok,
                if (ok) L("BMI %s · in range", bmi) else L("BMI %s · out of range", bmi),
                L("BMI %s", bmi),
                L("validated %s–%s", MyohmFormat.number(range.start), MyohmFormat.number(range.endInclusive))
            )
        }
        if (eq == BodyEquation.GENEVA) {
            result += EquationCheck("side", true, L("Right side"), L("Right hand and foot"), L("as in the study"))
            if (!inputs.isAthlete) result += EquationCheck("athlete", true, L("Not an athlete"), L("Not an athlete"), L("athletes use another equation"))
        }
        eq.standardErrorKg?.let { see ->
            result += EquationCheck("see", true, L("Typical error ± %s", MyohmFormat.kg(see)), L("Typical error"), "± " + MyohmFormat.kg(see))
        }
        return result
    }
}
