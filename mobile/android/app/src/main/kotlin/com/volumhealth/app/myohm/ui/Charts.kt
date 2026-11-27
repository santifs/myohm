package com.volumhealth.app.myohm.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.volumhealth.app.myohm.domain.SweepPoint
import kotlinx.datetime.Instant
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

private val axisStyle = TextStyle(fontSize = 10.sp, color = MyohmColor.muted)
private const val F_MIN = 4_000.0
private const val F_MAX = 200_000.0
private val F_TICKS = listOf(5_000.0, 10_000.0, 20_000.0, 50_000.0, 100_000.0, 200_000.0)

/** About four round tick values covering [lo, hi]. */
fun niceTicks(lo: Double, hi: Double, count: Int = 4): List<Double> {
    if (hi <= lo) return listOf(lo)
    val raw = (hi - lo) / count
    val mag = 10.0.pow(floor(log10(raw)))
    val step = listOf(1.0, 2.0, 2.5, 5.0, 10.0).map { it * mag }.first { it >= raw }
    val first = ceil(lo / step) * step
    return generateSequence(first) { it + step }.takeWhile { it <= hi + step * 1e-6 }.toList()
}

private fun DrawScope.label(m: TextMeasurer, text: String, x: Float, y: Float, alignRight: Boolean = false, center: Boolean = false) {
    val layout = m.measure(text, axisStyle)
    val dx = when {
        alignRight -> -layout.size.width.toFloat()
        center -> -layout.size.width / 2f
        else -> 0f
    }
    drawText(layout, topLeft = Offset(x + dx, y - layout.size.height / 2f))
}

/** Phase or modulus against frequency on a log axis, with optional previous series and selection. */
@Composable
fun SpectrumChart(
    points: List<SweepPoint>,
    previous: List<SweepPoint>,
    phase: Boolean,
    selected: SweepPoint?,
    onSelect: ((Double) -> Unit)?,
    modifier: Modifier = Modifier,
    fill: Boolean = true
) {
    val measurer = rememberTextMeasurer()
    fun value(p: SweepPoint) = if (phase) p.phaseAngle else p.magnitude
    val all = (points + previous).map(::value)
    val vMin = all.minOrNull() ?: 0.0
    val vMax = all.maxOrNull() ?: 1.0
    val lo = if (phase) max(0.0, floor(vMin - 1)) else vMin * 0.95
    val hi = if (phase) ceil(vMax + 1) else max(vMax * 1.05, lo + 1)
    val ticks = niceTicks(lo, hi)
    val leftPad = with(LocalDensity.current) { 34.dp.toPx() }
    val bottomPad = with(LocalDensity.current) { 20.dp.toPx() }

    fun xOf(f: Double, w: Float) = leftPad + ((ln(f) - ln(F_MIN)) / (ln(F_MAX) - ln(F_MIN))).toFloat() * (w - leftPad)
    fun fOf(x: Float, w: Float): Double {
        val t = ((x - leftPad) / (w - leftPad)).coerceIn(0f, 1f)
        return kotlin.math.exp(ln(F_MIN) + t * (ln(F_MAX) - ln(F_MIN)))
    }
    fun yOf(v: Double, h: Float) = ((1 - (v - lo) / (hi - lo)) * (h - bottomPad)).toFloat()

    var gestures = Modifier.fillMaxSize()
    if (onSelect != null) {
        gestures = gestures
            .pointerInput(points) {
                detectTapGestures { onSelect(fOf(it.x, size.width.toFloat()).coerceIn(points.first().frequencyHz, points.last().frequencyHz)) }
            }
            .pointerInput(points) {
                detectDragGestures { change, _ ->
                    onSelect(fOf(change.position.x, size.width.toFloat()).coerceIn(points.first().frequencyHz, points.last().frequencyHz))
                }
            }
    }

    Canvas(modifier.then(gestures)) {
        val w = size.width
        val h = size.height
        val plotBottom = h - bottomPad
        ticks.forEach { t ->
            val y = yOf(t, h)
            drawLine(MyohmColor.hairline, Offset(leftPad, y), Offset(w, y), 1.dp.toPx())
            label(measurer, MyohmFormat.number(t, 0) + if (phase) "°" else "", leftPad - 6.dp.toPx(), y, alignRight = true)
        }
        F_TICKS.forEach { f ->
            val x = xOf(f, w)
            drawLine(MyohmColor.hairline, Offset(x, 0f), Offset(x, plotBottom), 1.dp.toPx())
            label(measurer, MyohmFormat.frequency(f), x, plotBottom + 10.dp.toPx(), center = f != 200_000.0, alignRight = f == 200_000.0)
        }

        fun path(series: List<SweepPoint>): Path = Path().apply {
            series.forEachIndexed { i, p ->
                val o = Offset(xOf(p.frequencyHz, w), yOf(value(p), h))
                if (i == 0) moveTo(o.x, o.y) else lineTo(o.x, o.y)
            }
        }
        if (previous.size > 1) {
            drawPath(
                path(previous), MyohmColor.accentSoft,
                style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())))
            )
        }
        if (points.size > 1) {
            val line = path(points)
            if (fill) {
                val area = Path().apply {
                    addPath(line)
                    lineTo(xOf(points.last().frequencyHz, w), plotBottom)
                    lineTo(xOf(points.first().frequencyHz, w), plotBottom)
                    close()
                }
                drawPath(area, Brush.verticalGradient(listOf(MyohmColor.brand.copy(alpha = 0.18f), MyohmColor.brand.copy(alpha = 0f)), endY = plotBottom))
            }
            drawPath(line, MyohmColor.brand, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        } else if (points.size == 1) {
            drawCircle(MyohmColor.brand, 3.dp.toPx(), Offset(xOf(points[0].frequencyHz, w), yOf(value(points[0]), h)))
        }
        selected?.let { s ->
            val x = xOf(s.frequencyHz, w)
            drawLine(MyohmColor.muted.copy(alpha = 0.4f), Offset(x, 0f), Offset(x, plotBottom), 1.dp.toPx())
            drawCircle(Color.White, 6.5.dp.toPx(), Offset(x, yOf(value(s), h)))
            drawCircle(MyohmColor.brand, 5.dp.toPx(), Offset(x, yOf(value(s), h)))
        }
    }
}

