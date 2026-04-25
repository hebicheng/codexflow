package com.codexflow.codexflow.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.ViewAgenda
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.codexflow.codexflow.CodexFlowContainer
import com.codexflow.codexflow.ui.approvals.ApprovalViewModel
import com.codexflow.codexflow.ui.approvals.ApprovalsScreen
import com.codexflow.codexflow.ui.dashboard.DashboardScreen
import com.codexflow.codexflow.ui.dashboard.DashboardViewModel
import com.codexflow.codexflow.ui.sessions.SessionDetailScreen
import com.codexflow.codexflow.ui.sessions.SessionDetailViewModel
import com.codexflow.codexflow.ui.settings.SettingsScreen
import com.codexflow.codexflow.ui.settings.SettingsViewModel

@Composable
fun AppNavGraph(container: CodexFlowContainer) {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route
    val topRoutes = listOf(Routes.Dashboard, Routes.Approvals, Routes.Settings)

    Scaffold(
        bottomBar = {
            if (currentRoute in topRoutes) {
                NavigationBar {
                    TopDestination.entries.forEach { destination ->
                        NavigationBarItem(
                            selected = currentRoute == destination.route,
                            onClick = {
                                navController.navigate(destination.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(destination.icon, contentDescription = destination.label) },
                            label = { Text(destination.label) }
                        )
                    }
                }
            }
        }
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Routes.Dashboard,
            modifier = Modifier.padding(padding)
        ) {
            composable(Routes.Dashboard) {
                val viewModel: DashboardViewModel = viewModel(
                    factory = DashboardViewModel.factory(container.repository, container.settingsStore)
                )
                DashboardScreen(
                    viewModel = viewModel,
                    onOpenSession = { navController.navigate(Routes.sessionDetail(it)) }
                )
            }
            composable(Routes.Approvals) {
                val viewModel: ApprovalViewModel = viewModel(
                    factory = ApprovalViewModel.factory(container.repository)
                )
                ApprovalsScreen(viewModel = viewModel)
            }
            composable(Routes.Settings) {
                val viewModel: SettingsViewModel = viewModel(
                    factory = SettingsViewModel.factory(container.settingsStore, container.repository)
                )
                SettingsScreen(viewModel = viewModel)
            }
            composable(
                route = Routes.SessionDetail,
                arguments = listOf(navArgument("sessionId") { type = NavType.StringType })
            ) { entry ->
                val sessionId = entry.arguments?.getString("sessionId").orEmpty()
                val viewModel: SessionDetailViewModel = viewModel(
                    key = "session-$sessionId",
                    factory = SessionDetailViewModel.factory(sessionId, container.repository)
                )
                SessionDetailScreen(viewModel = viewModel, onBack = { navController.popBackStack() })
            }
        }
    }
}

private enum class TopDestination(
    val route: String,
    val label: String,
    val icon: androidx.compose.ui.graphics.vector.ImageVector
) {
    Dashboard(Routes.Dashboard, "会话", Icons.Outlined.ViewAgenda),
    Approvals(Routes.Approvals, "审批", Icons.Outlined.Checklist),
    Settings(Routes.Settings, "设置", Icons.Outlined.Settings)
}
