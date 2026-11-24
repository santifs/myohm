package com.volumhealth.app.ui.navigation

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Settings
import androidx.compose.ui.graphics.vector.ImageVector
import com.volumhealth.app.R

enum class AppDestination(
    val route: String,
    val icon: ImageVector,
    @StringRes val labelResId: Int
) {
    Laboratory("laboratory", Icons.Filled.Science, R.string.nav_laboratory),
    Subjects("subjects", Icons.Filled.People, R.string.nav_subjects),
    History("history", Icons.Filled.History, R.string.nav_history),
    Settings("settings", Icons.Filled.Settings, R.string.nav_settings);

    companion object {
        val bottomNavItems = listOf(Laboratory, Subjects, History, Settings)
    }
}

/** Non-bottom-nav destinations */
sealed class AppRoute(val route: String) {
    companion object {
        const val SUBJECT_MEASURE_PATTERN = "subjects/{athleteId}/measure"
        const val MEASUREMENT_EXECUTE_PATTERN = "measurement/{sessionId}/execute"
        const val MEASUREMENT_RESULT_PATTERN = "measurement/{sessionId}/result"
        const val HISTORY_DETAIL_PATTERN = "history/detail/{measurementId}"
        const val HISTORY_RAW_PATTERN = "history/raw/{measurementId}"
        const val FREQUENCY_CONFIG = "settings/frequency-config"

        fun subjectMeasure(athleteId: String) = "subjects/$athleteId/measure"
        fun measurementExecute(sessionId: String) = "measurement/$sessionId/execute"
        fun measurementResult(sessionId: String) = "measurement/$sessionId/result"
        fun historyDetail(measurementId: String) = "history/detail/$measurementId"
        fun historyRaw(measurementId: String) = "history/raw/$measurementId"
    }
}