/** Reactance against resistance; tapping picks the nearest frequency. */
@Composable
fun NyquistChart(
    points: List<SweepPoint>,
    previous: List<SweepPoint>,
    selected: SweepPoint?,
    onSelect: (Double) -> Unit,
    modifier: Modifier = Modifier
) {
    val measurer = rememberTextMeasurer()
    val rs = (points + previous).map { it.resistance }
    val xs = (points + previous).map { it.reactance }
    val rTicks = niceTicks(rs.minOrNull() ?: 0.0, rs.maxOrNull() ?: 1.0)
    val rLo = min(rs.minOrNull() ?: 0.0, rTicks.first())
    val rHi = max(rs.maxOrNull() ?: 1.0, rTicks.last())
    val xTicks = niceTicks(0.0, (xs.maxOrNull() ?: 1.0) * 1.1)
    val xHi = max((xs.maxOrNull() ?: 1.0) * 1.1, xTicks.last())
    val density = LocalDensity.current
    val leftPad = with(density) { 40.dp.toPx() }
    val bottomPad = with(density) { 34.dp.toPx() }
    val topPad = with(density) { 14.dp.toPx() }

    fun px(r: Double, w: Float) = leftPad + ((r - rLo) / (rHi - rLo)).toFloat() * (w - leftPad - 8f)
    fun py(x: Double, h: Float) = topPad + ((1 - x / xHi) * (h - bottomPad - topPad)).toFloat()

    Canvas(
        modifier.pointerInput(points) {
            detectTapGestures { tap ->
                val w = size.width.toFloat()
                val r = rLo + (tap.x - leftPad) / (w - leftPad - 8f) * (rHi - rLo)
                points.minByOrNull { abs(it.resistance - r) }?.let { onSelect(it.frequencyHz) }
            }
        }
    ) {
        val w = size.width
        val h = size.height
        val plotBottom = h - bottomPad
        xTicks.forEach { t ->
            val y = py(t, h)
            drawLine(MyohmColor.hairline, Offset(leftPad, y), Offset(w, y), 1.dp.toPx())
            label(measurer, MyohmFormat.number(t, 0), leftPad - 6.dp.toPx(), y, alignRight = true)
        }
        rTicks.forEach { t ->
            val x = px(t, w)
            if (x < leftPad - 1 || x > w) return@forEach
            drawLine(MyohmColor.hairline, Offset(x, topPad), Offset(x, plotBottom), 1.dp.toPx())
            label(measurer, MyohmFormat.number(t, 0), x, plotBottom + 9.dp.toPx(), center = true)
        }
        label(measurer, "R (Ω)", (leftPad + w) / 2, h - 7.dp.toPx(), center = true)
        label(measurer, "Xc (Ω)", 0f, topPad - 8.dp.toPx())
        previous.forEach { drawCircle(MyohmColor.accentSoft, 2.5.dp.toPx(), Offset(px(it.resistance, w), py(it.reactance, h))) }
        points.forEach { drawCircle(MyohmColor.brand, 3.dp.toPx(), Offset(px(it.resistance, w), py(it.reactance, h))) }
        selected?.let {
            val o = Offset(px(it.resistance, w), py(it.reactance, h))
            drawCircle(Color.White, 7.5.dp.toPx(), o)
            drawCircle(MyohmColor.accent, 6.dp.toPx(), o)
        }
    }
}

