package com.codexflow.codexflow.ui.navigation

object Routes {
    const val Dashboard = "dashboard"
    const val Approvals = "approvals"
    const val Settings = "settings"
    const val SessionDetail = "session/{sessionId}"

    fun sessionDetail(sessionId: String) = "session/$sessionId"
}
