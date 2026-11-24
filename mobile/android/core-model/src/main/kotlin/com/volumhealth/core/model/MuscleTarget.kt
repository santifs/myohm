package com.volumhealth.core.model

/**
 * Represents a specific muscle measurement target combining a muscle group and body side.
 * Used for tracking which specific muscle location is being measured during a session.
 */
data class MuscleTarget(
    val muscle: MuscleGroup,
    val side: BodySide
) {
    /**
     * Unique identifier for this target (e.g., "quadriceps_left")
     */
    val id: String
        get() = "${muscle.value}_${side.value}"

    /**
     * Compact display name combining muscle and side short name (e.g., "Cuádriceps I")
     */
    val displayName: String
        get() = "${muscle.displayName} ${side.shortName}"

    /**
     * Full display name with complete side name (e.g., "Cuádriceps Izquierdo")
     */
    val fullDisplayName: String
        get() = "${muscle.displayName} ${side.displayName}"

    companion object {
        /**
         * Generate all possible muscle targets for the given muscle groups.
         * Creates a target for each combination of muscle and side.
         *
         * @param muscles List of muscle groups to generate targets for.
         *                Defaults to all available muscle groups.
         * @return List of all possible MuscleTarget combinations
         */
        fun allTargets(muscles: List<MuscleGroup> = MuscleGroup.entries): List<MuscleTarget> {
            return muscles.flatMap { muscle ->
                BodySide.entries.map { side ->
                    MuscleTarget(muscle = muscle, side = side)
                }
            }
        }
    }
}
