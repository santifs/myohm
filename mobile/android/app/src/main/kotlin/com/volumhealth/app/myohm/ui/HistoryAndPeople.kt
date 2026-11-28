package com.volumhealth.app.myohm.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Accessibility
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.volumhealth.app.myohm.data.MyohmRecord
import com.volumhealth.app.myohm.data.MyohmViewModel
import com.volumhealth.app.myohm.domain.BodyEquation
import com.volumhealth.core.model.Athlete
import kotlinx.datetime.Instant

// MARK: - History

private enum class HistoryFilter { ALL, MUSCLES, BODY }

private data class Trend(val title: String, val kicker: String, val percent: Boolean, val points: List<Pair<Instant, Double>>)

@Composable
fun HistoryScreen(vm: MyohmViewModel, onOpen: (String) -> Unit) {
    val people by vm.people.collectAsState()
    val records by vm.records.collectAsState()
    val selectedId by vm.selectedPersonId.collectAsState()
    val person = people.orEmpty().resolve(selectedId)
    var filter by rememberSaveable { mutableStateOf(HistoryFilter.ALL) }

    val mine = person?.let { p -> records.filter { it.personId == p.id && it.sweep != null } }.orEmpty()
    val rows = when (filter) {
        HistoryFilter.ALL -> mine
        HistoryFilter.MUSCLES -> mine.filter { !it.isWholeBody }
        HistoryFilter.BODY -> mine.filter { it.isWholeBody }
    }
    val trend = remember(mine, filter, person) { person?.let { trendFor(mine, filter == HistoryFilter.BODY, it) } }

    Column(
        Modifier
            .fillMaxSize()
            .background(MyohmColor.background)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(L("History"), style = MyohmText.title(28), modifier = Modifier.weight(1f))
            person?.let { Text(it.fullName, style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.brand)) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ChipButton(L("All"), filter == HistoryFilter.ALL) { filter = HistoryFilter.ALL }
            ChipButton(L("Muscles"), filter == HistoryFilter.MUSCLES) { filter = HistoryFilter.MUSCLES }
            ChipButton(L("Whole body"), filter == HistoryFilter.BODY) { filter = HistoryFilter.BODY }
        }
        trend?.let { TrendCard(it) }
        if (rows.isEmpty()) {
            Column(
                Modifier.fillMaxWidth().padding(top = 40.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(Icons.Filled.GraphicEq, null, tint = MyohmColor.muted, modifier = Modifier.size(40.dp))
                Text(L("No measurements yet"), style = MyohmText.headline)
                Text(L("Measurements you take will appear here."), style = MyohmText.caption, textAlign = TextAlign.Center)
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            rows.forEach { r -> MeasurementRow(r, person) { onOpen(r.id) } }
        }
    }
}

private fun trendFor(mine: List<MyohmRecord>, body: Boolean, person: Athlete): Trend? {
    if (body) {
        var equation: BodyEquation? = null
        val points = mine.filter { it.isWholeBody }.reversed().mapNotNull { m ->
            val ref = m.sweep?.atReference ?: return@mapNotNull null
            val e = MeasurementValue.bodyEstimate(m, person, ref) ?: return@mapNotNull null
            equation = e.equation
            m.measuredAt to e.fatPercent
        }
        val eq = equation ?: return null
        if (points.size < 2) return null
        return Trend(L("Body fat"), L("%s equation · %s", eq.shortName, eq.year.toString()), true, points)
    }
    val latest = mine.firstOrNull { !it.isWholeBody } ?: return null
    val series = mine.filter {
        !it.isWholeBody && it.muscleGroup == latest.muscleGroup && it.side == latest.side && it.bandMillimeters == latest.bandMillimeters
    }.reversed().mapNotNull { m -> m.sweep?.atReference?.let { m.measuredAt to it.phaseAngle } }
    if (series.size < 2) return null
    var title = latest.myohmTitle
    latest.bandMillimeters?.let { title += " · $it mm" }
    return Trend(title, L("Phase angle at 50 kHz"), false, series)
}

@Composable
private fun TrendCard(t: Trend) {
    var selected by remember(t) { mutableIntStateOf(t.points.size - 1) }
    val shown = t.points[selected.coerceIn(0, t.points.size - 1)]
    CardColumn(spacing = 10.dp) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(t.kicker, style = MyohmText.micro)
                Text(t.title, style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink))
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    MyohmFormat.number(shown.second) + if (t.percent) " %" else "°",
                    style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = MyohmColor.brand)
                )
                Text(MyohmDates.medium(shown.first), style = TextStyle(fontSize = 11.sp, color = MyohmColor.muted))
            }
        }
        TrendChart(t.points, selected, { selected = it }, Modifier.fillMaxWidth().height(160.dp))
        Text(
            if (t.percent) L("Same equation for every measurement. Changes smaller than the error band are not meaningful.")
            else L("Only measurements with the same muscle, side and band."),
            style = MyohmText.small
        )
    }
}

