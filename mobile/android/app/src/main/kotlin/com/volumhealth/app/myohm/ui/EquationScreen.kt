package com.volumhealth.app.myohm.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.volumhealth.app.myohm.data.MyohmViewModel
import com.volumhealth.app.myohm.domain.BodyComposition
import com.volumhealth.app.myohm.domain.BodyEquation
import com.volumhealth.app.myohm.domain.BodyInputs
import com.volumhealth.app.myohm.domain.EquationSelection
import com.volumhealth.core.model.Athlete

@Composable
fun EquationScreen(vm: MyohmViewModel, id: String, onBack: () -> Unit) {
    val records by vm.records.collectAsState()
    val people by vm.people.collectAsState()
    val record = records.firstOrNull { it.id == id }
    val person = record?.let { r -> people.orEmpty().firstOrNull { it.id == r.personId } }
    val ref = record?.sweep?.atReference
    val inputs = if (record != null && person != null && ref != null) MeasurementValue.bodyInputs(record, person, ref) else null
    val eq = (inputs?.let { BodyComposition.select(it) } as? EquationSelection.Equation)?.equation

    ResultColumn {
        if (inputs != null && eq != null && person != null) {
            ScreenHeader(L("How it was calculated"), L("%s equation", eq.shortName), back = onBack)
            FormulaCard(eq, inputs, person)
            ValidityCard(eq, inputs, person)
            SelectionCard(eq)
            Reference(eq)
        } else {
            ScreenHeader(null, L("Equation"), back = onBack)
            Text(L("No equation applies to this measurement."), style = MyohmText.body.copy(color = MyohmColor.muted))
        }
    }
}

private fun formulaText(eq: BodyEquation) = when (eq) {
    BodyEquation.GENEVA -> L("FFM = −4.104\n+ 0.518 · height² / R\n+ 0.231 · weight\n+ 0.130 · Xc\n+ 4.229 · sex")
    BodyEquation.ATHLETES -> L("FFM = −2.261\n+ 0.327 · height² / R\n+ 0.525 · weight\n+ 5.462 · sex")
    BodyEquation.YOUTH -> L("FFM = 0.61 · height² / R\n+ 0.25 · weight\n+ 1.31")
}

private fun c(value: Double, digits: Int = 3) = MyohmFormat.number(value, digits)

private fun terms(eq: BodyEquation, i: BodyInputs): List<Pair<String, Double>> {
    val h = MyohmFormat.number(i.heightCm, 0)
    val r = MyohmFormat.number(i.r50, 0)
    val w = MyohmFormat.kg(i.weightKg)
    val sex = if (i.isMale) L("male (1)") else L("female (0)")
    val index = i.heightCm * i.heightCm / i.r50
    return when (eq) {
        BodyEquation.GENEVA -> listOf(
            "${c(0.518)} · $h² / $r" to 0.518 * index,
            "${c(0.231)} · $w" to 0.231 * i.weightKg,
            "${c(0.130)} · ${MyohmFormat.ohms(i.xc50)}" to 0.130 * i.xc50,
            "${c(4.229)} · $sex" to if (i.isMale) 4.229 else 0.0,
            L("Constant") to -4.104
        )
        BodyEquation.ATHLETES -> listOf(
            "${c(0.327)} · $h² / $r" to 0.327 * index,
            "${c(0.525)} · $w" to 0.525 * i.weightKg,
            "${c(5.462)} · $sex" to if (i.isMale) 5.462 else 0.0,
            L("Constant") to -2.261
        )
        BodyEquation.YOUTH -> listOf(
            "${c(0.61, 2)} · $h² / $r" to 0.61 * index,
            "${c(0.25, 2)} · $w" to 0.25 * i.weightKg,
            L("Constant") to 1.31
        )
    }
}

@Composable
private fun FormulaCard(eq: BodyEquation, i: BodyInputs, person: Athlete) {
    val estimate = BodyComposition.estimate(i, eq)
    CardColumn(padding = 18.dp, spacing = 14.dp) {
        Text(
            formulaText(eq),
            style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace, color = MyohmColor.brand, lineHeight = 24.sp),
            modifier = Modifier.fillMaxWidth().background(MyohmColor.background, RoundedCornerShape(14.dp)).padding(14.dp)
        )
        Text(L("FFM: fat-free mass (kg). Height in cm, weight in kg, R and Xc in Ω at 50 kHz. Sex: male = 1, female = 0."), style = MyohmText.small)
        Text(L("With %s's data", person.firstName), style = MyohmText.headline, modifier = Modifier.padding(top = 4.dp))
        Column {
            terms(eq, i).forEach { (label, value) ->
                TermRow(label, (if (value < 0) "−" else "") + MyohmFormat.number(kotlin.math.abs(value), 2))
            }
            Column {
                Row(Modifier.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(L("Fat-free mass"), style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink), modifier = Modifier.weight(1f))
                    Text(MyohmFormat.kg(estimate.fatFreeMassKg), style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.ExtraBold, color = MyohmColor.brand))
                }
                HairlineDivider()
            }
            TermRow(
                L("Fat = %s − %s", MyohmFormat.number(i.weightKg), MyohmFormat.number(estimate.fatFreeMassKg)),
                MyohmFormat.kg(estimate.fatMassKg) + " · " + MyohmFormat.percent(estimate.fatPercent),
                last = true
            )
        }
    }
}

