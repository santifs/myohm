package com.volumhealth.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class MuscleGroupTest {
    @Test
    fun fromString_parses_new_muscles() {
        assertEquals(MuscleGroup.BICEPS_BRACHII, MuscleGroup.fromString("biceps_brachii"))
        assertEquals(MuscleGroup.VASTUS_LATERALIS, MuscleGroup.fromString("vastus_lateralis"))
        assertEquals(MuscleGroup.BICEPS_FEMORIS, MuscleGroup.fromString("biceps_femoris"))
    }

    @Test
    fun fromString_remains_case_insensitive_and_keeps_legacy_values() {
        assertEquals(MuscleGroup.QUADRICEPS, MuscleGroup.fromString("QUADRICEPS"))
        assertEquals(MuscleGroup.HAMSTRING, MuscleGroup.fromString("hamstring"))
    }

    @Test
    fun new_muscles_have_spanish_display_names() {
        assertEquals("Bíceps braquial", MuscleGroup.BICEPS_BRACHII.displayName)
        assertEquals("Vasto lateral", MuscleGroup.VASTUS_LATERALIS.displayName)
        assertEquals("Bíceps femoral", MuscleGroup.BICEPS_FEMORIS.displayName)
    }
}
