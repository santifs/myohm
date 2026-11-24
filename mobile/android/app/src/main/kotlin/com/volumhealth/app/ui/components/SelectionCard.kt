package com.volumhealth.app.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
 * A tappable card for single-selection lists.
 *
 * Shows an icon, a title, and a checkmark when selected.
 * Background highlights to brandPrimary tint when selected; border becomes brandPrimary.
 *
 * Mirrors the iOS `SelectionCard` component.
 *
 * @param title The label to display.
 * @param icon The leading [ImageVector] icon.
 * @param isSelected Whether this card is currently selected.
 * @param onClick Called when the card is tapped.
 */
@Composable
fun SelectionCard(
    title: String,
    icon: ImageVector,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(12.dp),
        color = if (isSelected) {
            VolumColors.BrandPrimary.copy(alpha = 0.1f)
        } else {
            MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        },
        border = BorderStroke(
            width = 2.dp,
            color = if (isSelected) VolumColors.BrandPrimary else Color.Transparent
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Start
        ) {
            // Leading icon
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (isSelected) VolumColors.BrandPrimary else
                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                modifier = Modifier.size(28.dp)
            )

            Spacer(modifier = Modifier.width(12.dp))

            // Title
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge.copy(
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                ),
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f)
            )

            // Trailing checkmark
            AnimatedVisibility(
                visible = isSelected,
                enter = scaleIn() + fadeIn(),
                exit = scaleOut() + fadeOut()
            ) {
                Icon(
                    imageVector = Icons.Filled.CheckCircle,
                    contentDescription = null,
                    tint = VolumColors.BrandPrimary,
                    modifier = Modifier.size(24.dp)
                )
            }
        }
    }
}

// ── Previews ──

@Preview(showBackground = true)
@Composable
private fun SelectionCardSelectedPreview() {
    VolumHealthTheme {
        SelectionCard(
            title = "Cuadriceps",
            icon = Icons.Filled.CheckCircle,
            isSelected = true,
            onClick = {}
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun SelectionCardUnselectedPreview() {
    VolumHealthTheme {
        SelectionCard(
            title = "Biceps",
            icon = Icons.Filled.CheckCircle,
            isSelected = false,
            onClick = {}
        )
    }
}
