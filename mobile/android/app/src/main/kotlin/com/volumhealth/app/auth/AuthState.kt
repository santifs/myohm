package com.volumhealth.app.auth

import java.util.UUID

/**
 * Represents the current authentication state of the user.
 */
sealed class AuthState {
    /** Initial state, checking for existing session */
    data object Unknown : AuthState()

    /** No authenticated session */
    data object Unauthenticated : AuthState()

    /** User is authenticated */
    data class Authenticated(
        val userId: UUID,
        val email: String
    ) : AuthState()
}
