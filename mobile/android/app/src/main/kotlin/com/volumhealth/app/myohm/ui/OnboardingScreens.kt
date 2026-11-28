package com.volumhealth.app.myohm.ui

import android.app.Activity
import android.bluetooth.BluetoothDevice
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bluetooth
import androidx.compose.material.icons.filled.BluetoothSearching
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import com.volumhealth.app.myohm.data.MyohmViewModel
import com.volumhealth.core.ble.ConnectionState
import com.volumhealth.core.model.Athlete
import com.volumhealth.core.model.BiologicalSex
import kotlinx.datetime.Clock
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.minus
import kotlinx.datetime.toLocalDateTime
import androidx.compose.foundation.text.BasicTextField
import com.volumhealth.core.model.SyncStatus

/** Light (white) status bar icons while a dark screen is visible. */
@Composable
fun DarkStatusBar() {
    val view = LocalView.current
    DisposableEffect(Unit) {
        val window = (view.context as? Activity)?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, view) }
        controller?.isAppearanceLightStatusBars = false
        controller?.isAppearanceLightNavigationBars = false
        onDispose {
            controller?.isAppearanceLightStatusBars = true
            controller?.isAppearanceLightNavigationBars = true
        }
    }
}

// MARK: - Welcome

@Composable
fun WelcomeScreen(onConnect: () -> Unit) {
    DarkStatusBar()
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(Color(0xFF0C2C78), MyohmColor.brand, Color(0xFF04103A))))
    ) {
        val density = LocalDensity.current
        val widthDp = maxWidth
        val heightDp = maxHeight
        val logoWidth = minOf(widthDp - 64.dp, 320.dp)
        val scale = logoWidth.value / MyohmLogoGeometry.WIDTH
        val logoHeight = logoWidth * (MyohmLogoGeometry.HEIGHT / MyohmLogoGeometry.WIDTH)
        val logoCenterY = heightDp * 0.40f
        // The o sits 10 canvas units left of the canvas centre.
        val oCenter = with(density) { Offset((widthDp / 2 - (10 * scale).dp).toPx(), logoCenterY.toPx()) }
        val innerRadius = with(density) { (MyohmLogoGeometry.O_RADIUS * scale).dp.toPx() }
        val maxRadius = with(density) { (heightDp * 0.75f).toPx() }

        Canvas(Modifier.fillMaxSize()) {
            drawRect(
                Brush.radialGradient(
                    listOf(MyohmColor.chartBlue.copy(alpha = 0.45f), Color.Transparent),
                    center = oCenter, radius = size.width * 0.8f
                )
            )
        }
        SignalRings(oCenter, innerRadius, maxRadius)

        Column(
            Modifier
                .fillMaxWidth()
                .offset(y = logoCenterY - logoHeight / 2),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            MyohmLogo(width = logoWidth, color = Color.White)
            Spacer(Modifier.height(18.dp))
            // Product descriptor, kept in English in every language.
            OneLineText(
                "BIOIMPEDANCE SPECTROSCOPY",
                maxWidthDp = logoWidth + 24.dp,
                style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 2.6.sp, color = Color.White.copy(alpha = 0.72f))
            )
        }

        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp)
                .padding(bottom = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            MyohmPrimaryButton(L("Connect my Myohm"), light = true, onClick = onConnect)
            Text(L("Your data stays on this phone."), style = MyohmText.caption.copy(color = Color.White.copy(alpha = 0.72f)))
        }
    }
}

/** Single-line text that shrinks (down to 70 %) instead of wrapping. */
@Composable
fun OneLineText(text: String, maxWidthDp: androidx.compose.ui.unit.Dp, style: TextStyle) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val maxPx = with(density) { maxWidthDp.roundToPx() }
    fun scaled(f: Float) = style.copy(
        fontSize = style.fontSize * f,
        letterSpacing = if (style.letterSpacing.isSpecified) style.letterSpacing * f else style.letterSpacing
    )
    var factor = 1f
    while (factor > 0.7f) {
        val s = scaled(factor)
        val w = measurer.measure(text, s, maxLines = 1, softWrap = false, constraints = Constraints()).size.width
        if (w <= maxPx) break
        factor -= 0.03f
    }
    Text(
        text,
        style = scaled(factor),
        maxLines = 1, softWrap = false, textAlign = TextAlign.Center
    )
}

