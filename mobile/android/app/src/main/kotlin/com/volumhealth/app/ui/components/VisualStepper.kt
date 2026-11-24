package com.volumhealth.app.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.volumhealth.app.ui.theme.VolumColors
import com.volumhealth.app.ui.theme.VolumHealthTheme
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/**
 * A large numeric display with vertical arrow buttons for adjusting a value.
 *
 * Layout depends on the format string:
 * - **Decimal mode** ("%.1f"): Two columns — integer (±1) and decimal (±0.1) — separated by a comma.
 * - **Integer mode** ("%.0f"): Single vertical column with ±step.
 *
 * Features:
 * - **Tap the number** to enter editing mode (keyboard input).
 * - **Long-press arrows** for accelerating repeat (300ms → 100ms → 50ms).
 * - Supports comma as decimal separator in edit mode.
 * - Clamps value to [range] and rounds to avoid floating-point drift.
 */
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
fun VisualStepper(
    value: Double,
    onValueChange: (Double) -> Unit,
    range: ClosedFloatingPointRange<Double>,
    step: Double = 1.0,
    unit: String = "",
    format: String = "%.0f"
) {
    var isEditing by remember { mutableStateOf(false) }
    var editText by remember { mutableStateOf("") }
    var hasFocused by remember { mutableStateOf(false) }
    val focusRequester = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val scope = rememberCoroutineScope()

    // Long-press acceleration state
    var repeatJob by remember { mutableStateOf<Job?>(null) }
    var repeatStartTime by remember { mutableStateOf(0L) }

    val hasDecimals = format.contains(".1")

    val integerPart = value.toInt()
    val decimalPart = abs(((value * 10).roundToInt() - value.toInt() * 10))

    // Keep latest value/callbacks accessible from gesture detectors without restarting them
    val currentValue by rememberUpdatedState(value)
    val currentOnValueChange by rememberUpdatedState(onValueChange)
    val currentRange by rememberUpdatedState(range)

    DisposableEffect(Unit) {
        onDispose {
            repeatJob?.cancel()
        }
    }

    fun commitEdit() {
        isEditing = false
        focusManager.clearFocus()
        keyboardController?.hide()
        val normalized = editText.replace(",", ".")
        val parsed = normalized.toDoubleOrNull() ?: return
        val clamped = parsed.coerceIn(range.start, range.endInclusive)
        if (hasDecimals) {
            onValueChange((clamped * 10).roundToLong() / 10.0)
        } else {
            val stepsFromLower = ((clamped - range.start) / step).roundToLong()
            val snapped = range.start + stepsFromLower * step
            onValueChange(snapped.coerceIn(range.start, range.endInclusive))
        }
    }

    fun beginEdit() {
        editText = String.format(format, value)
        hasFocused = false
        isEditing = true
    }

    fun applyStep(direction: Double, stepSize: Double) {
        val newValue = ((currentValue + stepSize * direction) * 10).roundToLong() / 10.0
        currentOnValueChange(newValue.coerceIn(currentRange.start, currentRange.endInclusive))
    }

    fun startRepeating(direction: Double, stepSize: Double) {
        repeatJob?.cancel()
        repeatStartTime = System.currentTimeMillis()
        applyStep(direction, stepSize)
        repeatJob = scope.launch {
            while (true) {
                val elapsed = System.currentTimeMillis() - repeatStartTime
                val interval = when {
                    elapsed > 2000 -> 50L
                    elapsed > 1000 -> 100L
                    else -> 300L
                }
                delay(interval)
                applyStep(direction, stepSize)
            }
        }
    }

    fun stopRepeating() {
        repeatJob?.cancel()
        repeatJob = null
    }

    LaunchedEffect(isEditing) {
        if (isEditing) {
            delay(50)
            focusRequester.requestFocus()
            keyboardController?.show()
        }
    }

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.padding(vertical = 16.dp)
    ) {
        if (isEditing) {
            // ── Edit mode ──
            BasicTextField(
                value = editText,
                onValueChange = { editText = it },
                textStyle = TextStyle(
                    fontSize = 48.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurface
                ),
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Decimal,
                    imeAction = ImeAction.Done
                ),
                keyboardActions = KeyboardActions(
                    onDone = { commitEdit() }
                ),
                cursorBrush = SolidColor(VolumColors.BrandPrimary),
                modifier = Modifier
                    .widthIn(min = 80.dp, max = 160.dp)
                    .focusRequester(focusRequester)
                    .onFocusChanged { state ->
                        if (state.isFocused) {
                            hasFocused = true
                        } else if (hasFocused && isEditing) {
                            commitEdit()
                        }
                    }
            )
        } else if (hasDecimals) {
            // ── Decimal mode: two columns ──
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.clickable(
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() }
                ) { beginEdit() }
            ) {
                DigitColumn(
                    displayValue = "$integerPart",
                    canIncrement = value + 1.0 <= range.endInclusive,
                    canDecrement = value - 1.0 >= range.start,
                    stepSize = 1.0,
                    onStep = { dir, sz -> applyStep(dir, sz) },
                    onStartRepeat = { dir, sz -> startRepeating(dir, sz) },
                    onStopRepeat = { stopRepeating() }
                )

                Text(
                    text = ",",
                    style = TextStyle(
                        fontSize = 48.sp,
                        fontWeight = FontWeight.Bold
                    ),
                    color = MaterialTheme.colorScheme.onSurface
                )

                DigitColumn(
                    displayValue = "$decimalPart",
                    canIncrement = value + 0.1 <= range.endInclusive,
                    canDecrement = value - 0.1 >= range.start,
                    stepSize = 0.1,
                    onStep = { dir, sz -> applyStep(dir, sz) },
                    onStartRepeat = { dir, sz -> startRepeating(dir, sz) },
                    onStopRepeat = { stopRepeating() }
                )
            }
        } else {
            // ── Integer mode: single column ──
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.clickable(
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() }
                ) { beginEdit() }
            ) {
                DigitColumn(
                    displayValue = String.format("%.0f", value),
                    canIncrement = value + step <= range.endInclusive,
                    canDecrement = value - step >= range.start,
                    stepSize = step,
                    onStep = { dir, sz -> applyStep(dir, sz) },
                    onStartRepeat = { dir, sz -> startRepeating(dir, sz) },
                    onStopRepeat = { stopRepeating() }
                )
            }
        }

        if (unit.isNotEmpty()) {
            Text(
                text = unit,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(top = 2.dp)
            )
        }
    }
}

