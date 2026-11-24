package com.volumhealth.app.study

import com.volumhealth.core.model.BodySide
import com.volumhealth.core.model.MuscleGroup

enum class Study(
    val code: String,
    val label: String,
    val muscleGroups: List<MuscleGroup>,
    val sides: List<BodySide>,
    val sessionTypeSuggestions: List<String>
) {
    BICEPS_TFG(
        code = "biceps_tfg",
        label = "Bíceps TFG",
        muscleGroups = listOf(MuscleGroup.BICEPS_BRACHII),
        sides = listOf(BodySide.RIGHT),
        sessionTypeSuggestions = listOf(
            "basal",
            "post_serie_1", "post_serie_2", "post_serie_3", "post_serie_4", "post_serie_5",
            "12h", "24h", "36h", "48h", "60h", "72h"
        )
    ),
    SENTADILLA_TFM(
        code = "sentadilla_tfm",
        label = "Sentadilla TFM",
        muscleGroups = listOf(MuscleGroup.VASTUS_LATERALIS, MuscleGroup.BICEPS_FEMORIS),
        sides = listOf(BodySide.RIGHT, BodySide.LEFT),
        sessionTypeSuggestions = listOf(
            "baseline",
            "post_inc_1", "post_inc_2", "post_inc_3", "post_inc_4",
            "post_inc_5", "post_inc_6", "post_inc_7", "post_inc_8",
            "post_30s_1", "post_30s_2", "post_30s_3", "post_30s_4"
        )
    );

    companion object {
        fun fromCode(code: String?): Study? =
            code?.let { c -> entries.firstOrNull { it.code == c } }
    }
}