/** Time series with dates on the x axis; tapping or dragging selects the nearest point. */
@Composable
fun TrendChart(
    points: List<Pair<Instant, Double>>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val measurer = rememberTextMeasurer()
    val values = points.map { it.second }
    val lo = floor((values.minOrNull() ?: 0.0) - 1)
    val hi = ceil((values.maxOrNull() ?: 1.0) + 1)
    val ticks = niceTicks(lo, hi)
    val t0 = points.first().first.toEpochMilliseconds().toDouble()
    val t1 = points.last().first.toEpochMilliseconds().toDouble()
    val pad = max((t1 - t0) * 0.06, 86_400_000.0)
    val start = t0 - pad
    val end = t1 + pad
    val density = LocalDensity.current
    val leftPad = with(density) { 30.dp.toPx() }
    val bottomPad = with(density) { 20.dp.toPx() }

    fun xOf(ms: Double, w: Float) = leftPad + ((ms - start) / (end - start)).toFloat() * (w - leftPad)
    fun yOf(v: Double, h: Float) = (8f + (1 - (v - lo) / (hi - lo)) * (h - bottomPad - 8f)).toFloat()
    fun nearest(x: Float, w: Float): Int = points.indices.minBy { abs(xOf(points[it].first.toEpochMilliseconds().toDouble(), w) - x) }

    Canvas(
        modifier
            .pointerInput(points) { detectTapGestures { onSelect(nearest(it.x, size.width.toFloat())) } }
            .pointerInput(points) { detectDragGestures { change, _ -> onSelect(nearest(change.position.x, size.width.toFloat())) } }
    ) {
        val w = size.width
        val h = size.height
        val plotBottom = h - bottomPad
        ticks.forEach { t ->
            val y = yOf(t, h)
            drawLine(MyohmColor.hairline, Offset(leftPad, y), Offset(w, y), 1.dp.toPx())
            label(measurer, MyohmFormat.number(t, 0), leftPad - 6.dp.toPx(), y, alignRight = true)
        }
        // Up to four date labels, evenly spread.
        val labelCount = min(4, points.size)
        for (i in 0 until labelCount) {
            val ms = start + pad + (end - start - 2 * pad) * (if (labelCount == 1) 0.0 else i.toDouble() / (labelCount - 1))
            val x = xOf(ms, w)
            drawLine(MyohmColor.hairline, Offset(x, 8f), Offset(x, plotBottom), 1.dp.toPx())
            label(measurer, MyohmDates.dayMonth(Instant.fromEpochMilliseconds(ms.toLong())), x, plotBottom + 10.dp.toPx(), center = true)
        }
        val offsets = points.map { Offset(xOf(it.first.toEpochMilliseconds().toDouble(), w), yOf(it.second, h)) }
        val line = Path().apply { offsets.forEachIndexed { i, o -> if (i == 0) moveTo(o.x, o.y) else lineTo(o.x, o.y) } }
        val area = Path().apply {
            addPath(line); lineTo(offsets.last().x, plotBottom); lineTo(offsets.first().x, plotBottom); close()
        }
        drawPath(area, Brush.verticalGradient(listOf(MyohmColor.brand.copy(alpha = 0.16f), Color.Transparent), endY = plotBottom))
        drawPath(line, MyohmColor.brand, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        offsets.forEachIndexed { i, o ->
            if (i == selectedIndex) {
                drawLine(MyohmColor.muted.copy(alpha = 0.4f), Offset(o.x, 8f), Offset(o.x, plotBottom), 1.dp.toPx())
                drawCircle(Color.White, 7.dp.toPx(), o)
                drawCircle(MyohmColor.brand, 5.5.dp.toPx(), o)
            } else {
                drawCircle(MyohmColor.brand, 3.5.dp.toPx(), o)
            }
        }
    }
}

@Composable
fun Donut(segments: List<Pair<Double, Color>>, center: String, caption: String, modifier: Modifier = Modifier) {
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val total = segments.sumOf { max(0.0, it.first) }.takeIf { it > 0 } ?: 1.0
            val thickness = size.minDimension * 0.11f
            val inset = thickness / 2
            val arc = Size(size.minDimension - thickness, size.minDimension - thickness)
            val gap = 3f
            var startAngle = -90f
            segments.forEach { (v, c) ->
                val sweep = (max(0.0, v) / total * 360).toFloat()
                drawArc(c, startAngle + gap / 2, max(0f, sweep - gap), false, Offset(inset, inset), arc, style = Stroke(thickness, cap = StrokeCap.Butt))
                startAngle += sweep
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(horizontal = 22.dp)) {
            OneLineTextFit(center, TextStyle(fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = Color.White))
            Text(caption, style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.75f)), textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun OneLineTextFit(text: String, style: TextStyle) {
    BoxWithConstraints { OneLineText(text, maxWidth, style) }
}

/** Where the estimate sits on a 10–45 % scale, with its error band. */
@Composable
fun ErrorBand(value: Double, error: Double, range: ClosedFloatingPointRange<Double> = 10.0..45.0) {
    val measurer = rememberTextMeasurer()
    Canvas(Modifier.fillMaxWidth().height(40.dp)) {
        val w = size.width
        fun x(v: Double) = (w * (v.coerceIn(range.start, range.endInclusive) - range.start) / (range.endInclusive - range.start)).toFloat()
        val cy = 11.dp.toPx()
        drawRoundRect(
            Brush.horizontalGradient(listOf(MyohmColor.leanOnDark.copy(alpha = 0.25f), MyohmColor.accentSoft.copy(alpha = 0.35f))),
            topLeft = Offset(0f, cy - 4.dp.toPx()), size = Size(w, 8.dp.toPx()), cornerRadius = CornerRadius(4.dp.toPx())
        )
        val bandStart = x(value - error)
        val bandWidth = max(8.dp.toPx(), x(value + error) - bandStart)
        drawRoundRect(Color.White.copy(alpha = 0.28f), Offset(bandStart, cy - 8.dp.toPx()), Size(bandWidth, 16.dp.toPx()), CornerRadius(8.dp.toPx()))
        drawCircle(Color.White, 7.dp.toPx(), Offset(x(value), cy))
        drawCircle(MyohmColor.accentSoft, 7.dp.toPx(), Offset(x(value), cy), style = Stroke(3.dp.toPx()))
        val small = TextStyle(fontSize = 10.sp, color = Color.White.copy(alpha = 0.7f))
        val lowLayout = measurer.measure("${range.start.toInt()} %", small)
        drawText(lowLayout, topLeft = Offset(0f, cy + 12.dp.toPx()))
        val highLayout = measurer.measure("${range.endInclusive.toInt()} %", small)
        drawText(highLayout, topLeft = Offset(w - highLayout.size.width, cy + 12.dp.toPx()))
        val mid = measurer.measure(
            MyohmFormat.number(value - error) + " – " + MyohmFormat.percent(value + error),
            TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        )
        val minX = lowLayout.size.width + 8f
        val maxX = w - highLayout.size.width - 8f - mid.size.width
        val mx = if (maxX < minX) (w - mid.size.width) / 2f else (x(value) - mid.size.width / 2f).coerceIn(minX, maxX)
        drawText(mid, topLeft = Offset(mx, cy + 12.dp.toPx()))
    }
}
