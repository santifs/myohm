package com.volumhealth.app.locale

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.volumhealth.app.data.appDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

enum class AppLanguage(val code: String, val displayName: String) {
    ENGLISH("en", "English"),
    SPANISH("es", "Espanol");

    companion object {
        fun fromCode(code: String): AppLanguage =
            entries.find { it.code == code } ?: ENGLISH
    }
}

@Singleton
class LanguageManager @Inject constructor(
    private val context: Context
) {
    private val languageKey = stringPreferencesKey("app_language")

    val currentLanguage: Flow<AppLanguage> = context.appDataStore.data.map { preferences ->
        val code = preferences[languageKey] ?: getSystemLanguage()
        AppLanguage.fromCode(code)
    }

    suspend fun setLanguage(language: AppLanguage) {
        context.appDataStore.edit { preferences ->
            preferences[languageKey] = language.code
        }
        applyLanguage(language)
    }

    fun applyLanguage(language: AppLanguage) {
        val localeList = LocaleListCompat.forLanguageTags(language.code)
        AppCompatDelegate.setApplicationLocales(localeList)
    }

    fun initializeLanguage() {
        val currentLocales = AppCompatDelegate.getApplicationLocales()
        if (currentLocales.isEmpty) {
            // Apply system default or saved preference
            val systemLanguage = getSystemLanguage()
            val language = AppLanguage.fromCode(systemLanguage)
            applyLanguage(language)
        }
    }

    private fun getSystemLanguage(): String {
        val systemLocale = Locale.getDefault().language
        return if (systemLocale == "es") "es" else "en"
    }
}
