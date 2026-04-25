package com.codexflow.codexflow.data.model

import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class JsonValueTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun jsonValue_decodesAndEncodesNestedValues() {
        val decoded = json.decodeFromString<JsonValue>(
            """{"text":"hello","count":2,"ok":true,"items":[null,"x"]}"""
        )

        assertTrue(decoded is JsonValue.ObjectValue)
        val encoded = json.encodeToString(decoded)
        val roundTrip = json.decodeFromString<JsonValue>(encoded)

        assertEquals(decoded, roundTrip)
    }
}
