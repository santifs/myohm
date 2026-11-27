package com.volumhealth.app.myohm.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.volumhealth.app.myohm.data.MyohmRecord
import com.volumhealth.app.myohm.domain.BodyComposition
import com.volumhealth.app.myohm.domain.BodyInputs
import com.volumhealth.app.myohm.domain.FatEstimate
import com.volumhealth.app.myohm.domain.SweepPoint
import com.volumhealth.core.ble.ConnectionState
import com.volumhealth.core.model.Athlete
import com.volumhealth.core.model.BatteryData
import com.volumhealth.core.model.BiologicalSex
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.periodUntil
import kotlinx.datetime.plus
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.toJavaInstant
import kotlinx.datetime.toLocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

// MARK: - People helpers

val Athlete.initials: String
    get() {
        val letters = fullName.trim().split(" ").filter { it.isNotEmpty() }.take(2).map { it.first().toString() }
        return if (letters.isEmpty()) "?" else letters.joinToString("").uppercase()
    }

val Athlete.firstName: String get() = fullName.trim().split(" ").firstOrNull()?.takeIf { it.isNotEmpty() } ?: fullName

val Athlete.bmiValue: Double?
    get() {
        val h = heightCm ?: return null
        val w = weightKg ?: return null
        return if (h > 0) w / Math.pow(h / 100, 2.0) else null
    }

/** Age in years with a fractional part, consistent with whole calendar years. */
fun Athlete.ageYears(at: Instant = Clock.System.now()): Double {
    val tz = TimeZone.currentSystemDefault()
    val date = at.toLocalDateTime(tz).date
    val years = dateOfBirth.periodUntil(date).years
    val lastBirthday = dateOfBirth.plus(DatePeriod(years = years)).atStartOfDayIn(tz)
    return years + (at - lastBirthday).inWholeSeconds / (365.2425 * 24 * 3600)
}

val Athlete.profileSummary: String
    get() {
        val parts = mutableListOf<String>()
        biologicalSex?.let { parts += if (it == BiologicalSex.MALE) L("Male") else L("Female") }
        parts += L("%s years", age.toString())
        parts += if (isAthlete == true) L("athlete") else L("not an athlete")
        return parts.joinToString(" · ")
    }

// MARK: - Dates

object MyohmDates {
    private val zone: ZoneId get() = ZoneId.systemDefault()
    fun medium(instant: Instant): String =
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(MyohmLocale.locale)
            .format(instant.toJavaInstant().atZone(zone))
    fun mediumWithTime(instant: Instant): String =
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(MyohmLocale.locale)
            .format(instant.toJavaInstant().atZone(zone))
    fun dayMonth(instant: Instant): String =
        DateTimeFormatter.ofPattern("d MMM", MyohmLocale.locale).format(instant.toJavaInstant().atZone(zone)).trimEnd('.')
    fun date(date: LocalDate): String =
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(MyohmLocale.locale)
            .format(java.time.LocalDate.of(date.year, date.monthNumber, date.dayOfMonth))
}

// MARK: - Record helpers

val MyohmRecord.myohmTitle: String
    get() {
        if (isWholeBody) return L("Whole body")
        val muscleName = muscle?.displayName ?: muscleGroup.replaceFirstChar { it.uppercase() }
        val side = bodySide ?: return muscleName
        return L("%s · %s", muscleName, side.displayName.lowercase(MyohmLocale.locale))
    }

object MeasurementValue {
    fun headline(record: MyohmRecord, person: Athlete?): String {
        val ref = record.sweep?.atReference ?: return "—"
        if (record.isWholeBody && person != null) {
            bodyEstimate(record, person, ref)?.let { return MyohmFormat.percent(it.fatPercent) }
        }
        return MyohmFormat.degrees(ref.phaseAngle)
    }

    fun bodyInputs(record: MyohmRecord, person: Athlete, reference: SweepPoint): BodyInputs? {
        val height = person.heightCm ?: return null
        val weight = record.bodyWeightKg ?: person.weightKg ?: return null
        val sex = person.biologicalSex ?: return null
        return BodyInputs(
            heightCm = height, weightKg = weight,
            ageYears = person.ageYears(record.measuredAt),
            isMale = sex == BiologicalSex.MALE, isAthlete = person.isAthlete == true,
            r50 = reference.resistance, xc50 = reference.reactance
        )
    }

    fun bodyEstimate(record: MyohmRecord, person: Athlete, reference: SweepPoint): FatEstimate? =
        bodyInputs(record, person, reference)?.let { BodyComposition.estimate(it) }
}

// MARK: - Logo

/**
 * The Myohm wordmark, drawn from design/myohm/myohm-editable.svg (1440 × 520 canvas,
 * 38-unit monoline stroke). The h is the y rotated 180° around the centre of the o.
 */
object MyohmLogoGeometry {
    const val WIDTH = 1440f
    const val HEIGHT = 520f
    val oCenter = Offset(710f, 260f)
    const val O_RADIUS = 100f

    fun mPath(dx: Float = 0f) = Path().apply {
        moveTo(60f + dx, 360f); lineTo(60f + dx, 230f)
        cubicTo(60f + dx, 191.34f, 91.34f + dx, 160f, 130f + dx, 160f)
        cubicTo(168.66f + dx, 160f, 200f + dx, 191.34f, 200f + dx, 230f)
        lineTo(200f + dx, 360f)
        moveTo(200f + dx, 230f)
        cubicTo(200f + dx, 191.34f, 231.34f + dx, 160f, 270f + dx, 160f)
        cubicTo(308.66f + dx, 160f, 340f + dx, 191.34f, 340f + dx, 230f)
        lineTo(340f + dx, 360f)
    }

