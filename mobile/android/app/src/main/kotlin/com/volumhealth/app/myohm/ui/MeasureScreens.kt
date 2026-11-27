package com.volumhealth.app.myohm.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.volumhealth.app.R
import com.volumhealth.app.myohm.data.MyohmViewModel
import com.volumhealth.app.myohm.domain.LimbSide
import com.volumhealth.app.myohm.domain.MeasurementKind
import com.volumhealth.app.myohm.domain.MyohmMuscle
import com.volumhealth.app.myohm.domain.SweepPoint
import com.volumhealth.core.ble.ConnectionState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.ceil

// MARK: - Muscle selection

@Composable
fun MuscleSelectScreen(vm: MyohmViewModel, onBack: () -> Unit, onMeasure: (MeasurementKind) -> Unit) {
    val people by vm.people.collectAsState()
    val selectedId by vm.selectedPersonId.collectAsState()
    val person = people.orEmpty().resolve(selectedId)

    var view by rememberSaveable { mutableStateOf(MyohmMuscle.BodyView.FRONT) }
    var muscle by rememberSaveable { mutableStateOf(MyohmMuscle.QUADRICEPS) }
    var side by rememberSaveable { mutableStateOf(LimbSide.RIGHT) }
    var band by rememberSaveable { mutableIntStateOf(100) }

    fun pick(item: MyohmMuscle, newSide: LimbSide) {
        muscle = item
        side = newSide
        item.suggestedBand?.let { band = it }
        item.view?.let { view = it }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(MyohmColor.background)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        ScreenHeader(person?.let { L("%s · local measurement", it.fullName) }, L("Which muscle?"), back = onBack)

        CardColumn(padding = 14.dp, spacing = 10.dp) {
            PillSegmented(listOf(MyohmMuscle.BodyView.FRONT to L("Front"), MyohmMuscle.BodyView.BACK to L("Back")), view) { view = it }
            Box(Modifier.fillMaxWidth().height(360.dp)) {
                BodyMap(view, muscle, side, Modifier.fillMaxSize()) { m, s -> pick(m, s) }
                Row(Modifier.fillMaxWidth().padding(6.dp)) {
                    val small = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.muted)
                    Text(if (view == MyohmMuscle.BodyView.FRONT) L("RIGHT") else L("LEFT"), style = small)
                    Spacer(Modifier.weight(1f))
                    Text(if (view == MyohmMuscle.BodyView.FRONT) L("LEFT") else L("RIGHT"), style = small)
                }
            }
            val sides = if (view == MyohmMuscle.BodyView.FRONT) listOf(LimbSide.RIGHT, LimbSide.LEFT) else listOf(LimbSide.LEFT, LimbSide.RIGHT)
            PillSegmented(sides.map { it to it.displayName }, side) { side = it }
        }

        FlowChips {
            MyohmMuscle.entries.forEach { item ->
                ChipButton(if (item == MyohmMuscle.OTHER) L("Other…") else item.displayName, muscle == item) { pick(item, side) }
            }
        }

        CardColumn {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(L("Band"), style = MyohmText.headline, modifier = Modifier.weight(1f))
                Text(L("Distance between V+ and V−"), style = MyohmText.small)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(50, 75, 100, 150).forEach { mm ->
                    val selected = band == mm
                    Column(
                        Modifier
                            .weight(1f)
                            .heightIn(min = 72.dp)
                            .background(if (selected) MyohmColor.brand else MyohmColor.background, RoundedCornerShape(16.dp))
                            .semantics { contentDescription = L("%s millimetre band", mm.toString()) }
                            .pressable { band = mm }
                            .padding(vertical = 10.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        val c = if (selected) Color.White else MyohmColor.ink
                        Text("$mm", style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c))
                        Text("mm", style = TextStyle(fontSize = 11.sp, color = c.copy(alpha = 0.8f)))
                        if (muscle.suggestedBand == mm) {
                            Text(L("Suggested"), style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = c), modifier = Modifier.padding(top = 2.dp), maxLines = 1)
                        }
                    }
                }
            }
            Text(
                if (muscle == MyohmMuscle.OTHER) L("Choose the band that covers the muscle belly without reaching the tendon.")
                else L("Centre the band on the muscle belly. Always use the same band on this muscle to compare measurements."),
                style = MyohmText.caption
            )
        }

        MyohmPrimaryButton(
            if (muscle == MyohmMuscle.OTHER) L("Measure")
            else L("Measure · %s %s", muscle.displayName.lowercase(MyohmLocale.locale), side.displayName.lowercase(MyohmLocale.locale))
        ) { onMeasure(MeasurementKind.Muscle(muscle, side, band)) }
    }
}

