package com.codexflow.codexflow.data.api

sealed class ApiError(message: String, cause: Throwable? = null) : Exception(message, cause) {
    data object InvalidBaseUrl : ApiError("Agent base URL 无效")
    data object InvalidResponse : ApiError("Agent 返回了无效响应")
    data class Server(val detail: String) : ApiError(detail)
    data class Network(val detail: String, val source: Throwable? = null) : ApiError(detail, source)
}

fun Throwable.userMessage(): String = when (this) {
    is ApiError -> message ?: "请求失败"
    else -> localizedMessage ?: "请求失败"
}
