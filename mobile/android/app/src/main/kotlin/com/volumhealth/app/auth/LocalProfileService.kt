// SPDX-License-Identifier: Apache-2.0
package com.volumhealth.app.auth
import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** Local owner key for the existing Room model; not a remote account or authentication session. */
@Singleton
class LocalProfileService @Inject constructor(@ApplicationContext context: Context) {
    private val preferences = context.getSharedPreferences("myohm_local_owner", Context.MODE_PRIVATE)
    private val owner: UUID = preferences.getString("id", null)?.let(UUID::fromString)
        ?: UUID.randomUUID().also { preferences.edit().putString("id", it.toString()).apply() }
    val authState: StateFlow<AuthState> = MutableStateFlow(AuthState.Authenticated(owner, "Local"))
    val currentUserId: UUID get() = owner
    val isAuthenticated = true
    suspend fun initialize() = Unit
    // No account exists to sign out; the account controls are removed from the UI.
    suspend fun signOut() = Unit
}