/** Concentric rings spreading from the o of the logo, like a signal passing through tissue. */
@Composable
fun SignalRings(center: Offset, innerRadius: Float, maxRadius: Float) {
    val transition = rememberInfiniteTransition(label = "rings")
    val time by transition.animateFloat(
        initialValue = 0f, targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(7_000, easing = LinearEasing), RepeatMode.Restart),
        label = "t"
    )
    Canvas(Modifier.fillMaxSize()) {
        val count = 6
        for (i in 0 until count) {
            val t = (time + i.toFloat() / count) % 1f
            val radius = innerRadius * 1.5f + t * (maxRadius - innerRadius * 1.5f)
            val fade = (1 - t) * minOf(1f, t * 6)
            drawCircle(Color.White.copy(alpha = 0.16f * fade), radius = radius, center = center, style = Stroke(width = 1.2.dp.toPx()))
        }
    }
}

// MARK: - Pairing

@Composable
fun PairingScreen(vm: MyohmViewModel, onBack: () -> Unit, onDone: () -> Unit) {
    val state by vm.connectionState.collectAsState()
    val battery by vm.battery.collectAsState()
    val devices by vm.discoveredDevices.collectAsState()
    var selected by remember { mutableStateOf<String?>(null) }
    val connected = state is ConnectionState.Connected || state is ConnectionState.Measuring

    LaunchedEffect(Unit) { if (!connected) vm.startScan() }
    DisposableEffect(Unit) { onDispose { if (vm.connectionState.value is ConnectionState.Scanning) vm.stopScan() } }
    LaunchedEffect(devices.size) { if (selected == null) selected = devices.firstOrNull()?.address }

    Column(
        Modifier
            .fillMaxSize()
            .background(MyohmColor.background)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        ScreenHeader(null, if (connected) L("Myohm connected") else L("Looking for your Myohm"), back = onBack)
        Text(
            if (connected) L("Ready to measure. From now on the app will connect to it automatically.")
            else L("Turn it on and keep it within a metre. Pick yours; the name matches the label on the device."),
            style = MyohmText.body.copy(color = MyohmColor.muted)
        )
        Radar(connected, Modifier.fillMaxWidth().height(170.dp))

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (connected) {
                Row(
                    Modifier.fillMaxWidth().background(Color.White, RoundedCornerShape(16.dp)).padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(Icons.Filled.CheckCircle, null, tint = MyohmColor.success, modifier = Modifier.size(24.dp))
                    Column {
                        Text(vm.ble.connectedDeviceName ?: vm.pairedDeviceName() ?: "Myohm", style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink))
                        Text(battery?.let { L("Connected · %s", "${it.percentage} %") } ?: L("Connected"), style = MyohmText.caption)
                    }
                }
            }
            devices.filter { !connected || it.address != vm.ble.connectedDeviceAddress }.forEach { device ->
                DeviceRow(device, selected == device.address, state) { selected = device.address }
            }
            if (devices.isEmpty() && !connected) {
                Text(
                    if (state is ConnectionState.Scanning) L("Searching…") else L("No devices found yet."),
                    style = MyohmText.caption, textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp)
                )
            }
        }
        (state as? ConnectionState.Error)?.let { if (!connected) Text(it.message, style = MyohmText.caption.copy(color = MyohmColor.accent)) }

        Spacer(Modifier.weight(1f))

        if (connected) {
            MyohmPrimaryButton(L("Continue"), onClick = onDone)
        } else {
            MyohmPrimaryButton(
                L("Connect"),
                enabled = selected != null && state !is ConnectionState.Connecting
            ) { devices.firstOrNull { it.address == selected }?.let { vm.connect(it) } }
            Row(Modifier.fillMaxWidth()) {
                LinkText(L("Search again")) { vm.startScan() }
                Spacer(Modifier.weight(1f))
                LinkText(L("Set up later"), onClick = onDone)
            }
        }
    }
}

@Composable
fun LinkText(text: String, color: Color = MyohmColor.brand, onClick: () -> Unit) {
    Box(Modifier.heightIn(min = 44.dp).pressable(onClick = onClick).padding(horizontal = 4.dp), contentAlignment = Alignment.Center) {
        Text(text, style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = color))
    }
}