private const val CANVAS_W = 520f
private const val CANVAS_H = 1000f

/** Smooth closed outline through the traced points (Catmull–Rom converted to Bézier). */
fun muscleOutlinePath(points: List<Pair<Float, Float>>, scale: Float, origin: Offset): Path {
    val path = Path()
    val p = points.map { Offset(origin.x + it.first * scale, origin.y + it.second * scale) }
    if (p.size < 3) return path
    path.moveTo(p[0].x, p[0].y)
    for (i in p.indices) {
        val p0 = p[(i - 1 + p.size) % p.size]; val p1 = p[i]; val p2 = p[(i + 1) % p.size]; val p3 = p[(i + 2) % p.size]
        path.cubicTo(
            p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6,
            p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6,
            p2.x, p2.y
        )
    }
    path.close()
    return path
}

private fun insidePolygon(x: Float, y: Float, poly: List<Pair<Float, Float>>): Boolean {
    var inside = false
    var j = poly.size - 1
    for (i in poly.indices) {
        val (xi, yi) = poly[i]; val (xj, yj) = poly[j]
        if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside
        j = i
    }
    return inside
}

/** Anatomical illustration with tappable muscle zones. */
@Composable
fun BodyMap(
    view: MyohmMuscle.BodyView,
    muscle: MyohmMuscle,
    side: LimbSide,
    modifier: Modifier = Modifier,
    onTap: (MyohmMuscle, LimbSide) -> Unit
) {
    val zones = MyohmMuscle.entries.filter { it.view == view }
    BoxWithConstraints(modifier, contentAlignment = Alignment.Center) {
        val density = LocalDensity.current
        val wPx = with(density) { maxWidth.toPx() }
        val hPx = with(density) { maxHeight.toPx() }
        val scale = minOf(wPx / CANVAS_W, hPx / CANVAS_H)
        val origin = Offset((wPx - CANVAS_W * scale) / 2, (hPx - CANVAS_H * scale) / 2)
        Image(
            painterResource(if (view == MyohmMuscle.BodyView.FRONT) R.drawable.myohm_body_front else R.drawable.myohm_body_back),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize()
        )
        Canvas(
            Modifier
                .fillMaxSize()
                .pointerInput(view, scale) {
                    detectTapGestures { tap ->
                        val x = (tap.x - origin.x) / scale
                        val y = (tap.y - origin.y) / scale
                        // A small tolerance makes thin zones (tibialis, forearm) easy to hit.
                        val hit = zones.firstNotNullOfOrNull { m ->
                            m.outlines.indexOfFirst { insidePolygon(x, y, it) }.takeIf { it >= 0 }?.let { m to it }
                        } ?: zones.firstNotNullOfOrNull { m ->
                            m.outlines.indexOfFirst { poly -> listOf(-8f to 0f, 8f to 0f, 0f to -8f, 0f to 8f).any { (dx, dy) -> insidePolygon(x + dx, y + dy, poly) } }
                                .takeIf { it >= 0 }?.let { m to it }
                        }
                        hit?.let { (m, index) -> onTap(m, if (index == 0) LimbSide.RIGHT else LimbSide.LEFT) }
                    }
                }
        ) {
            zones.forEach { m ->
                m.outlines.forEachIndexed { index, outline ->
                    val selected = m == muscle && (if (index == 0) LimbSide.RIGHT else LimbSide.LEFT) == side
                    val path = muscleOutlinePath(outline, scale, origin)
                    drawPath(path, if (selected) MyohmColor.brand.copy(alpha = 0.55f) else MyohmColor.chartBlue.copy(alpha = 0.12f))
                    drawPath(
                        path,
                        if (selected) Color.White else MyohmColor.chartBlue.copy(alpha = 0.35f),
                        style = Stroke(width = (if (selected) 2 else 1).dp.toPx())
                    )
                }
            }
        }
    }
}

