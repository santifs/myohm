package com.volumhealth.app.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.volumhealth.app.ui.theme.VolumColors
import com.volumhealth.app.ui.theme.VolumHealthTheme

/**
 * Configuration for a single chip option.
 *
 * @param label The text label displayed in the chip.
 * @param icon An optional leading [ImageVector] icon.
 */
data class ChipOption(
    val label: String,
    val icon: ImageVector? = null
)

/**
 * A horizontal scrollable row of pill-shaped chips for **single selection**.
 *
 * The selected chip is tinted with brandPrimary. Mirrors the iOS `ChipRow`.
 *
 * @param options The available chip options.
 * @param selected The currently selected label.
 * @param onSelect Called when a chip is tapped, with its label.
 */
@Composable
fun ChipRow(
    options: List<ChipOption>,
    selected: String,
    onSelect: (String) -> Unit
) {
    LazyRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        items(options, key = { it.label }) { option ->
            SingleChip(
                option = option,
                isSelected = option.label == selected,
                onClick = { onSelect(option.label) }
            )
        }
    }
}

/**
 * A flow grid of toggleable chips for **multi-selection**.
 *
 * Uses Compose Foundation's [FlowRow] to wrap chips that overflow horizontally.
 * Mirrors the iOS `MultiSelectChipGrid`.
 *
 * @param options The available chip options.
 * @param selected The set of currently selected labels.
 * @param onToggle Called when a chip is tapped, with its label (toggle on/off).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MultiSelectChipGrid(
    options: List<ChipOption>,
    selected: Set<String>,
    onToggle: (String) -> Unit
) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        options.forEach { option ->
            SingleChip(
                option = option,
                isSelected = option.label in selected,
                onClick = { onToggle(option.label) }
            )
        }
    }
}

// ── Internal chip composable ──

@Composable
private fun SingleChip(
    option: ChipOption,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    val backgroundColor = if (isSelected) {
        VolumColors.BrandPrimary.copy(alpha = 0.15f)
    } else {
        MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
    }

    val contentColor = if (isSelected) {
        VolumColors.BrandPrimary
    } else {
        MaterialTheme.colorScheme.onSurface
    }

    val borderColor = if (isSelected) {
        VolumColors.BrandPrimary
    } else {
        Color.Transparent
    }

    Surface(
        modifier = Modifier.clickable(onClick = onClick),
        shape = RoundedCornerShape(50),
        color = backgroundColor,
        border = BorderStroke(1.5.dp, borderColor)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            option.icon?.let { icon ->
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = contentColor,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
            }
            Text(
                text = option.label,
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                ),
                color = contentColor
            )
        }
    }
}

// ── Previews ──

@Preview(showBackground = true)
@Composable
private fun ChipRowPreview() {
    VolumHealthTheme {
        var selected by remember { mutableStateOf("Leve") }
        ChipRow(
            options = listOf(
                ChipOption("Ninguna"),
                ChipOption("Leve"),
                ChipOption("Moderada"),
                ChipOption("Intensa")
            ),
            selected = selected,
            onSelect = { selected = it }
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun MultiSelectChipGridPreview() {
    VolumHealthTheme {
        var selected by remember { mutableStateOf(setOf("Pecho")) }
        MultiSelectChipGrid(
            options = listOf(
                ChipOption("Pecho"),
                ChipOption("Espalda"),
                ChipOption("Hombros"),
                ChipOption("Brazos"),
                ChipOption("Piernas"),
                ChipOption("Core")
            ),
            selected = selected,
            onToggle = { label ->
                selected = if (label in selected) selected - label else selected + label
            }
        )
    }
}
