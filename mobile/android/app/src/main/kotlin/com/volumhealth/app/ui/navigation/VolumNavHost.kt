package com.volumhealth.app.ui.navigation

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.volumhealth.app.ui.screens.history.HistoryScreen
import com.volumhealth.app.ui.screens.history.MeasurementDetailScreen
import com.volumhealth.app.ui.screens.history.RawMeasurementDetailScreen
import com.volumhealth.app.ui.screens.measurement.FrequencyConfigurationScreen
import com.volumhealth.app.ui.screens.measurement.MeasurementScreen
import com.volumhealth.app.ui.screens.settings.SettingsScreen
import com.volumhealth.app.ui.screens.subjects.MeasurementResultScreen
import com.volumhealth.app.ui.screens.subjects.SubjectListScreen
import com.volumhealth.app.ui.screens.subjects.SubjectMeasurementScreen

@Composable
fun VolumApp() {
    val bootstrapViewModel: AppBootstrapViewModel = hiltViewModel()
    val context = LocalContext.current

    val permissionsToRequest = remember {
        buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(Manifest.permission.BLUETOOTH_SCAN)
                add(Manifest.permission.BLUETOOTH_CONNECT)
            } else {
                add(Manifest.permission.ACCESS_FINE_LOCATION)
                add(Manifest.permission.ACCESS_COARSE_LOCATION)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { granted ->
        // Try to auto-reconnect once permissions are granted (will silently no-op if any missing)
        if (granted.values.any { it }) {
            bootstrapViewModel.tryAutoReconnect()
        }
    }

    LaunchedEffect(Unit) {
        val missing = permissionsToRequest.filter { perm ->
            ContextCompat.checkSelfPermission(context, perm) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            permissionLauncher.launch(missing.toTypedArray())
        } else {
            bootstrapViewModel.tryAutoReconnect()
        }
    }

    val navController = rememberNavController()
    Scaffold(
        bottomBar = { VolumBottomBar(navController) }
    ) { padding ->
        VolumNavHost(navController = navController, modifier = Modifier.padding(padding))
    }
}

@Composable
private fun VolumBottomBar(navController: NavHostController) {
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route
    NavigationBar {
        AppDestination.bottomNavItems.forEach { destination ->
            NavigationBarItem(
                selected = currentRoute == destination.route,
                onClick = {
                    if (currentRoute != destination.route) {
                        navController.navigate(destination.route) {
                            popUpTo(navController.graph.startDestinationId) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    }
                },
                icon = { Icon(destination.icon, contentDescription = stringResource(destination.labelResId)) },
                label = { Text(stringResource(destination.labelResId)) }
            )
        }
    }
}

@Composable
private fun VolumNavHost(navController: NavHostController, modifier: Modifier = Modifier) {
    NavHost(
        navController = navController,
        startDestination = AppDestination.Subjects.route,
        modifier = modifier
    ) {
        composable(AppDestination.Laboratory.route) {
            MeasurementScreen(
                laboratoryMode = true,
                onConfigure = { navController.navigate(AppRoute.FREQUENCY_CONFIG) },
                onNavigateBack = { navController.navigate(AppDestination.Subjects.route) },
                onNavigateToHistory = { navController.navigate(AppDestination.History.route) }
            )
        }
        composable(AppDestination.Subjects.route) {
            SubjectListScreen(
                onSubjectSelected = { athleteId ->
                    navController.navigate(AppRoute.subjectMeasure(athleteId))
                }
            )
        }
        composable(AppDestination.History.route) {
            HistoryScreen(
                onMeasurementSelected = { measurementId ->
                    navController.navigate(AppRoute.historyDetail(measurementId))
                },
                onRawMeasurementSelected = { measurementId ->
                    navController.navigate(AppRoute.historyRaw(measurementId))
                }
            )
        }
        composable(AppDestination.Settings.route) {
            SettingsScreen(
                onNavigateToFrequencyConfig = {
                    navController.navigate(AppRoute.FREQUENCY_CONFIG)
                }
            )
        }
        composable(AppRoute.FREQUENCY_CONFIG) {
            FrequencyConfigurationScreen(onNavigateBack = { navController.popBackStack() })
        }
        composable(
            route = AppRoute.SUBJECT_MEASURE_PATTERN,
            arguments = listOf(navArgument("athleteId") { type = NavType.StringType })
        ) {
            SubjectMeasurementScreen(
                onNavigateBack = { navController.popBackStack() },
                onNavigateToChangeDevice = {
                    navController.navigate(AppDestination.Settings.route)
                },
                onNavigateToSettings = {
                    navController.navigate(AppDestination.Settings.route)
                },
                onNavigateToMeasure = { sessionId ->
                    navController.navigate(AppRoute.measurementExecute(sessionId))
                }
            )
        }
        composable(
            route = AppRoute.MEASUREMENT_EXECUTE_PATTERN,
            arguments = listOf(navArgument("sessionId") { type = NavType.StringType })
        ) { backStackEntry ->
            val sessionId = backStackEntry.arguments?.getString("sessionId") ?: ""
            MeasurementScreen(
                sessionId = sessionId,
                onNavigateBack = { navController.popBackStack() },
                onMeasurementComplete = {
                    navController.navigate(AppRoute.measurementResult(sessionId)) {
                        popUpTo(AppRoute.MEASUREMENT_EXECUTE_PATTERN) { inclusive = true }
                    }
                },
                onNavigateToHistory = { navController.navigate(AppDestination.History.route) }
            )
        }
        composable(
            route = AppRoute.MEASUREMENT_RESULT_PATTERN,
            arguments = listOf(navArgument("sessionId") { type = NavType.StringType })
        ) {
            MeasurementResultScreen(
                onNewMeasurement = {
                    navController.popBackStack(AppRoute.SUBJECT_MEASURE_PATTERN, inclusive = false)
                },
                onChangeSubject = {
                    navController.popBackStack(AppDestination.Subjects.route, inclusive = false)
                }
            )
        }
        composable(
            route = AppRoute.HISTORY_DETAIL_PATTERN,
            arguments = listOf(navArgument("measurementId") { type = NavType.StringType })
        ) {
            MeasurementDetailScreen(onNavigateBack = { navController.popBackStack() })
        }
        composable(
            route = AppRoute.HISTORY_RAW_PATTERN,
            arguments = listOf(navArgument("measurementId") { type = NavType.StringType })
        ) {
            RawMeasurementDetailScreen(onNavigateBack = { navController.popBackStack() })
        }
    }
}

@Composable
private fun PlaceholderScreen(label: String) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(label)
    }
}
