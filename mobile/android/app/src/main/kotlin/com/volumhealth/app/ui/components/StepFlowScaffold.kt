package com.volumhealth.app.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Divider
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.volumhealth.app.R
import com.volumhealth.app.ui.theme.VolumColors
import com.volumhealth.app.ui.theme.VolumHealthTheme

/**
 * Configuration for a single step in a [StepFlowScaffold].
 *
 * @param title The large heading displayed for this step.
 * @param subtitle An optional secondary line displayed below the title.
 * @param isOptional If true, a "Skip" text button is shown above the main action button.
 * @param autoAdvance If true, the caller is expected to auto-advance programmatically.
 */
data class StepConfig(
    val title: String,
    val subtitle: String? = null,
    val isOptional: Boolean = false,
    val autoAdvance: Boolean = false
)

/**
 * A generic step-by-step scaffold that mirrors the iOS `StepFlowView`.
 *
 * Layout (top to bottom):
 * 1. **Top bar (fixed)** -- Back arrow (hidden on step 0) + segmented progress capsules
 * 2. **Scrollable area** -- Title, content, and buttons flow together naturally:
 *    - Title + optional subtitle
 *    - Step-specific content (animated slide transitions)
 *    - Optional "Skip" link + primary action button
 *
 * @param steps List of [StepConfig] describing each step.
 * @param currentStep The 0-based index of the active step.
 * @param canProceed Whether the main action button is enabled.
 * @param lastButtonTitle Label for the action button on the final step.
 * @param onBack Called when the user presses back on step 0 (dismiss the flow).
 * @param onStepChange Called to navigate to a different step index.
 * @param onComplete Called when the user taps the action button on the last step.
 * @param onSkip Optional handler for the "Skip" action. If null, skipping simply advances.
 * @param content Composable content for each step index.
 */
@Composable
fun StepFlowScaffold(
    steps: List<StepConfig>,
    currentStep: Int,
    canProceed: Boolean,
    lastButtonTitle: String = stringResource(R.string.step_finish),
    onBack: () -> Unit,
    onStepChange: (Int) -> Unit,
    onComplete: () -> Unit,
    onSkip: (() -> Unit)? = null,
    content: @Composable (stepIndex: Int) -> Unit
) {
    // Track navigation direction for animation
    var previousStep by remember { mutableIntStateOf(currentStep) }
    val navigatingBack = currentStep < previousStep
    previousStep = currentStep

    val isLastStep = currentStep >= steps.count() - 1

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface)
            .imePadding()
    ) {
        // ── Top Bar: Back button + Progress capsules ──
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(top = 8.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Back arrow -- invisible on step 0 to keep layout stable
            IconButton(
                onClick = {
                    if (currentStep > 0) {
                        onStepChange(currentStep - 1)
                    } else {
                        onBack()
                    }
                },
                enabled = currentStep > 0,
                modifier = Modifier.size(32.dp)
            ) {
                Icon(
                    imageVector = Icons.Filled.ArrowBack,
                    contentDescription = stringResource(R.string.step_back),
                    tint = if (currentStep > 0) {
                        VolumColors.BrandPrimary
                    } else {
                        MaterialTheme.colorScheme.surface // invisible
                    }
                )
            }

            // Segmented progress bar
            Row(
                modifier = Modifier.weight(1f),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                steps.forEachIndexed { index, _ ->
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(4.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(
                                if (index <= currentStep) {
                                    VolumColors.BrandPrimary
                                } else {
                                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f)
                                }
                            )
                    )
                }
            }
        }

        // ── Scrollable content area (takes remaining space above button) ──
        val transitionSpec: ContentTransform = if (navigatingBack) {
            (slideInHorizontally { -it } + fadeIn()) togetherWith
                    (slideOutHorizontally { it } + fadeOut())
        } else {
            (slideInHorizontally { it } + fadeIn()) togetherWith
                    (slideOutHorizontally { -it } + fadeOut())
        }

        BoxWithConstraints(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
        ) {
            val containerHeight = maxHeight

            AnimatedContent(
                targetState = currentStep,
                transitionSpec = { transitionSpec },
                label = "StepFlowContent",
                modifier = Modifier.fillMaxSize()
            ) { stepIndex ->
                val config = steps.getOrNull(stepIndex)

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .heightIn(min = containerHeight)
                        .padding(horizontal = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Spacer(modifier = Modifier.height(20.dp))

                    // ── Title Area ──
                    config?.let { cfg ->
                        Column(
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                text = cfg.title,
                                style = MaterialTheme.typography.titleLarge.copy(
                                    fontWeight = FontWeight.Bold
                                ),
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            cfg.subtitle?.let { subtitle ->
                                Text(
                                    text = subtitle,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                                    modifier = Modifier.padding(top = 4.dp)
                                )
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(32.dp))

                    // ── Step Content (centered in available space) ──
                    Box(modifier = Modifier.fillMaxWidth()) {
                        content(stepIndex)
                    }

                    Spacer(modifier = Modifier.height(20.dp))
                }
            }
        }

        // ── Pinned Bottom Area: divider + Skip + Action Button ──
        @Suppress("DEPRECATION")
        Divider(
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
        )

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                .padding(horizontal = 24.dp)
                .padding(top = 16.dp, bottom = 12.dp)
                .navigationBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Optional skip link
            if (steps.getOrNull(currentStep)?.isOptional == true) {
                TextButton(
                    onClick = {
                        if (onSkip != null) {
                            onSkip()
                        } else if (currentStep < steps.count() - 1) {
                            onStepChange(currentStep + 1)
                        }
                    }
                ) {
                    Text(
                        text = stringResource(R.string.step_skip),
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontWeight = FontWeight.Medium
                        ),
                        color = VolumColors.BrandPrimary
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))
            }

            // Primary action button
            Button(
                onClick = {
                    if (isLastStep) {
                        onComplete()
                    } else {
                        onStepChange(currentStep + 1)
                    }
                },
                enabled = canProceed,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = VolumColors.BrandPrimary
                )
            ) {
                Text(
                    text = if (isLastStep) lastButtonTitle else stringResource(R.string.step_next),
                    style = MaterialTheme.typography.bodyLarge.copy(
                        fontWeight = FontWeight.SemiBold
                    )
                )
            }
        }
    }
}

// ── Previews ──

@Preview(showBackground = true)
@Composable
private fun StepFlowScaffoldPreview() {
    VolumHealthTheme {
        var step by remember { mutableIntStateOf(0) }
        StepFlowScaffold(
            steps = listOf(
                StepConfig(title = "Weight", subtitle = "Enter your current weight"),
                StepConfig(title = "Hydration", isOptional = true),
                StepConfig(title = "Summary")
            ),
            currentStep = step,
            canProceed = true,
            lastButtonTitle = "Start",
            onBack = {},
            onStepChange = { step = it },
            onComplete = {}
        ) { stepIndex ->
            when (stepIndex) {
                0 -> Text("Step 1 content")
                1 -> Text("Step 2 content")
                else -> Text("Step 3 content")
            }
        }
    }
}
