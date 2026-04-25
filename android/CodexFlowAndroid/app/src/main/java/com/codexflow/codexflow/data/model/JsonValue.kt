package com.codexflow.codexflow.data.model

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

@Serializable(with = JsonValueSerializer::class)
sealed class JsonValue {
    data class StringValue(val value: String) : JsonValue()
    data class NumberValue(val value: Double) : JsonValue()
    data class BooleanValue(val value: Boolean) : JsonValue()
    data class ObjectValue(val value: Map<String, JsonValue>) : JsonValue()
    data class ArrayValue(val value: List<JsonValue>) : JsonValue()
    data object NullValue : JsonValue()

    val stringValue: String?
        get() = (this as? StringValue)?.value

    val objectValue: Map<String, JsonValue>?
        get() = (this as? ObjectValue)?.value

    val arrayValue: List<JsonValue>?
        get() = (this as? ArrayValue)?.value

    fun toJsonElement(): JsonElement = when (this) {
        is StringValue -> JsonPrimitive(value)
        is NumberValue -> JsonPrimitive(value)
        is BooleanValue -> JsonPrimitive(value)
        is ObjectValue -> JsonObject(value.mapValues { it.value.toJsonElement() })
        is ArrayValue -> JsonArray(value.map { it.toJsonElement() })
        NullValue -> JsonNull
    }

    companion object {
        fun fromJsonElement(element: JsonElement): JsonValue = when (element) {
            JsonNull -> NullValue
            is JsonObject -> ObjectValue(element.mapValues { fromJsonElement(it.value) })
            is JsonArray -> ArrayValue(element.map { fromJsonElement(it) })
            is JsonPrimitive -> when {
                element.isString -> StringValue(element.content)
                element.booleanOrNull != null -> BooleanValue(element.booleanOrNull == true)
                element.doubleOrNull != null -> NumberValue(element.doubleOrNull ?: 0.0)
                else -> StringValue(element.content)
            }
        }

        fun string(value: String) = StringValue(value)
        fun number(value: Double) = NumberValue(value)
        fun bool(value: Boolean) = BooleanValue(value)
        fun obj(value: Map<String, JsonValue>) = ObjectValue(value)
        fun array(value: List<JsonValue>) = ArrayValue(value)
        fun nullValue() = NullValue
    }
}

object JsonValueSerializer : KSerializer<JsonValue> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("JsonValue")

    override fun deserialize(decoder: Decoder): JsonValue {
        val jsonDecoder = decoder as? JsonDecoder
            ?: throw SerializationException("JsonValue can only be decoded from JSON")
        return JsonValue.fromJsonElement(jsonDecoder.decodeJsonElement())
    }

    override fun serialize(encoder: Encoder, value: JsonValue) {
        val jsonEncoder = encoder as? JsonEncoder
            ?: throw SerializationException("JsonValue can only be encoded to JSON")
        jsonEncoder.encodeJsonElement(value.toJsonElement())
    }
}
