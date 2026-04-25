package com.codexflow.codexflow.data.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

class SettingsStore(
    private val dataStore: DataStore<Preferences>
) {
    val baseUrl: Flow<String> = dataStore.data.map { preferences ->
        preferences[BASE_URL_KEY] ?: DEFAULT_BASE_URL
    }

    suspend fun currentBaseUrl(): String = baseUrl.first()

    suspend fun saveBaseUrl(value: String) {
        dataStore.edit { preferences ->
            preferences[BASE_URL_KEY] = normalizeBaseUrl(value)
        }
    }

    suspend fun restoreDefaultBaseUrl() {
        saveBaseUrl(DEFAULT_BASE_URL)
    }

    companion object {
        const val DEFAULT_BASE_URL = "http://10.0.2.2:4318"
        private val BASE_URL_KEY = stringPreferencesKey("agent_base_url")

        fun create(context: Context): SettingsStore {
            val dataStore = PreferenceDataStoreFactory.create(
                produceFile = { context.preferencesDataStoreFile("codexflow_settings") }
            )
            return SettingsStore(dataStore)
        }

        fun normalizeBaseUrl(value: String): String {
            return value.trim().trimEnd('/')
        }
    }
}