// MARK: - Whole-body placement

@Composable
fun PlacementScreen(vm: MyohmViewModel, onBack: () -> Unit, onStart: (MeasurementKind) -> Unit) {
    val people by vm.people.collectAsState()
    val selectedId by vm.selectedPersonId.collectAsState()
    val person = people.orEmpty().resolve(selectedId)

    var weight by rememberSaveable { mutableStateOf(person?.weightKg?.let { MyohmFormat.number(it) } ?: "") }
    var supine by rememberSaveable { mutableStateOf(false) }
    var noMetal by rememberSaveable { mutableStateOf(false) }
    var fasted by rememberSaveable { mutableStateOf(false) }
    val restStart = rememberSaveable { System.currentTimeMillis() }
    var now by remember { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(1_000); now = System.currentTimeMillis() } }

    val restSeconds = 5 * 60.0
    val remaining = maxOf(0.0, restSeconds - (now - restStart) / 1000.0)
    val weightValue = weight.replace(",", ".").toDoubleOrNull()?.takeIf { it in 10.0..300.0 }

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
        ScreenHeader(person?.let { L("%s · whole body", it.fullName) }, L("Attach the cables"), back = onBack)

        CardColumn {
            ElectrodeDiagram(
                Modifier
                    .fillMaxWidth()
                    .aspectRatio(1536f / 1100f)
                    .clip(RoundedCornerShape(16.dp))
                    .border(1.dp, MyohmColor.hairline, RoundedCornerShape(16.dp))
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Legend(MyohmColor.brand, L("Current (I)"), L("Back of the hand and base of the toes"), Modifier.weight(1f))
                Legend(MyohmColor.accent, L("Sensing (V)"), L("Wrist and ankle, between the bones"), Modifier.weight(1f))
            }
            Text(L("Leave at least 5 cm between the electrodes of each pair."), style = MyohmText.caption)
        }

        Column(Modifier.myohmCard(16.dp)) {
            Text(L("Before measuring"), style = MyohmText.headline, modifier = Modifier.padding(top = 6.dp, bottom = 2.dp))
            Box(Modifier.pressable { supine = !supine }) { CheckRow(L("Lying on the back, arms and legs apart"), supine) }
            HairlineDivider()
            CheckRow(L("5 minutes of rest"), remaining == 0.0, if (remaining > 0) clock(remaining) else null)
            HairlineDivider()
            Box(Modifier.pressable { noMetal = !noMetal }) { CheckRow(L("No metal objects, not touching a metal frame"), noMetal) }
            HairlineDivider()
            Box(Modifier.pressable { fasted = !fasted }) { CheckRow(L("No hard exercise or large meal in the last hours, empty bladder"), fasted) }
        }

        Row(Modifier.myohmCard(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f)) {
                Text(L("Today's weight"), style = MyohmText.headline)
                person?.weightKg?.let { Text(L("Last time: %s", MyohmFormat.kg(it)), style = MyohmText.caption) }
            }
            FieldInput(
                weight, { weight = it }, "0",
                KeyboardOptions(keyboardType = KeyboardType.Decimal),
                textStyle = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink, textAlign = TextAlign.End),
                modifier = Modifier.width(100.dp)
            )
            Text("kg", style = TextStyle(fontSize = 15.sp, color = MyohmColor.muted))
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            MyohmPrimaryButton(L("Start measurement"), enabled = weightValue != null) {
                weightValue?.let { onStart(MeasurementKind.WholeBody(it, remaining == 0.0)) }
            }
            Text(
                L("You can start earlier; the measurement will be marked as incomplete rest."),
                style = MyohmText.caption, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

private fun clock(seconds: Double): String {
    val s = ceil(seconds).toInt()
    return "%d:%02d".format(s / 60, s % 60)
}

@Composable
private fun Legend(color: Color, title: String, text: String, modifier: Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.padding(top = 3.dp).size(12.dp).background(color, CircleShape))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink))
            Text(text, style = MyohmText.caption)
        }
    }
}

