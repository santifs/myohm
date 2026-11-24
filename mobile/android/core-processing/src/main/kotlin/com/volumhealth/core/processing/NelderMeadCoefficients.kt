package com.volumhealth.core.processing

/** Constants controlling the Nelder-Mead simplex behavior. */
object NelderMeadCoefficients {
    const val ALPHA = 1.0f   // Reflection coefficient
    const val GAMMA = 2.0f   // Expansion coefficient
    const val RHO = 0.5f     // Contraction coefficient
    const val SIGMA = 0.5f   // Shrinkage coefficient
}
