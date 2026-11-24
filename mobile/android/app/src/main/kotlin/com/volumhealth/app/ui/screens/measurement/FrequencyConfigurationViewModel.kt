package com.volumhealth.app.ui.screens.measurement

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.volumhealth.core.ble.ConnectionState
import com.volumhealth.core.ble.SweepConfiguration
import com.volumhealth.core.ble.BioMessBleManager
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

internal const val MIN_START_FREQ = 1_000f
internal const val MAX_START_FREQ = 50_000f
internal const val MIN_STOP_FREQ = 50_000f
internal const val MAX_STOP_FREQ = 200_000f
internal const val MIN_POINT_COUNT = 16
internal const val MAX_POINT_COUNT = 100
internal const val MIN_REPETITIONS = 1
internal const val MAX_REPETITIONS = 10
private const val MIN_GAP_HZ = 1_000f

@HiltViewModel
class FrequencyConfigurationViewModel @Inject constructor(
    private val bleManager: BioMessBleManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(FrequencyConfigurationUiState())
    val uiState: StateFlow<FrequencyConfigurationUiState> = _uiState.asStateFlow()

    val connectionState: StateFlow<ConnectionState> = bleManager.connectionState

    fun refreshConfiguration() {
        viewModelScope.launch {
            _uiState.update { it.copy(statusMessage = "Reading configuration…") }
            runCatching { bleManager.readSweepConfiguration() }
                .onSuccess { applyDeviceConfig(it) }
                .onFailure { error ->
                    _uiState.update { state ->
                        state.copy(statusMessage = error.message ?: "Unable to read configuration")
                    }
                }
        }
    }

    private fun applyDeviceConfig(config: SweepConfiguration) {
        _uiState.update {
            it.copy(
                startFrequency = config.startFrequency,
                stopFrequency = config.stopFrequency,
                points = config.points,
                repetitions = config.repetitions,
                statusMessage = "Configuration synced from device"
            ).withPreset()
        }
    }

    fun setStartFrequency(value: Float) {
        _uiState.update { state ->
            val upperBound = (state.stopFrequency - MIN_GAP_HZ).coerceAtLeast(MIN_START_FREQ)
            val clamped = value.coerceIn(MIN_START_FREQ, upperBound)
            state.copy(startFrequency = clamped, statusMessage = null).withPreset()
        }
    }

    fun setStopFrequency(value: Float) {
        _uiState.update { state ->
            val lowerBound = (state.startFrequency + MIN_GAP_HZ).coerceAtMost(MAX_STOP_FREQ)
            val clamped = value.coerceIn(lowerBound, MAX_STOP_FREQ)
            state.copy(stopFrequency = clamped, statusMessage = null).withPreset()
        }
    }

    fun setPoints(value: Int) {
        _uiState.update { state ->
            val clamped = value.coerceIn(MIN_POINT_COUNT, MAX_POINT_COUNT)
            state.copy(points = clamped, statusMessage = null).withPreset()
        }
    }

    fun setRepetitions(value: Int) {
        _uiState.update { state ->
            val clamped = value.coerceIn(MIN_REPETITIONS, MAX_REPETITIONS)
            state.copy(repetitions = clamped, statusMessage = null).withPreset()
        }
    }

    fun applyPreset(preset: FrequencyPreset) {
        _uiState.update {
            it.copy(
                startFrequency = preset.startHz,
                stopFrequency = preset.stopHz,
                points = preset.points,
                repetitions = preset.repetitions,
                selectedPreset = preset,
                statusMessage = "Preset “${preset.title}” applied"
            )
        }
    }

    fun applyConfiguration() {
        val current = _uiState.value
        if (current.isApplying) return
        viewModelScope.launch {
            _uiState.update { it.copy(isApplying = true, statusMessage = "Applying configuration…") }
            runCatching {
                bleManager.configureSweepStartFreq(current.startFrequency)
                bleManager.configureSweepStopFreq(current.stopFrequency)
                bleManager.configureSweepPoints(current.points)
                bleManager.configureRepetitions(current.repetitions)
            }.onSuccess {
                _uiState.update { it.copy(isApplying = false, statusMessage = "Configuration applied") }
            }.onFailure { error ->
                _uiState.update {
                    it.copy(isApplying = false, statusMessage = error.message ?: "Failed to apply configuration")
                }
            }
        }
    }

    private fun FrequencyConfigurationUiState.withPreset(): FrequencyConfigurationUiState {
        val preset = FrequencyPreset.detect(startFrequency, stopFrequency, points, repetitions)
        return copy(selectedPreset = preset)
    }
}

data class FrequencyConfigurationUiState(
    val startFrequency: Float = 4_000f,
    val stopFrequency: Float = 198_000f,
    val points: Int = 48,
    val repetitions: Int = 5,
    val selectedPreset: FrequencyPreset? = FrequencyPreset.STANDARD,
    val isApplying: Boolean = false,
    val statusMessage: String? = null
) {
    val totalPoints: Int get() = points * repetitions

    val estimatedDurationText: String
        get() {
            val seconds = totalPoints * 0.05
            return if (seconds < 60) {
                "~${seconds.roundToInt()} sec"
            } else {
                val minutes = seconds / 60.0
                val wholeMinutes = minutes.toInt()
                val remainingSeconds = ((minutes - wholeMinutes) * 60).roundToInt()
                "${wholeMinutes} min ${remainingSeconds} sec"
            }
        }

    val repetitionQuality: String
        get() = when (repetitions) {
            1 -> "Fast"
            2, 3 -> "Standard"
            in 4..6 -> "High Quality"
            else -> "Maximum Quality"
        }

    val repetitionDescription: String
        get() = when (repetitions) {
            1 -> "Quick measurement, minimal filtering"
            2, 3 -> "Balanced speed and accuracy"
            in 4..6 -> "Advanced noise filtering"
            else -> "Best signal-to-noise ratio"
        }

    val rangeDescription: String
        get() = "${formatFrequency(startFrequency)} → ${formatFrequency(stopFrequency)}"

    private fun formatFrequency(value: Float): String {
        return if (value >= 1_000f) String.format("%.1f kHz", value / 1_000f) else "${value.roundToInt()} Hz"
    }
}

enum class FrequencyPreset(
    val title: String,
    val description: String,
    val startHz: Float,
    val stopHz: Float,
    val points: Int,
    val repetitions: Int
) {
    FAST(
        title = "Rápido",
        description = "Escaneo rápido",
        startHz = 4_000f,
        stopHz = 150_000f,
        points = 24,
        repetitions = 1
    ),
    STANDARD(
        title = "Estándar",
        description = "Recomendado",
        startHz = 4_000f,
        stopHz = 198_000f,
        points = 48,
        repetitions = 5
    ),
    QUALITY(
        title = "Calidad",
        description = "Alta precisión",
        startHz = 4_000f,
        stopHz = 198_000f,
        points = 48,
        repetitions = 5
    ),
    MAXIMUM(
        title = "Máximo",
        description = "Mejor precisión",
        startHz = 4_000f,
        stopHz = 198_000f,
        points = 48,
        repetitions = 8
    );

    companion object {
        private const val TOLERANCE_HZ = 1_000f

        fun detect(start: Float, stop: Float, points: Int, repetitions: Int): FrequencyPreset? {
            return entries.firstOrNull {
                abs(it.startHz - start) < TOLERANCE_HZ &&
                    abs(it.stopHz - stop) < TOLERANCE_HZ &&
                    it.points == points &&
                    it.repetitions == repetitions
            }
        }
    }
}
