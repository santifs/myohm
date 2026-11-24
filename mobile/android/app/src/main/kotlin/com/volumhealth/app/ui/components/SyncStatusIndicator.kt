package com.volumhealth.app.ui.components

import androidx.annotation.StringRes
import androidx.compose.animation.core.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.volumhealth.app.R
import com.volumhealth.app.ui.theme.VolumColors
import com.volumhealth.core.model.SyncStatus

@Composable
fun SyncStatusIndicator(
    status: SyncStatus,
    modifier: Modifier = Modifier,
    showLabel: Boolean = true
) {
    val icon = Icons.Default.PhoneAndroid
    val tint = MaterialTheme.colorScheme.onSurfaceVariant
    val rotation = 0f
    val statusLabel = stringResource(R.string.myohm_local)

    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = statusLabel,
            tint = tint,
            modifier = Modifier
                .size(16.dp)
                .rotate(rotation)
        )

        if (showLabel) {
            Text(
                text = statusLabel,
                style = MaterialTheme.typography.labelSmall,
                color = tint
            )
        }
    }
}

@Composable
fun SyncStatusBar(
    isSyncing: Boolean,
    pendingCount: Int,
    lastError: String?,
    onSyncClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (lastError != null) {
                MaterialTheme.colorScheme.errorContainer
            } else {
                MaterialTheme.colorScheme.surfaceVariant
            }
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(modifier = Modifier.weight(1f)) {
                if (lastError != null) {
                    Text(
                        text = stringResource(R.string.sync_error_title),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                    Text(
                        text = lastError,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.7f),
                        maxLines = 1
                    )
                } else if (pendingCount > 0) {
                    Text(
                        text = stringResource(R.string.sync_pending_count, pendingCount),
                        style = MaterialTheme.typography.labelMedium
                    )
                } else {
                    Text(
                        text = stringResource(R.string.sync_all_synced),
                        style = MaterialTheme.typography.labelMedium,
                        color = VolumColors.SystemGreen
                    )
                }
            }

            if (pendingCount > 0 || lastError != null) {
                Button(
                    onClick = onSyncClick,
                    enabled = !isSyncing,
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp)
                ) {
                    if (isSyncing) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary
                        )
                    } else {
                        Text(stringResource(R.string.sync_button))
                    }
                }
            }
        }
    }
}

/**
 * Returns the string resource ID for a [SyncStatus] display name.
 * Can be used outside of @Composable context; resolve with stringResource() in a Composable.
 */
@StringRes
fun syncStatusDisplayNameRes(status: SyncStatus): Int {
    return R.string.myohm_local
}
