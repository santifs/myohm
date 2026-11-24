package com.volumhealth.app.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore

internal val Context.appDataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")