@Composable
private fun Radar(connected: Boolean, modifier: Modifier) {
    val transition = rememberInfiniteTransition(label = "radar")
    val t by transition.animateFloat(0f, 1f, infiniteRepeatable(tween(1_800), RepeatMode.Restart), label = "pulse")
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(170.dp)) {
            for (ring in 0 until 3) {
                drawCircle(MyohmColor.brand.copy(alpha = 0.12f), radius = (30 + ring * 25).dp.toPx(), style = Stroke(1.5.dp.toPx()))
            }
            if (!connected) {
                val r = 80.dp.toPx() * (0.4f + 0.6f * t)
                drawCircle(MyohmColor.brand.copy(alpha = 0.25f * 0.8f * (1 - t)), radius = r, style = Stroke(2.dp.toPx()))
            }
        }
        Box(
            Modifier.size(44.dp).background(if (connected) MyohmColor.success else MyohmColor.brand, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(if (connected) Icons.Filled.Check else Icons.Filled.BluetoothSearching, null, tint = Color.White, modifier = Modifier.size(22.dp))
        }
    }
}

@Composable
@android.annotation.SuppressLint("MissingPermission")
private fun DeviceRow(device: BluetoothDevice, selected: Boolean, state: ConnectionState, onClick: () -> Unit) {
    val name = runCatching { device.name }.getOrNull() ?: "Myohm"
    Row(
        Modifier
            .fillMaxWidth()
            .background(Color.White, RoundedCornerShape(16.dp))
            .border(2.dp, if (selected) MyohmColor.brand else Color.Transparent, RoundedCornerShape(16.dp))
            .pressable(onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(name, style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink))
            Text(
                if (selected && state is ConnectionState.Connecting) L("Connecting…") else L("Nearby"),
                style = MyohmText.caption
            )
        }
        Icon(Icons.Filled.Bluetooth, null, tint = MyohmColor.brand)
    }
}

