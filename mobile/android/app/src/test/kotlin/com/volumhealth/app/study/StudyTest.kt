package com.volumhealth.app.study

import com.volumhealth.core.model.BodySide
import com.volumhealth.core.model.MuscleGroup
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StudyTest {
    @Test
    fun biceps_tfg_uses_biceps_brachii_right_only() {
        val s = Study.BICEPS_TFG
        assertEquals(listOf(MuscleGroup.BICEPS_BRACHII), s.muscleGroups)
        assertEquals(listOf(BodySide.RIGHT), s.sides)
        assertTrue("basal" in s.sessionTypeSuggestions)
        assertTrue("post_serie_5" in s.sessionTypeSuggestions)
        assertTrue("12h" in s.sessionTypeSuggestions)
        assertTrue("72h" in s.sessionTypeSuggestions)
        assertEquals(12, s.sessionTypeSuggestions.size)
    }

    @Test
    fun sentadilla_tfm_is_bilateral_and_has_two_muscles() {
        val s = Study.SENTADILLA_TFM
        assertEquals(
            setOf(MuscleGroup.VASTUS_LATERALIS, MuscleGroup.BICEPS_FEMORIS),
            s.muscleGroups.toSet()
        )
        assertEquals(setOf(BodySide.RIGHT, BodySide.LEFT), s.sides.toSet())
        assertTrue("baseline" in s.sessionTypeSuggestions)
        assertTrue("post_inc_1" in s.sessionTypeSuggestions)
        assertTrue("post_30s_1" in s.sessionTypeSuggestions)
        assertEquals(13, s.sessionTypeSuggestions.size)
    }

    @Test
    fun fromCode_still_works() {
        assertEquals(Study.BICEPS_TFG, Study.fromCode("biceps_tfg"))
        assertEquals(Study.SENTADILLA_TFM, Study.fromCode("sentadilla_tfm"))
    }
}
