package com.codexflow.codexflow.data.model

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class ApprovalResultBuilderTest {
    private val json = Json

    @Test
    fun commandApproval_buildsDecisionBody() {
        val approval = PendingRequestView(kind = "command", choices = listOf("accept", "reject"))

        val result = ApprovalResultBuilder.build(approval, selectedChoice = "accept")

        assertEquals("""{"decision":"accept"}""", json.encodeToString(result))
    }

    @Test
    fun permissionsApproval_buildsScopedPermissionsBody() {
        val approval = PendingRequestView(
            kind = "permissions",
            params = mapOf("permissions" to JsonValue.obj(mapOf("network" to JsonValue.string("ask"))))
        )

        val result = ApprovalResultBuilder.build(approval, selectedChoice = "session")

        assertEquals(
            """{"permissions":{"network":"ask"},"scope":"session"}""",
            json.encodeToString(result)
        )
    }

    @Test
    fun userInputApproval_usesQuestionId() {
        val approval = PendingRequestView(
            kind = "userInput",
            params = mapOf(
                "questions" to JsonValue.array(
                    listOf(JsonValue.obj(mapOf("id" to JsonValue.string("next_step"))))
                )
            )
        )

        val result = ApprovalResultBuilder.build(approval, selectedChoice = "answer", userInputText = "继续")

        assertEquals(
            """{"answers":{"next_step":{"answers":["继续"]}}}""",
            json.encodeToString(result)
        )
    }
}
