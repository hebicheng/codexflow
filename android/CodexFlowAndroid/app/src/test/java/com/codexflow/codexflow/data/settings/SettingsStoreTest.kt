package com.codexflow.codexflow.data.settings

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.io.File
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SettingsStoreTest {
    @get:Rule val temporaryFolder = TemporaryFolder()

    @Test
    fun baseUrl_defaultsToAndroidEmulatorLoopback() = runTest {
        val file = File(temporaryFolder.root, "settings.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create(produceFile = { file })
        val store = SettingsStore(dataStore)

        assertEquals(SettingsStore.DEFAULT_BASE_URL, store.currentBaseUrl())
    }
}
