package com.volumhealth.app.study

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.volumhealth.app.data.appDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class StudyPreferencesManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val key = stringPreferencesKey("active_study_id")

    val activeStudy: Flow<Study?> =
        context.appDataStore.data.map { Study.fromCode(it[key]) }

    suspend fun setActiveStudy(study: Study) {
        context.appDataStore.edit { it[key] = study.code }
    }
}