@Composable
fun MeasurementRow(record: MyohmRecord, person: Athlete?, onClick: () -> Unit) {
    val parts = mutableListOf(MyohmDates.mediumWithTime(record.measuredAt))
    record.bandMillimeters?.let { parts += L("band %s mm", it.toString()) }
    record.bodyWeightKg?.let { parts += MyohmFormat.kg(it) }
    Row(
        Modifier
            .fillMaxWidth()
            .shadow(1.dp, RoundedCornerShape(18.dp), ambientColor = MyohmColor.ink.copy(alpha = 0.06f))
            .background(Color.White, RoundedCornerShape(18.dp))
            .pressable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            Modifier.size(40.dp).background(if (record.isWholeBody) MyohmColor.accentBg else MyohmColor.brandSoft, RoundedCornerShape(12.dp)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                if (record.isWholeBody) Icons.Filled.Accessibility else Icons.Filled.FitnessCenter, null,
                tint = if (record.isWholeBody) MyohmColor.accentInk else MyohmColor.brand, modifier = Modifier.size(20.dp)
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(record.myohmTitle, style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.ink))
            Text(parts.joinToString(" · "), style = MyohmText.caption)
        }
        Text(MeasurementValue.headline(record, person), style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink))
    }
}

// MARK: - People

@Composable
fun PeopleScreen(
    vm: MyohmViewModel,
    onOpen: (String) -> Unit,
    onEdit: (String) -> Unit,
    onAdd: () -> Unit,
    onMeasure: () -> Unit
) {
    val people by vm.people.collectAsState()
    val records by vm.records.collectAsState()
    val selectedId by vm.selectedPersonId.collectAsState()
    val list = people.orEmpty()
    val person = list.resolve(selectedId)
    var menu by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    Column(
        Modifier
            .fillMaxSize()
            .background(MyohmColor.background)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(L("People"), style = MyohmText.title(28), modifier = Modifier.weight(1f))
            Box(
                Modifier.size(44.dp).background(MyohmColor.brand, CircleShape).pressable(onClick = onAdd).semantics { contentDescription = L("Add person") },
                contentAlignment = Alignment.Center
            ) { Icon(Icons.Filled.Add, null, tint = Color.White) }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            list.forEach { p ->
                val selected = p.id == person?.id
                Row(
                    Modifier
                        .height(40.dp)
                        .background(if (selected) MyohmColor.brand else Color.White, CircleShape)
                        .border(1.dp, if (selected) Color.Transparent else MyohmColor.line, CircleShape)
                        .pressable { vm.selectPerson(p.id) }
                        .padding(start = 6.dp, end = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Avatar(p.initials, 28.dp, inverted = selected)
                    Text(p.firstName, style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = if (selected) Color.White else MyohmColor.ink))
                }
            }
        }

        if (person != null) {
            val mine = records.filter { it.personId == person.id }
            val lastBody = mine.firstOrNull { it.isWholeBody }
            val muscles = mine.filter { !it.isWholeBody }
                .groupBy { "${it.muscleGroup}|${it.side}|${it.bandMillimeters ?: 0}" }
                .values.map { group -> group.maxBy { it.measuredAt } to group.size }
                .sortedByDescending { it.first.measuredAt }

            CardColumn(padding = 18.dp, spacing = 14.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Avatar(person.initials, 60.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(person.fullName, style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink))
                        Text(person.profileSummary, style = MyohmText.caption)
                    }
                    Box {
                        LinkText(L("Edit")) { menu = true }
                        DropdownMenu(menu, { menu = false }, modifier = Modifier.background(Color.White)) {
                            DropdownMenuItem(text = { Text(L("Edit")) }, onClick = { menu = false; onEdit(person.id) })
                            DropdownMenuItem(text = { Text(L("Delete person"), color = MyohmColor.accent) }, onClick = { menu = false; confirmDelete = true })
                        }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Metric(L("Height"), person.heightCm?.let { MyohmFormat.number(it, 0) + " cm" } ?: "—", Modifier.weight(1f))
                    Metric(L("Weight"), person.weightKg?.let { MyohmFormat.kg(it) } ?: "—", Modifier.weight(1f))
                    Metric(L("BMI"), person.bmiValue?.let { MyohmFormat.number(it) } ?: "—", Modifier.weight(1f))
                }
            }

            if (lastBody != null) {
                SectionLabel(L("Latest values"))
                Row(Modifier.pressable { onOpen(lastBody.id) }, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ValueTile(L("Body fat"), MeasurementValue.headline(lastBody, person), lastBody.measuredAt, Modifier.weight(1f))
                    ValueTile(
                        L("Whole-body phase"),
                        lastBody.sweep?.atReference?.let { MyohmFormat.degrees(it.phaseAngle) } ?: "—",
                        lastBody.measuredAt, Modifier.weight(1f)
                    )
                }
            }

            if (muscles.isNotEmpty()) {
                SectionLabel(L("Muscles measured"))
                Column(
                    Modifier
                        .fillMaxWidth()
                        .shadow(1.dp, RoundedCornerShape(20.dp), ambientColor = MyohmColor.ink.copy(alpha = 0.06f))
                        .background(Color.White, RoundedCornerShape(20.dp))
                ) {
                    muscles.forEachIndexed { index, (record, count) ->
                        Column(Modifier.pressable { onOpen(record.id) }) {
                            Row(Modifier.padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(record.myohmTitle, style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.ink))
                                    val band = (record.bandMillimeters ?: 0).toString()
                                    Text(
                                        if (count == 1) L("Band %s mm · 1 measurement", band) else L("Band %s mm · %s measurements", band, count.toString()),
                                        style = MyohmText.caption
                                    )
                                }
                                Text(MeasurementValue.headline(record, person), style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink))
                            }
                            if (index < muscles.size - 1) HairlineDivider()
                        }
                    }
                }
            }

            MyohmPrimaryButton(L("Measure %s", person.firstName), onClick = onMeasure)

            if (confirmDelete) {
                AlertDialog(
                    onDismissRequest = { confirmDelete = false },
                    title = { Text(L("Delete %s?", person.fullName)) },
                    text = { Text(L("Their measurements will also be deleted from this phone. This cannot be undone.")) },
                    confirmButton = {
                        TextButton(onClick = { confirmDelete = false; vm.deletePerson(person) }) { Text(L("Delete"), color = MyohmColor.accent) }
                    },
                    dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(L("Cancel"), color = MyohmColor.brand) } },
                    containerColor = Color.White
                )
            }
        }
    }
}

@Composable
private fun Metric(label: String, value: String, modifier: Modifier) {
    Column(modifier.background(MyohmColor.background, RoundedCornerShape(14.dp)).padding(horizontal = 12.dp, vertical = 10.dp)) {
        Text(label, style = MyohmText.small)
        Text(value, style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink), maxLines = 1)
    }
}

@Composable
private fun ValueTile(label: String, value: String, date: Instant, modifier: Modifier) {
    Column(
        modifier
            .shadow(1.dp, RoundedCornerShape(20.dp), ambientColor = MyohmColor.ink.copy(alpha = 0.06f))
            .background(Color.White, RoundedCornerShape(20.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(label, style = MyohmText.micro)
        Text(value, style = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.ExtraBold, color = MyohmColor.ink), maxLines = 1)
        Text(MyohmDates.medium(date), style = MyohmText.small)
    }
}
