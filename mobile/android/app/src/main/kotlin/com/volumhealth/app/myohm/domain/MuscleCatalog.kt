package com.volumhealth.app.myohm.domain

import com.volumhealth.app.myohm.ui.L

/** Muscles that can be measured with a local band, plus the whole-body montage. */
enum class MyohmMuscle(val key: String) {
    QUADRICEPS("quadriceps"),
    HAMSTRINGS("hamstrings"),
    CALF("calf"),
    TIBIALIS("tibialis"),
    BICEPS("biceps"),
    TRICEPS("triceps"),
    FOREARM("forearm"),
    GLUTES("glutes"),
    OTHER("other");

    enum class BodyView { FRONT, BACK }

    val view: BodyView?
        get() = when (this) {
            QUADRICEPS, TIBIALIS, BICEPS, FOREARM -> BodyView.FRONT
            HAMSTRINGS, CALF, TRICEPS, GLUTES -> BodyView.BACK
            OTHER -> null
        }

    /** Suggested band (distance between V+ and V−, mm). A starting point, not a rule. */
    val suggestedBand: Int?
        get() = when (this) {
            QUADRICEPS, HAMSTRINGS -> 100
            CALF, TIBIALIS, BICEPS, TRICEPS -> 75
            FOREARM -> 50
            GLUTES -> 150
            OTHER -> null
        }

    val displayName: String
        get() = when (this) {
            QUADRICEPS -> L("Quadriceps")
            HAMSTRINGS -> L("Hamstrings")
            CALF -> L("Calf")
            TIBIALIS -> L("Tibialis anterior")
            BICEPS -> L("Biceps")
            TRICEPS -> L("Triceps")
            FOREARM -> L("Forearm")
            GLUTES -> L("Glutes")
            OTHER -> L("Other")
        }

    /**
     * Outlines traced on the 520 × 1000 body illustrations, for the side drawn on the viewer's left.
     * The front view shows the person's right on the viewer's left; the back view, the person's left.
     */
    private val tracedOutline: List<Pair<Float, Float>>
        get() = when (this) {
            BICEPS -> listOf(126f to 266f, 158f to 262f, 166f to 288f, 160f to 318f, 147f to 345f, 131f to 358f, 112f to 350f, 114f to 316f, 118f to 288f)
            FOREARM -> listOf(102f to 372f, 146f to 370f, 140f to 408f, 124f to 446f, 106f to 466f, 86f to 460f, 88f to 420f, 94f to 392f)
            QUADRICEPS -> listOf(182f to 442f, 222f to 446f, 249f to 492f, 247f to 560f, 237f to 612f, 218f to 632f, 196f to 628f, 173f to 594f, 163f to 530f, 167f to 476f)
            TIBIALIS -> listOf(172f to 690f, 194f to 688f, 199f to 740f, 195f to 798f, 184f to 828f, 173f to 800f, 167f to 742f)
            TRICEPS -> listOf(118f to 264f, 160f to 262f, 165f to 290f, 153f to 328f, 135f to 352f, 110f to 346f, 111f to 310f, 114f to 284f)
            GLUTES -> listOf(200f to 398f, 240f to 393f, 257f to 412f, 257f to 470f, 249f to 499f, 215f to 502f, 189f to 488f, 181f to 450f, 187f to 414f)
            HAMSTRINGS -> listOf(174f to 516f, 249f to 513f, 247f to 570f, 239f to 624f, 227f to 674f, 201f to 679f, 185f to 650f, 174f to 590f)
            CALF -> listOf(173f to 702f, 222f to 699f, 231f to 745f, 224f to 789f, 200f to 800f, 177f to 792f, 163f to 750f)
            OTHER -> emptyList()
        }

    /** Tap outlines for each side: index 0 is the person's right, index 1 the left. */
    val outlines: List<List<Pair<Float, Float>>>
        get() {
            val traced = tracedOutline
            if (traced.isEmpty()) return emptyList()
            val mirrored = traced.map { (x, y) -> (520f - x) to y }
            return if (view == BodyView.BACK) listOf(mirrored, traced) else listOf(traced, mirrored)
        }

    companion object {
        const val WHOLE_BODY_KEY = "whole_body"
        fun fromKey(key: String): MyohmMuscle? = entries.firstOrNull { it.key == key }
    }
}

enum class LimbSide(val key: String) {
    RIGHT("right"), LEFT("left");

    val displayName: String get() = if (this == RIGHT) L("Right") else L("Left")

    companion object {
        fun fromKey(key: String): LimbSide? = entries.firstOrNull { it.key == key }
    }
}

sealed interface MeasurementKind {
    data class Muscle(val muscle: MyohmMuscle, val side: LimbSide, val band: Int) : MeasurementKind
    data class WholeBody(val weightKg: Double, val restCompleted: Boolean) : MeasurementKind

    /** Compact form used as a navigation argument. */
    fun encode(): String = when (this) {
        is Muscle -> "m_${muscle.key}_${side.key}_$band"
        is WholeBody -> "b_${weightKg}_${if (restCompleted) 1 else 0}"
    }

    companion object {
        fun decode(value: String): MeasurementKind? {
            val parts = value.split("_")
            return when (parts.firstOrNull()) {
                "m" -> {
                    if (parts.size != 4) return null
                    val muscle = MyohmMuscle.fromKey(parts[1]) ?: return null
                    val side = LimbSide.fromKey(parts[2]) ?: return null
                    Muscle(muscle, side, parts[3].toIntOrNull() ?: return null)
                }
                "b" -> {
                    if (parts.size != 3) return null
                    WholeBody(parts[1].toDoubleOrNull() ?: return null, parts[2] == "1")
                }
                else -> null
            }
        }
    }
}
