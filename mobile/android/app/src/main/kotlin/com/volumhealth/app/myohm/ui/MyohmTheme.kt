package com.volumhealth.app.myohm.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.Locale

object MyohmColor {
    val brand = Color(0xFF092568)
    val brandDeep = Color(0xFF071A4D)
    val brandMid = Color(0xFF1B3C94)
    val brandSoft = Color(0xFFE7ECF8)
    val background = Color(0xFFF4F6FA)
    val card = Color.White
    val ink = Color(0xFF0B1533)
    val muted = Color(0xFF5A6480)
    val line = Color(0xFFDCE1EC)
    val hairline = Color(0xFFEEF1F7)
    val accent = Color(0xFFC4580F)
    val accentSoft = Color(0xFFF2A25C)
    val accentBg = Color(0xFFFDEBDC)
    val accentInk = Color(0xFF8A3C08)
    val success = Color(0xFF1E7A4C)
    val successBg = Color(0xFFE3F2EA)
    val leanOnDark = Color(0xFF9FB4F2)
    val waterOnDark = Color(0xFF6FD3E6)
    val chartBlue = Color(0xFF3E63C9)
    val ringOff = Color(0xFFC9D1E4)
}

object MyohmText {
    fun display(size: Int) = TextStyle(fontSize = size.sp, fontWeight = FontWeight.ExtraBold, color = MyohmColor.ink)
    fun title(size: Int = 22) = TextStyle(fontSize = size.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink)
    val headline = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Bold, color = MyohmColor.ink)
    val body = TextStyle(fontSize = 15.sp, color = MyohmColor.ink, lineHeight = 20.sp)
    val caption = TextStyle(fontSize = 13.sp, color = MyohmColor.muted, lineHeight = 17.sp)
    val micro = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.muted)
    val small = TextStyle(fontSize = 12.sp, color = MyohmColor.muted, lineHeight = 16.sp)
}

// MARK: - Localisation

/** Spanish when the app runs in Spanish; English (the source language) otherwise. */
object MyohmLocale {
    @Volatile var spanish: Boolean = false
    val locale: Locale get() = if (spanish) Locale("es", "ES") else Locale.UK
}

/** Localised string. Keys are the English text, as on iOS; `%s` placeholders take [args]. */
fun L(key: String, vararg args: Any): String {
    val text = if (MyohmLocale.spanish) MyohmSpanish.strings[key] ?: key else key
    return if (args.isEmpty()) text else String.format(MyohmLocale.locale, text, *args)
}

object MyohmFormat {
    fun number(value: Double, digits: Int = 1): String = String.format(MyohmLocale.locale, "%.${digits}f", value)
    fun degrees(value: Double) = number(value) + "°"
    fun percent(value: Double) = number(value) + " %"
    fun kg(value: Double) = number(value) + " kg"
    fun litres(value: Double) = number(value) + " L"
    fun ohms(value: Double) = number(value, 0) + " Ω"
    fun frequency(hz: Double): String {
        val k = hz / 1000
        val digits = if (hz >= 1000 && kotlin.math.abs(k - Math.rint(k)) > 0.05) 1 else 0
        return if (hz >= 1000) number(k, digits) + " kHz" else number(hz, 0) + " Hz"
    }
}

// MARK: - Building blocks

val CardShape = RoundedCornerShape(24.dp)

fun Modifier.myohmCard(padding: Dp = 16.dp, shape: Shape = CardShape): Modifier = this
    .fillMaxWidth()
    .shadow(1.dp, shape, ambientColor = MyohmColor.ink.copy(alpha = 0.06f), spotColor = MyohmColor.ink.copy(alpha = 0.10f))
    .background(MyohmColor.card, shape)
    .padding(padding)

/** Whole-area tap target with a gentle press feedback, like MyohmPlainButton on iOS. */
@Composable
fun Modifier.pressable(
    enabled: Boolean = true,
    role: Role = Role.Button,
    onClick: () -> Unit
): Modifier {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    return this
        .alpha(if (pressed) 0.7f else 1f)
        .clickable(interactionSource = source, indication = null, enabled = enabled, role = role, onClick = onClick)
}

@Composable
fun MyohmPrimaryButton(
    text: String,
    modifier: Modifier = Modifier,
    light: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    Box(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .scale(if (pressed) 0.98f else 1f)
            .alpha(if (!enabled) 0.5f else if (pressed) 0.85f else 1f)
            .clip(CircleShape)
            .background(if (light) Color.White else MyohmColor.brand)
            .clickable(interactionSource = source, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 14.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text,
            style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = if (light) MyohmColor.brand else Color.White),
            textAlign = TextAlign.Center
        )
    }
}

@Composable
fun MyohmSecondaryButton(
    text: String,
    modifier: Modifier = Modifier,
    leading: (@Composable () -> Unit)? = null,
    onClick: () -> Unit
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(CircleShape)
            .background(Color.White)
            .border(1.dp, MyohmColor.line, CircleShape)
            .pressable(onClick = onClick)
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (leading != null) { leading(); Spacer(Modifier.width(8.dp)) }
        Text(text, style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = MyohmColor.ink))
    }
}

/** Segmented control matching the design (white pill on a grey track). */
@Composable
fun <T> PillSegmented(options: List<Pair<T, String>>, selection: T, modifier: Modifier = Modifier, onSelect: (T) -> Unit) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(MyohmColor.hairline, RoundedCornerShape(12.dp))
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        options.forEach { (value, label) ->
            val selected = value == selection
            Box(
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 40.dp)
                    .then(
                        if (selected) Modifier
                            .shadow(2.dp, RoundedCornerShape(10.dp), ambientColor = MyohmColor.ink.copy(alpha = 0.12f))
                            .background(Color.White, RoundedCornerShape(10.dp))
                        else Modifier
                    )
                    .semantics { this.selected = selected }
                    .pressable(role = Role.Tab) { onSelect(value) },
                contentAlignment = Alignment.Center
            ) {
                Text(
                    label,
                    style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = if (selected) MyohmColor.brand else MyohmColor.muted),
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 8.dp)
                )
            }
        }
    }
}

@Composable
fun ChipButton(title: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .defaultMinSize(minHeight = 40.dp)
            .clip(CircleShape)
            .background(if (selected) MyohmColor.brand else Color.White)
            .border(1.dp, if (selected) MyohmColor.brand else MyohmColor.line, CircleShape)
            .semantics { this.selected = selected }
            .pressable { onClick() }
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(title, style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = if (selected) Color.White else MyohmColor.ink))
    }
}

@Composable
fun SectionLabel(text: String) {
    Text(
        text.uppercase(MyohmLocale.locale),
        style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp, color = MyohmColor.muted)
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FlowChips(spacing: Dp = 8.dp, content: @Composable () -> Unit) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(spacing),
        verticalArrangement = Arrangement.spacedBy(spacing)
    ) { content() }
}

@Composable
fun Pill(text: String, color: Color, background: Color, modifier: Modifier = Modifier) {
    Text(
        text,
        style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = color),
        modifier = modifier
            .background(background, CircleShape)
            .padding(horizontal = 10.dp, vertical = 5.dp)
    )
}

@Composable
fun CardColumn(modifier: Modifier = Modifier, padding: Dp = 16.dp, spacing: Dp = 12.dp, content: @Composable () -> Unit) {
    Column(modifier = modifier.myohmCard(padding), verticalArrangement = Arrangement.spacedBy(spacing)) { content() }
}

val ScreenPadding = PaddingValues(20.dp)