@Composable
private fun TermRow(label: String, value: String, last: Boolean = false) {
    Column {
        Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = TextStyle(fontSize = 14.sp, color = MyohmColor.muted), modifier = Modifier.weight(1f))
            Text(value, style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.ink), modifier = Modifier.padding(start = 8.dp))
        }
        if (!last) HairlineDivider()
    }
}

@Composable
private fun ValidityCard(eq: BodyEquation, i: BodyInputs, person: Athlete) {
    CardColumn(padding = 18.dp, spacing = 10.dp) {
        Text(L("Is it valid for %s?", person.firstName), style = MyohmText.headline)
        EquationChecks.checks(eq, i).filter { it.id != "see" }.forEach { check ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(
                    if (check.ok) Icons.Filled.CheckCircle else Icons.Outlined.ErrorOutline, null,
                    tint = if (check.ok) MyohmColor.success else MyohmColor.accent, modifier = Modifier.size(20.dp)
                )
                Text(check.label, style = TextStyle(fontSize = 14.sp, color = MyohmColor.ink), modifier = Modifier.weight(1f))
                Text(check.detail, style = TextStyle(fontSize = 14.sp, color = MyohmColor.muted))
            }
        }
        Text(
            when (eq) {
                BodyEquation.GENEVA -> L("Typical error ± 1.72 kg of fat-free mass (r = 0.986), in 343 healthy adults compared with DXA.")
                BodyEquation.ATHLETES -> L("Developed in athletes against a 4-compartment model. Typical error not yet verified by Myohm.")
                BodyEquation.YOUTH -> L("Developed and cross-validated in children and adolescents. Typical error not yet verified by Myohm.")
            },
            style = MyohmText.caption, modifier = Modifier.padding(top = 4.dp)
        )
    }
}

@Composable
private fun SelectionCard(current: BodyEquation) {
    Column(Modifier.myohmCard(18.dp)) {
        Text(L("How the app chooses"), style = MyohmText.headline, modifier = Modifier.padding(bottom = 6.dp))
        SelectionRow(L("Adult, BMI 17–34"), "Geneva 2001", highlighted = current == BodyEquation.GENEVA)
        SelectionRow(L("Athlete"), "Matias–Campa 2021", highlighted = current == BodyEquation.ATHLETES)
        SelectionRow(L("10–19 years"), "Houtkooper 1992", highlighted = current == BodyEquation.YOUTH)
        SelectionRow(L("Under 10 years"), L("No fat; phase only"), warning = true)
        SelectionRow(L("BMI above 34"), L("Water only (spectrum)"), warning = true, last = true)
        Text(L("Each measurement keeps the data used, so the calculation can be repeated."), style = MyohmText.small, modifier = Modifier.padding(top = 8.dp))
    }
}

@Composable
private fun SelectionRow(who: String, eq: String, highlighted: Boolean = false, warning: Boolean = false, last: Boolean = false) {
    Column {
        Row(Modifier.padding(vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(who, style = TextStyle(fontSize = 14.sp, color = MyohmColor.ink), modifier = Modifier.weight(1f))
            Text(
                eq,
                style = TextStyle(
                    fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                    color = if (highlighted) MyohmColor.brand else if (warning) MyohmColor.accentInk else MyohmColor.ink
                )
            )
        }
        if (!last) HairlineDivider()
    }
}

@Composable
private fun Reference(eq: BodyEquation) {
    val context = LocalContext.current
    Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        SectionLabel(L("Reference"))
        Text(eq.citation, style = MyohmText.caption.copy(color = MyohmColor.ink))
        Box(
            Modifier.heightIn(min = 44.dp).pressable {
                runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://doi.org/${eq.doi}"))) }
            },
            contentAlignment = Alignment.CenterStart
        ) {
            Text("doi:${eq.doi}", style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.brand))
        }
    }
}
