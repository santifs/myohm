package com.volumhealth.app.ui.components

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.volumhealth.app.R
import com.volumhealth.app.ui.theme.VolumColors
import kotlin.math.roundToInt

/**
 * A fatigue slider component with a 0-10 scale.
 * Displays color-coded fatigue level based on the value:
 * - 0-3: Green (low fatigue)
 * - 4-6: Orange (moderate fatigue)
 * - 7-10: Red (high fatigue)
 *
 * @param value Current fatigue value (0-10)
 * @param onValueChange Callback when value changes
 * @param modifier Modifier for the component
 * @param label Optional section title label
 */
@Composable
fun FatigueSlider(
    value: Int,
    onValueChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null
) {
    val fatigueColor = getFatigueColor(value)
    val fatigueDescriptionRes = getFatigueDescriptionRes(value)

    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surface
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Optional section label
            if (label != null) {
                Text(
                    text = label,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                )
            }

            // Value display row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        text = stringResource(R.string.fatigue_level_label),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "$value",
                        style = MaterialTheme.typography.headlineMedium.copy(
                            fontSize = 28.sp,
                            fontWeight = FontWeight.Bold
                        ),
                        color = VolumColors.BrandPrimary
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = stringResource(R.string.fatigue_max_value),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                    )
                }

                // Fatigue description badge
                Surface(
                    shape = RoundedCornerShape(50),
                    color = fatigueColor
                ) {
                    Text(
                        text = stringResource(fatigueDescriptionRes),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Medium,
                        color = Color.White,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp)
                    )
                }
            }

            // Slider
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Slider(
                    value = value.toFloat(),
                    onValueChange = { onValueChange(it.roundToInt()) },
                    valueRange = 0f..10f,
                    steps = 9, // 9 steps creates 10 intervals (0-10)
                    colors = SliderDefaults.colors(
                        thumbColor = VolumColors.BrandPrimary,
                        activeTrackColor = VolumColors.BrandPrimary,
                        inactiveTrackColor = VolumColors.BrandPrimary.copy(alpha = 0.3f)
                    ),
                    modifier = Modifier.fillMaxWidth()
                )

                // Numeric labels at key points
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "0",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                    )
                    Text(
                        text = "5",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                    )
                    Text(
                        text = "10",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                    )
                }

                // Descriptive labels
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = stringResource(R.string.fatigue_rested),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                    )
                    Text(
                        text = stringResource(R.string.fatigue_moderate_short),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                    )
                    Text(
                        text = stringResource(R.string.fatigue_exhausted),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                    )
                }
            }
        }
    }
}

/**
 * Returns the color for the fatigue badge based on the value.
 * - 0-3: Green (low fatigue)
 * - 4-6: Orange (moderate fatigue)
 * - 7-10: Red (high fatigue)
 */
private fun getFatigueColor(value: Int): Color {
    return when (value) {
        in 0..3 -> VolumColors.SystemGreen
        in 4..6 -> VolumColors.SystemOrange
        else -> VolumColors.SystemRed
    }
}

/**
 * Returns the string resource ID for the fatigue level description.
 * Can be used outside of @Composable context; resolve with stringResource() in a Composable.
 */
@StringRes
fun getFatigueDescriptionRes(value: Int): Int {
    return when (value) {
        0 -> R.string.fatigue_none
        in 1..3 -> R.string.fatigue_mild
        in 4..6 -> R.string.fatigue_moderate
        in 7..9 -> R.string.fatigue_high
        10 -> R.string.fatigue_extreme
        else -> R.string.fatigue_unknown
    }
}

/**
 * A more compact version of the fatigue slider for inline use.
 */
@Composable
fun CompactFatigueSlider(
    value: Int,
    onValueChange: (Int) -> Unit,
    label: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = stringResource(R.string.fatigue_value_format, value),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = VolumColors.BrandPrimary
            )
        }

        Slider(
            value = value.toFloat(),
            onValueChange = { onValueChange(it.roundToInt()) },
            valueRange = 0f..10f,
            steps = 9,
            colors = SliderDefaults.colors(
                thumbColor = VolumColors.BrandPrimary,
                activeTrackColor = VolumColors.BrandPrimary,
                inactiveTrackColor = VolumColors.BrandPrimary.copy(alpha = 0.3f)
            ),
            modifier = Modifier.fillMaxWidth()
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun FatigueSliderPreview() {
    Column(
        modifier = Modifier.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        FatigueSlider(
            value = 0,
            onValueChange = {},
            label = "Fatiga general"
        )
        FatigueSlider(
            value = 5,
            onValueChange = {},
            label = "Fatiga muscular"
        )
        FatigueSlider(
            value = 10,
            onValueChange = {}
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun CompactFatigueSliderPreview() {
    Column(
        modifier = Modifier.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        CompactFatigueSlider(
            value = 3,
            onValueChange = {},
            label = "Cuadriceps derecho"
        )
        CompactFatigueSlider(
            value = 7,
            onValueChange = {},
            label = "Cuadriceps izquierdo"
        )
    }
}