/** Right hand and right foot with the four electrode positions. */
@Composable
fun ElectrodeDiagram(modifier: Modifier) {
    val label = L("Right hand and foot seen from above: current electrodes on the back of the hand and the base of the toes; sensing electrodes on the wrist and the ankle.")
    BoxWithConstraints(modifier.background(Color.White).semantics { contentDescription = label }) {
        val density = LocalDensity.current
        val wPx = with(density) { maxWidth.toPx() }
        val s = wPx / 1536f
        fun at(x: Float, y: Float) = with(density) { Offset(x * s, y * s) }
        Image(
            painterResource(R.drawable.myohm_limbs), null,
            contentScale = ContentScale.FillWidth,
            modifier = Modifier.fillMaxWidth().aspectRatio(1536f / 1024f)
        )
        Canvas(Modifier.fillMaxSize()) {
            val dash = PathEffect.dashPathEffect(floatArrayOf(1f, 4.dp.toPx()))
            listOf(Pair(at(432f, 455f), at(432f, 745f)), Pair(at(1102f, 375f), at(1102f, 695f))).forEach { (a, b) ->
                drawLine(MyohmColor.muted, a, b, strokeWidth = 1.2.dp.toPx(), cap = StrokeCap.Round, pathEffect = dash)
            }
            listOf(Triple(432f, 405f, true), Triple(432f, 790f, false), Triple(1102f, 330f, true), Triple(1102f, 740f, false)).forEach { (x, y, current) ->
                val c = if (current) MyohmColor.brand else MyohmColor.accent
                drawCircle(c.copy(alpha = 0.18f), radius = 58f * s, center = at(x, y))
                drawCircle(c, radius = 40f * s, center = at(x, y))
                drawCircle(Color.White, radius = 40f * s, center = at(x, y), style = Stroke(2.dp.toPx()))
            }
        }
        @Composable
        fun Label(text: String, x: Float, y: Float, style: TextStyle) {
            val w = with(density) { 200.dp.toPx() }
            Box(
                Modifier
                    .offset(x = with(density) { (x * s - w / 2).toDp() }, y = with(density) { (y * s - 9.dp.toPx()).toDp() })
                    .width(200.dp),
                contentAlignment = Alignment.Center
            ) { Text(text, style = style, maxLines = 1) }
        }
        val letter = TextStyle(fontSize = with(density) { (46f * s).toSp() }, fontWeight = FontWeight.Bold, color = Color.White)
        Label("I", 432f, 400f, letter); Label("V", 432f, 785f, letter); Label("I", 1102f, 325f, letter); Label("V", 1102f, 735f, letter)
        val note = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.muted)
        Label("≥ 5 cm", 520f, 600f, note); Label("≥ 5 cm", 1190f, 535f, note)
        val caption = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink)
        Label(L("Right hand"), 432f, 1066f, caption); Label(L("Right foot"), 1102f, 1066f, caption)
    }
}

// MARK: - Measuring