@Composable
private fun DigitColumn(
    displayValue: String,
    canIncrement: Boolean,
    canDecrement: Boolean,
    stepSize: Double,
    onStep: (Double, Double) -> Unit,
    onStartRepeat: (Double, Double) -> Unit,
    onStopRepeat: () -> Unit
) {
    val scope = rememberCoroutineScope()

    // Keep latest callbacks/state accessible without restarting pointerInput
    val currentOnStep by rememberUpdatedState(onStep)
    val currentOnStartRepeat by rememberUpdatedState(onStartRepeat)
    val currentOnStopRepeat by rememberUpdatedState(onStopRepeat)
    val currentCanIncrement by rememberUpdatedState(canIncrement)
    val currentCanDecrement by rememberUpdatedState(canDecrement)

    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Up arrow
        Icon(
            imageVector = Icons.Filled.KeyboardArrowUp,
            contentDescription = "Increase",
            tint = if (canIncrement) VolumColors.BrandPrimary else
                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.2f),
            modifier = Modifier
                .size(48.dp)
                .pointerInput(Unit) {
                    detectTapGestures(
                        onTap = {
                            if (currentCanIncrement) currentOnStep(1.0, stepSize)
                        },
                        onLongPress = { /* handled by onPress */ },
                        onPress = {
                            if (!currentCanIncrement) return@detectTapGestures
                            val pressJob = scope.launch {
                                delay(300)
                                currentOnStartRepeat(1.0, stepSize)
                            }
                            tryAwaitRelease()
                            pressJob.cancel()
                            currentOnStopRepeat()
                        }
                    )
                }
        )

        // Value
        AnimatedContent(
            targetState = displayValue,
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            label = "DigitValue"
        ) { text ->
            Text(
                text = text,
                style = TextStyle(
                    fontSize = 48.sp,
                    fontWeight = FontWeight.Bold
                ),
                color = MaterialTheme.colorScheme.onSurface
            )
        }

        // Down arrow
        Icon(
            imageVector = Icons.Filled.KeyboardArrowDown,
            contentDescription = "Decrease",
            tint = if (canDecrement) VolumColors.BrandPrimary else
                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.2f),
            modifier = Modifier
                .size(48.dp)
                .pointerInput(Unit) {
                    detectTapGestures(
                        onTap = {
                            if (currentCanDecrement) currentOnStep(-1.0, stepSize)
                        },
                        onLongPress = { /* handled by onPress */ },
                        onPress = {
                            if (!currentCanDecrement) return@detectTapGestures
                            val pressJob = scope.launch {
                                delay(300)
                                currentOnStartRepeat(-1.0, stepSize)
                            }
                            tryAwaitRelease()
                            pressJob.cancel()
                            currentOnStopRepeat()
                        }
                    )
                }
        )
    }
}

// ── Previews ──

@Preview(showBackground = true)
@Composable
private fun VisualStepperDecimalPreview() {
    VolumHealthTheme {
        var weight by remember { mutableDoubleStateOf(75.5) }
        VisualStepper(
            value = weight,
            onValueChange = { weight = it },
            range = 30.0..200.0,
            step = 0.5,
            unit = "kg",
            format = "%.1f"
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun VisualStepperIntPreview() {
    VolumHealthTheme {
        var height by remember { mutableDoubleStateOf(175.0) }
        VisualStepper(
            value = height,
            onValueChange = { height = it },
            range = 100.0..220.0,
            step = 1.0,
            unit = "cm",
            format = "%.0f"
        )
    }
}
