package com.volumhealth.app.study

object SessionTypeNormalizer {
    /**
     * Canonicalize a user-entered session_type label.
     *
     * Trims whitespace, lowercases, and collapses runs of internal whitespace
     * to a single underscore. Returns null for blank or null input.
     *
     * Underscores are treated as user content: they are NOT stripped or
     * collapsed. So "Basal_" stays "basal_" and "Post__inc" stays "post__inc".
     * Chips in [Study.sessionTypeSuggestions] are responsible for staying
     * canonical (no leading/trailing/repeated underscores) — verified by
     * SessionTypeNormalizerTest.all_study_suggestions_are_already_canonical.
     */
    fun normalize(raw: String?): String? {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        return trimmed.lowercase().replace(Regex("\\s+"), "_")
    }
}