    fun yPath() = Path().apply {
        moveTo(415f, 160f); lineTo(415f, 285f)
        cubicTo(415f, 326.42f, 448.58f, 360f, 490f, 360f)
        cubicTo(531.42f, 360f, 565f, 326.42f, 565f, 285f)
        lineTo(565f, 160f)
        moveTo(565f, 285f); lineTo(565f, 470f)
    }
}

@Composable
fun MyohmLogo(width: Dp, color: Color = MyohmColor.brand, modifier: Modifier = Modifier) {
    Canvas(
        modifier = modifier
            .width(width)
            .aspectRatio(MyohmLogoGeometry.WIDTH / MyohmLogoGeometry.HEIGHT)
            .semantics { contentDescription = "Myohm" }
    ) {
        val s = size.width / MyohmLogoGeometry.WIDTH
        val stroke = Stroke(width = 38f, cap = StrokeCap.Butt, join = StrokeJoin.Round)
        withTransform({ scale(s, s, pivot = Offset.Zero) }) {
            drawPath(MyohmLogoGeometry.mPath(), color, style = stroke)
            drawPath(MyohmLogoGeometry.yPath(), color, style = stroke)
            drawCircle(color, radius = MyohmLogoGeometry.O_RADIUS, center = MyohmLogoGeometry.oCenter, style = stroke)
            withTransform({ rotate(180f, pivot = MyohmLogoGeometry.oCenter) }) {
                drawPath(MyohmLogoGeometry.yPath(), color, style = stroke)
            }
            drawPath(MyohmLogoGeometry.mPath(1020f), color, style = stroke)
        }
    }
}

// MARK: - Small components

@Composable
fun Avatar(initials: String, size: Dp = 28.dp, inverted: Boolean = false) {
    Box(
        modifier = Modifier
            .size(size)
            .background(if (inverted) Color.White.copy(alpha = 0.16f) else MyohmColor.brandSoft, CircleShape),
        contentAlignment = Alignment.Center
    ) {
        Text(
            initials,
            style = TextStyle(
                fontSize = (size.value * 0.42f).sp, fontWeight = FontWeight.Bold,
                color = if (inverted) Color.White else MyohmColor.brand
            )
        )
    }
}

fun connectionLabel(state: ConnectionState, battery: BatteryData?, hasPaired: Boolean): Triple<String, Color, Boolean> =
    when (state) {
        is ConnectionState.Connected ->
            if (battery != null) Triple(L("Connected · %s", "${battery.percentage} %"), MyohmColor.success, false)
            else Triple(L("Connected"), MyohmColor.success, false)
        is ConnectionState.Measuring -> Triple(L("Measuring"), MyohmColor.success, true)
        is ConnectionState.Connecting -> Triple(L("Connecting…"), MyohmColor.muted, true)
        is ConnectionState.Scanning -> Triple(L("Looking for Myohm…"), MyohmColor.muted, true)
        is ConnectionState.Error -> Triple(L("Bluetooth unavailable"), MyohmColor.accent, false)
        is ConnectionState.Disconnected ->
            Triple(if (hasPaired) L("Not connected · retry") else L("No device"), MyohmColor.accent, false)
    }

@Composable
fun ConnectionPill(state: ConnectionState, battery: BatteryData?, hasPaired: Boolean, onTap: () -> Unit) {
    val (text, color, busy) = connectionLabel(state, battery, hasPaired)
    Row(
        modifier = Modifier
            .heightIn(min = 36.dp)
            .shadow(0.dp, CircleShape)
            .background(Color.White, CircleShape)
            .border(1.dp, MyohmColor.line, CircleShape)
            .pressable(onClick = onTap)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (busy) {
            CircularProgressIndicator(modifier = Modifier.size(12.dp), strokeWidth = 1.5.dp, color = MyohmColor.muted)
        } else {
            Box(Modifier.size(8.dp).background(color, CircleShape))
        }
        Text(text, style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.ink), maxLines = 1)
    }
}

@Composable
fun CircleIconButton(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .shadow(1.dp, CircleShape, ambientColor = MyohmColor.ink.copy(alpha = 0.08f))
            .background(Color.White, CircleShape)
            .pressable(onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = null, tint = MyohmColor.ink, modifier = Modifier.size(22.dp))
    }
}

@Composable
fun ScreenHeader(
    kicker: String?,
    title: String,
    back: (() -> Unit)? = null,
    backIcon: ImageVector = Icons.AutoMirrored.Filled.ArrowBack,
    trailing: (@Composable () -> Unit)? = null
) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        if (back != null) CircleIconButton(backIcon, L("Back"), back)
        Column(Modifier.weight(1f)) {
            if (kicker != null) Text(kicker, style = MyohmText.caption)
            Text(title, style = MyohmText.title())
        }
        trailing?.invoke()
    }
}

@Composable
fun CheckRow(text: String, done: Boolean, trailing: String? = null) {
    Row(
        modifier = Modifier.padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            modifier = Modifier
                .size(24.dp)
                .then(
                    if (done) Modifier.background(MyohmColor.success, CircleShape)
                    else Modifier.border(2.dp, MyohmColor.ringOff, CircleShape)
                ),
            contentAlignment = Alignment.Center
        ) {
            if (done) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(15.dp))
        }
        Text(text, style = MyohmText.body, modifier = Modifier.weight(1f))
        if (trailing != null) {
            Text(
                trailing,
                style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.brand),
                modifier = Modifier.background(MyohmColor.brandSoft, CircleShape).padding(horizontal = 10.dp, vertical = 6.dp)
            )
        }
    }
}

@Composable
fun HairlineDivider(color: Color = MyohmColor.hairline) {
    Box(Modifier.fillMaxWidth().height(1.dp).background(color))
}

@Composable
fun VSpace(height: Dp) = Spacer(Modifier.height(height))