// MARK: - Person form

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PersonFormScreen(vm: MyohmViewModel, personId: String?, onBack: () -> Unit, onSaved: (Athlete) -> Unit) {
    val people by vm.people.collectAsState()
    val person = remember(people, personId) { personId?.let { id -> people?.firstOrNull { it.id == id } } }
    val today = remember { Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date }

    var name by rememberSaveable { mutableStateOf("") }
    var male by rememberSaveable { mutableStateOf(false) }
    var birthEpochDay by rememberSaveable { mutableStateOf(today.minus(DatePeriod(years = 30)).toEpochDays()) }
    var height by rememberSaveable { mutableStateOf("") }
    var weight by rememberSaveable { mutableStateOf("") }
    var athlete by rememberSaveable { mutableStateOf(false) }
    var loaded by rememberSaveable { mutableStateOf(false) }
    var showDate by remember { mutableStateOf(false) }

    LaunchedEffect(person) {
        if (!loaded && person != null) {
            loaded = true
            name = person.fullName
            male = person.biologicalSex == BiologicalSex.MALE
            birthEpochDay = person.dateOfBirth.toEpochDays()
            athlete = person.isAthlete == true
            person.heightCm?.let { height = MyohmFormat.number(it, if (Math.rint(it) == it) 0 else 1) }
            person.weightKg?.let { weight = MyohmFormat.number(it) }
        }
    }

    val heightValue = height.replace(",", ".").toDoubleOrNull()
    val weightValue = weight.replace(",", ".").toDoubleOrNull()
    val valid = name.isNotBlank() && heightValue != null && heightValue in 50.0..250.0 && weightValue != null && weightValue in 10.0..300.0
    val birth = LocalDate.fromEpochDays(birthEpochDay)

    Column(
        Modifier
            .fillMaxSize()
            .background(MyohmColor.background)
            .statusBarsPadding()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        ScreenHeader(
            kicker = when {
                personId != null -> null
                people.isNullOrEmpty() -> L("Before the first measurement")
                else -> L("New person")
            },
            title = if (personId == null) L("Who are we measuring?") else L("Edit person"),
            back = onBack
        )
        CardColumn(padding = 18.dp, spacing = 14.dp) {
            FormField(L("Name")) {
                FieldInput(name, { name = it }, L("Name and surname"), KeyboardOptions(capitalization = KeyboardCapitalization.Words))
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(L("Biological sex"), style = MyohmText.micro)
                PillSegmented(listOf(false to L("Female"), true to L("Male")), male) { male = it }
                Text(L("Body-composition equations need it."), style = MyohmText.small)
            }
            Row(
                Modifier.fillMaxWidth().heightIn(min = 48.dp).pressable { showDate = true },
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(L("Date of birth"), style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.ink), modifier = Modifier.weight(1f))
                Text(
                    MyohmDates.date(birth),
                    style = TextStyle(fontSize = 15.sp, color = MyohmColor.ink),
                    modifier = Modifier.background(MyohmColor.hairline, RoundedCornerShape(8.dp)).padding(horizontal = 12.dp, vertical = 7.dp)
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                FormField(L("Height"), Modifier.weight(1f)) {
                    FieldInput(height, { height = it }, "170", KeyboardOptions(keyboardType = KeyboardType.Decimal), suffix = "cm")
                }
                FormField(L("Weight"), Modifier.weight(1f)) {
                    FieldInput(weight, { weight = it }, "65", KeyboardOptions(keyboardType = KeyboardType.Decimal), suffix = "kg")
                }
            }
            Row(
                Modifier.fillMaxWidth().pressable(role = androidx.compose.ui.semantics.Role.Switch) { athlete = !athlete },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Column(Modifier.weight(1f)) {
                    Text(L("Athlete"), style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.ink))
                    Text(L("Trains regularly at a competitive level. Uses an athlete-specific equation."), style = MyohmText.small)
                }
                Switch(checked = athlete, onCheckedChange = { athlete = it }, colors = myohmSwitchColors())
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Filled.Lock, null, tint = MyohmColor.muted, modifier = Modifier.size(14.dp))
            Text(L("Data is stored only on this phone."), style = MyohmText.caption)
        }
        MyohmPrimaryButton(if (personId == null) L("Save and continue") else L("Save"), enabled = valid) {
            val base = person ?: Athlete(fullName = name.trim(), dateOfBirth = birth, createdAt = Clock.System.now())
            val updated = base.copy(
                fullName = name.trim(),
                dateOfBirth = birth,
                biologicalSex = if (male) BiologicalSex.MALE else BiologicalSex.FEMALE,
                isAthlete = athlete,
                heightCm = heightValue,
                weightKg = weightValue,
                syncStatus = SyncStatus.PENDING
            )
            vm.savePerson(updated, isNew = person == null, onSaved = onSaved)
        }
    }

    if (showDate) {
        val state = rememberDatePickerState(
            initialSelectedDateMillis = birthEpochDay.toLong() * 86_400_000L,
            selectableDates = object : androidx.compose.material3.SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis <= System.currentTimeMillis()
            }
        )
        DatePickerDialog(
            onDismissRequest = { showDate = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { birthEpochDay = (it / 86_400_000L).toInt() }
                    showDate = false
                }) { Text(L("Done"), color = MyohmColor.brand) }
            },
            dismissButton = { TextButton(onClick = { showDate = false }) { Text(L("Cancel"), color = MyohmColor.brand) } }
        ) {
            DatePicker(state = state, showModeToggle = true)
        }
    }
}

@Composable
fun myohmSwitchColors() = SwitchDefaults.colors(
    checkedThumbColor = Color.White,
    checkedTrackColor = MyohmColor.brand,
    uncheckedThumbColor = Color.White,
    uncheckedTrackColor = MyohmColor.line,
    uncheckedBorderColor = MyohmColor.line
)

@Composable
fun FormField(label: String, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, style = MyohmText.micro)
        content()
    }
}

@Composable
fun FieldInput(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    keyboard: KeyboardOptions = KeyboardOptions.Default,
    suffix: String? = null,
    textStyle: TextStyle = TextStyle(fontSize = 17.sp, color = MyohmColor.ink),
    modifier: Modifier = Modifier.fillMaxWidth()
) {
    BasicTextField(
        value = value,
        onValueChange = onChange,
        singleLine = true,
        keyboardOptions = keyboard,
        textStyle = textStyle,
        cursorBrush = SolidColor(MyohmColor.brand),
        modifier = modifier,
        decorationBox = { inner ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .background(MyohmColor.background, RoundedCornerShape(12.dp))
                    .border(1.dp, MyohmColor.line, RoundedCornerShape(12.dp))
                    .padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(Modifier.weight(1f)) {
                    if (value.isEmpty()) Text(placeholder, style = textStyle.copy(color = MyohmColor.muted.copy(alpha = 0.6f)))
                    inner()
                }
                if (suffix != null) Text(suffix, style = TextStyle(fontSize = 15.sp, color = MyohmColor.muted), modifier = Modifier.padding(start = 6.dp))
            }
        }
    )
}