@Composable
fun MeasuringScreen(vm: MyohmViewModel, kind: MeasurementKind, onCancel: () -> Unit, onFinished: (String) -> Unit) {
    val people by vm.people.collectAsState()
    val selectedId by vm.selectedPersonId.collectAsState()
    val person = people.orEmpty().resolve(selectedId)
    val state by vm.connectionState.collectAsState()
    val deviceReady by vm.isDeviceReady.collectAsState()
    val progress by vm.liveProgress.collectAsState()
    val livePoints by vm.livePoints.collectAsState()
    val scope = rememberCoroutineScope()
    var job by remember { mutableStateOf<Job?>(null) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var started by remember { mutableStateOf(false) }
    var finished by remember { mutableStateOf(false) }

    val ready = (state is ConnectionState.Connected || state is ConnectionState.Measuring) && deviceReady

    fun start(force: Boolean) {
        if (!ready || !(force || !started)) return
        started = true
        errorText = null
        job = scope.launch {
            try {
                val id = vm.measure(kind, person?.id)
                finished = true
                onFinished(id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errorText = L("The measurement failed: %s", e.message ?: e.javaClass.simpleName)
            }
        }
    }
    LaunchedEffect(ready) { if (ready) start(false) }

    val subtitle = when (kind) {
        is MeasurementKind.Muscle -> L("%s %s · band %s mm", kind.muscle.displayName, kind.side.displayName.lowercase(MyohmLocale.locale), kind.band.toString())
        is MeasurementKind.WholeBody -> L("Whole body · right side")
    }
    val measuring = state is ConnectionState.Measuring
    val shownProgress = if (started) progress else 0.0
    val status = when {
        errorText != null -> L("Stopped")
        measuring -> if (progress > 0) L("Sweep 4–198 kHz") else L("Starting the sweep…")
        started && progress >= 1.0 -> L("Saving…")
        ready -> L("Preparing…")
        else -> L("Not connected")
    }
    val waiting = shownProgress == 0.0 && errorText == null

    Column(
        Modifier
            .fillMaxSize()
            .background(MyohmColor.background)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        ScreenHeader(subtitle, L("Measuring"), back = {
            job?.cancel()
            if (vm.connectionState.value is ConnectionState.Measuring) scope.launch { delay(300); vm.reconnect() }
            onCancel()
        }, backIcon = Icons.Filled.Close)

        Spacer(Modifier.weight(1f))

        ProgressRing(shownProgress, waiting, status, Modifier.size(220.dp))

        Column(Modifier.myohmCard(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(L("Phase angle · live"), style = MyohmText.micro)
            if (livePoints.isEmpty() || !started) {
                Box(Modifier.fillMaxWidth().heightIn(min = 140.dp), contentAlignment = Alignment.Center) {
                    Text(L("The curve will appear as frequencies arrive."), style = MyohmText.caption, textAlign = TextAlign.Center)
                }
            } else {
                SpectrumChart(
                    points = livePoints.map { SweepPoint(it.frequency.toDouble(), it.magnitude.toDouble(), abs(it.phase.toDouble())) },
                    previous = emptyList(),
                    phase = true,
                    selected = null,
                    onSelect = null,
                    modifier = Modifier.fillMaxWidth().height(140.dp),
                    fill = false
                )
            }
        }

        when {
            errorText != null -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(errorText!!, style = MyohmText.body.copy(color = MyohmColor.accent), textAlign = TextAlign.Center)
                MyohmPrimaryButton(L("Try again")) { start(true) }
            }
            !ready -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(L("Waiting for the device…"), style = MyohmText.body.copy(color = MyohmColor.muted))
                MyohmSecondaryButton(L("Reconnect")) { vm.reconnect() }
            }
            else -> Text(L("Stay still and relaxed until it finishes."), style = MyohmText.body.copy(color = MyohmColor.muted), textAlign = TextAlign.Center)
        }
        Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun ProgressRing(progress: Double, waiting: Boolean, status: String, modifier: Modifier) {
    val animated by animateFloatAsState(progress.toFloat(), tween(300), label = "progress")
    val spin = rememberInfiniteTransition(label = "spin")
    val angle by spin.animateFloat(0f, 360f, infiniteRepeatable(tween(1_400, easing = LinearEasing), RepeatMode.Restart), label = "angle")
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 14.dp.toPx()
            val inset = stroke / 2
            val arcSize = androidx.compose.ui.geometry.Size(size.width - stroke, size.height - stroke)
            val topLeft = Offset(inset, inset)
            drawArc(MyohmColor.brandSoft, 0f, 360f, false, topLeft, arcSize, style = Stroke(stroke))
            if (waiting) {
                drawArc(MyohmColor.brand, angle - 90f, 65f, false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
            } else if (animated > 0f) {
                drawArc(MyohmColor.brand, -90f, 360f * animated, false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("${Math.round(progress * 100)} %", style = MyohmText.display(44))
            Text(status, style = MyohmText.caption, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 24.dp))
        }
    }
}
