package com.volumhealth.app.myohm.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Accessibility
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.volumhealth.app.myohm.data.MyohmRecord
import com.volumhealth.app.myohm.data.MyohmViewModel
import com.volumhealth.app.myohm.domain.MeasurementKind
import com.volumhealth.core.ble.ConnectionState
import com.volumhealth.core.model.Athlete

fun List<Athlete>.resolve(id: String): Athlete? = firstOrNull { it.id == id } ?: firstOrNull()

/** Whole body returns null: it goes back to placement because it needs today's weight. */
fun MyohmRecord.repeatKind(): MeasurementKind? {
    if (isWholeBody) return null
    val m = muscle ?: return null
    val s = bodySide ?: return null
    return MeasurementKind.Muscle(m, s, bandMillimeters ?: m.suggestedBand ?: 100)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    vm: MyohmViewModel,
    onMuscle: () -> Unit,
    onWholeBody: () -> Unit,
    onRepeat: (MeasurementKind?) -> Unit,
    onPairing: () -> Unit,
    onSettings: () -> Unit
) {
    val people by vm.people.collectAsState()
    val records by vm.records.collectAsState()
    val selectedId by vm.selectedPersonId.collectAsState()
    val state by vm.connectionState.collectAsState()
    val battery by vm.battery.collectAsState()
    val person = people.orEmpty().resolve(selectedId)
    val last = person?.let { p -> records.firstOrNull { it.personId == p.id } }
    var showPicker by remember { mutableStateOf(false) }

    Column(
        Modifier
            .fillMaxSize()
            .background(MyohmColor.background)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MyohmLogo(width = 104.dp)
            Spacer(Modifier.weight(1f))
            ConnectionPill(state, battery, vm.hasPairedDevice()) {
                if (vm.hasPairedDevice() && state is ConnectionState.Disconnected) vm.reconnect()
                else if (state !is ConnectionState.Connected && state !is ConnectionState.Measuring) onPairing()
            }
            CircleIconButton(Icons.Outlined.Settings, L("Settings"), onSettings)
        }

        if (person != null) {
            Row(
                Modifier.myohmCard(14.dp).pressable { showPicker = true },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Avatar(person.initials, 44.dp)
                Column(Modifier.weight(1f)) {
                    Text(L("Person"), style = MyohmText.caption)
                    Text(person.fullName, style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink))
                }
                Text(L("Change"), style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.brand))
            }
        }

        Text(L("What do you want to measure?"), style = MyohmText.title(26), modifier = Modifier.padding(top = 4.dp))

        ChoiceCard(L("One muscle"), L("Phase angle and spectrum with an electrode band."), Icons.Filled.FitnessCenter, dark = true, onClick = onMuscle)
        ChoiceCard(L("Whole body"), L("Body fat and water, with cables from wrist to ankle."), Icons.Filled.Accessibility, dark = false, onClick = onWholeBody)

        if (last != null && (last.isWholeBody || last.repeatKind() != null)) {
            Row(
                Modifier.myohmCard(14.dp).pressable { onRepeat(last.repeatKind()) },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(Modifier.size(40.dp).background(MyohmColor.brandSoft, RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.Replay, null, tint = MyohmColor.brand, modifier = Modifier.size(20.dp))
                }
                Column(Modifier.weight(1f)) {
                    Text(L("Repeat last"), style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.ink))
                    val parts = mutableListOf(last.myohmTitle)
                    last.bandMillimeters?.let { parts += L("band %s mm", it.toString()) }
                    Text(parts.joinToString(" · "), style = MyohmText.caption)
                }
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MyohmColor.muted)
            }
        }
    }

    if (showPicker) {
        ModalBottomSheet(
            onDismissRequest = { showPicker = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = MyohmColor.background
        ) {
            Column(Modifier.navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 16.dp)) {
                Text(L("Who is being measured?"), style = MyohmText.headline, modifier = Modifier.padding(bottom = 12.dp))
                Column(Modifier.background(Color.White, RoundedCornerShape(20.dp))) {
                    people.orEmpty().forEachIndexed { index, p ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .heightIn(min = 60.dp)
                                .pressable {
                                    vm.selectPerson(p.id)
                                    showPicker = false
                                }
                                .padding(horizontal = 16.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Avatar(p.initials, 36.dp)
                            Column(Modifier.weight(1f)) {
                                Text(p.fullName, style = MyohmText.body)
                                Text(p.profileSummary, style = MyohmText.caption)
                            }
                            if (p.id == person?.id) Icon(Icons.Filled.Check, null, tint = MyohmColor.brand)
                        }
                        if (index < people.orEmpty().size - 1) Box(Modifier.padding(start = 64.dp)) { HairlineDivider() }
                    }
                }
            }
        }
    }
}

