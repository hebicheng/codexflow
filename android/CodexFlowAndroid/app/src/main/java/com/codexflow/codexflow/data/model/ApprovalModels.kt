package com.codexflow.codexflow.data.model

import kotlinx.serialization.Serializable

@Serializable
data class ApprovalListEnvelope(
    val data: List<PendingRequestView> = emptyList()
)

@Serializable
data class PendingRequestView(
    val id: String = "",
    val method: String = "",
    val kind: String = "",
    val threadId: String = "",
    val turnId: String = "",
    val itemId: String = "",
    val reason: String = "",
    val summary: String = "",
    val choices: List<String> = emptyList(),
    val createdAt: String = "",
    val params: Map<String, JsonValue> = emptyMap()
)

object ApprovalResultBuilder {
    fun build(approval: PendingRequestView, selectedChoice: String, userInputText: String = ""): JsonValue {
        return when (approval.kind) {
            "command", "fileChange" -> JsonValue.obj(
                mapOf("decision" to JsonValue.string(selectedChoice))
            )

            "permissions" -> {
                val scoped = selectedChoice == "session" || selectedChoice == "turn"
                JsonValue.obj(
                    mapOf(
                        "permissions" to if (scoped) {
                            approval.params["permissions"] ?: JsonValue.obj(emptyMap())
                        } else {
                            JsonValue.obj(
                                mapOf(
                                    "network" to JsonValue.nullValue(),
                                    "fileSystem" to JsonValue.nullValue()
                                )
                            )
                        },
                        "scope" to if (scoped) JsonValue.string(selectedChoice) else JsonValue.nullValue()
                    )
                )
            }

            "userInput" -> {
                val questionId = firstQuestionId(approval.params) ?: "reply"
                JsonValue.obj(
                    mapOf(
                        "answers" to JsonValue.obj(
                            mapOf(
                                questionId to JsonValue.obj(
                                    mapOf(
                                        "answers" to JsonValue.array(listOf(JsonValue.string(userInputText)))
                                    )
                                )
                            )
                        )
                    )
                )
            }

            else -> JsonValue.obj(mapOf("decision" to JsonValue.string(selectedChoice)))
        }
    }

    private fun firstQuestionId(params: Map<String, JsonValue>): String? {
        return params["questions"]
            ?.arrayValue
            ?.asSequence()
            ?.mapNotNull { it.objectValue?.get("id")?.stringValue }
            ?.firstOrNull { it.isNotBlank() }
    }
}
