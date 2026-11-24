package com.volumhealth.app.study

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SessionTypeNormalizerTest {
    @Test
    fun trims_and_lowercases() {
        assertEquals("basal", SessionTypeNormalizer.normalize("  Basal  "))
        assertEquals("basal", SessionTypeNormalizer.normalize("BASAL"))
        assertEquals("post_inc_3", SessionTypeNormalizer.normalize("Post_Inc_3"))
    }

    @Test
    fun replaces_internal_whitespace_with_underscore() {
        assertEquals("serie_1", SessionTypeNormalizer.normalize("Serie 1"))
        assertEquals("post_inc_3", SessionTypeNormalizer.normalize("post inc 3"))
    }

    @Test
    fun underscores_are_user_content_not_collapsed_or_stripped() {
        assertEquals("basal_", SessionTypeNormalizer.normalize("Basal_"))
        assertEquals("post__inc", SessionTypeNormalizer.normalize("Post__Inc"))
        assertEquals("_basal_", SessionTypeNormalizer.normalize("_Basal_"))
    }

    @Test
    fun blank_input_returns_null() {
        assertNull(SessionTypeNormalizer.normalize(""))
        assertNull(SessionTypeNormalizer.normalize("   "))
        assertNull(SessionTypeNormalizer.normalize(null))
    }

    @Test
    fun all_study_suggestions_are_already_canonical() {
        Study.entries.forEach { study ->
            study.sessionTypeSuggestions.forEach { suggestion ->
                assertEquals(
                    "suggestion '$suggestion' for ${study.code} is not canonical",
                    suggestion,
                    SessionTypeNormalizer.normalize(suggestion)
                )
            }
        }
    }
}
