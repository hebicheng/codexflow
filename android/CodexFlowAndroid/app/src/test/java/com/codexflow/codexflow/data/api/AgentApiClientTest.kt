package com.codexflow.codexflow.data.api

import org.junit.Assert.assertEquals
import org.junit.Test

class AgentApiClientTest {
    @Test
    fun buildUrl_joinsBaseAndPathWithoutDoubleSlash() {
        val url = AgentApiClient.buildUrl("http://10.0.2.2:4318/", "/api/v1/dashboard")

        assertEquals("http://10.0.2.2:4318/api/v1/dashboard", url.toString())
    }
}