@Composable
private fun ChoiceCard(title: String, subtitle: String, icon: ImageVector, dark: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(28.dp)
    val fg = if (dark) Color.White else MyohmColor.ink
    Row(
        Modifier
            .fillMaxWidth()
            .shadow(if (dark) 10.dp else 1.dp, shape, ambientColor = if (dark) MyohmColor.brand.copy(alpha = 0.25f) else MyohmColor.ink.copy(alpha = 0.06f), spotColor = if (dark) MyohmColor.brand.copy(alpha = 0.35f) else MyohmColor.ink.copy(alpha = 0.1f))
            .background(
                if (dark) Brush.radialGradient(listOf(MyohmColor.brandMid, MyohmColor.brand, MyohmColor.brandDeep), center = androidx.compose.ui.geometry.Offset.Zero, radius = 1100f)
                else Brush.linearGradient(listOf(Color.White, Color.White)),
                shape
            )
            .pressable(onClick = onClick)
            .padding(20.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(
                Modifier.size(48.dp).background(if (dark) Color.White.copy(alpha = 0.14f) else MyohmColor.brandSoft, RoundedCornerShape(14.dp)),
                contentAlignment = Alignment.Center
            ) { Icon(icon, null, tint = if (dark) Color.White else MyohmColor.brand, modifier = Modifier.size(26.dp)) }
            Text(title, style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold, color = fg))
            Text(subtitle, style = MyohmText.body.copy(color = fg.copy(alpha = 0.8f)))
        }
        Box(Modifier.size(40.dp).background(if (dark) Color.White else MyohmColor.brand, CircleShape), contentAlignment = Alignment.Center) {
            Icon(Icons.AutoMirrored.Filled.ArrowForward, null, tint = if (dark) MyohmColor.brand else Color.White, modifier = Modifier.size(20.dp))
        }
    }
}

// MARK: - Settings

@Composable
fun SettingsScreen(vm: MyohmViewModel, onBack: () -> Unit, onPairing: () -> Unit, onLaboratory: () -> Unit) {
    val battery by vm.battery.collectAsState()
    var confirmForget by remember { mutableStateOf(false) }
    var paired by remember { mutableStateOf(vm.pairedDeviceName() ?: if (vm.hasPairedDevice()) "Myohm" else null) }

    Column(
        Modifier
            .fillMaxSize()
            .background(MyohmColor.background)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        ScreenHeader(null, L("Settings"), back = onBack)

        SectionLabel(L("Device"))
        Column(Modifier.myohmCard(0.dp, RoundedCornerShape(20.dp))) {
            SettingsRow(L("Name"), value = vm.ble.connectedDeviceName ?: paired ?: "—")
            battery?.let { HairlineDivider(); SettingsRow(L("Battery"), value = "${it.percentage} %") }
            HairlineDivider()
            SettingsRow(L("Connect another device"), color = MyohmColor.brand) {
                vm.disconnect()
                onPairing()
            }
            if (paired != null) {
                HairlineDivider()
                SettingsRow(L("Forget this device"), color = MyohmColor.accent) { confirmForget = true }
            }
        }

        Column(Modifier.myohmCard(0.dp, RoundedCornerShape(20.dp))) {
            SettingsRow(L("Laboratory mode"), chevron = true, onClick = onLaboratory)
        }
        Text(L("Configurable sweeps and raw data export, without a person."), style = MyohmText.caption, modifier = Modifier.padding(horizontal = 4.dp))

        Text(L("Estimates for monitoring, education and research. Not a diagnosis."), style = MyohmText.caption, modifier = Modifier.padding(horizontal = 4.dp, vertical = 8.dp))
    }

    if (confirmForget) {
        AlertDialog(
            onDismissRequest = { confirmForget = false },
            title = { Text(L("Forget this device?")) },
            text = { Text(L("You will need to pair it again before measuring.")) },
            confirmButton = {
                TextButton(onClick = {
                    vm.forgetDevice()
                    paired = null
                    confirmForget = false
                }) { Text(L("Forget"), color = MyohmColor.accent) }
            },
            dismissButton = { TextButton(onClick = { confirmForget = false }) { Text(L("Cancel"), color = MyohmColor.brand) } },
            containerColor = Color.White
        )
    }
}

@Composable
private fun SettingsRow(
    label: String,
    value: String? = null,
    color: Color = MyohmColor.ink,
    chevron: Boolean = false,
    onClick: (() -> Unit)? = null
) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .then(if (onClick != null) Modifier.pressable(onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, style = TextStyle(fontSize = 15.sp, color = color, fontWeight = if (onClick != null) FontWeight.SemiBold else FontWeight.Normal), modifier = Modifier.weight(1f))
        if (value != null) Text(value, style = TextStyle(fontSize = 15.sp, color = MyohmColor.muted))
        if (chevron) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MyohmColor.muted)
    }
}
