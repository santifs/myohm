package com.volumhealth.app.myohm.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.core.content.ContextCompat
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.People
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.volumhealth.app.myohm.data.MyohmViewModel
import com.volumhealth.app.myohm.domain.BodyEquation
import com.volumhealth.app.myohm.domain.MeasurementKind
import com.volumhealth.app.ui.screens.measurement.FrequencyConfigurationScreen
import com.volumhealth.app.ui.screens.measurement.MeasurementScreen

object Routes {
    const val HOME = "home"
    const val PEOPLE = "people"
    const val HISTORY = "history"
    const val MUSCLE = "muscle"
    const val PLACEMENT = "placement"
    const val MEASURING = "measuring/{kind}"
    const val RESULT = "result/{id}"
    const val EQUATION = "equation/{id}?eq={eq}"
    const val PERSON_FORM = "person?id={id}"
    const val PAIRING = "pairing"
    const val SETTINGS = "settings"
    const val LABORATORY = "laboratory"
    const val FREQUENCY_CONFIG = "laboratory/frequency"

    fun measuring(kind: MeasurementKind) = "measuring/${kind.encode()}"
    fun result(id: String) = "result/$id"
    fun equation(id: String, eq: BodyEquation? = null) = if (eq == null) "equation/$id" else "equation/$id?eq=${eq.name}"
    fun personForm(id: String?) = if (id == null) "person" else "person?id=$id"

    val tabs = listOf(HOME, PEOPLE, HISTORY)
}

/** Root of the redesigned app: first-use flow, then three tabs. */
@Composable
fun MyohmApp() {
    val activity = LocalContext.current as ComponentActivity
    val vm: MyohmViewModel = hiltViewModel(activity)
    MyohmLocale.spanish = LocalConfiguration.current.locales[0].language == "es"

    BluetoothPermissions { vm.reconnect() }

    val people by vm.people.collectAsState()
    val onboarded by vm.onboarded.collectAsState()
    val list = people ?: run {
        Box(Modifier.fillMaxSize().background(MyohmColor.background))
        return
    }
    if (list.isEmpty() || !(onboarded || vm.hasPairedDevice())) {
        OnboardingFlow(vm)
    } else {
        Box(Modifier.fillMaxSize()) {
            MainTabs(vm)
            // Content scrolls under the transparent status bar; keep the clock readable.
            Box(
                Modifier
                    .fillMaxWidth()
                    .windowInsetsTopHeight(WindowInsets.statusBars)
                    .background(MyohmColor.background.copy(alpha = 0.94f))
            )
        }
    }
}

/** Asks for Bluetooth (and notification) permissions once, then tries the paired device. */
@Composable
private fun BluetoothPermissions(onGranted: () -> Unit) {
    val context = LocalContext.current
    val permissions = remember {
        buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(Manifest.permission.BLUETOOTH_SCAN)
                add(Manifest.permission.BLUETOOTH_CONNECT)
            } else {
                add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        }
    }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
        if (granted.values.all { it }) onGranted()
    }
    LaunchedEffect(Unit) {
        val missing = permissions.filter { ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) onGranted() else launcher.launch(missing.toTypedArray())
    }
}

@Composable
private fun OnboardingFlow(vm: MyohmViewModel) {
    val nav = rememberNavController()
    NavHost(nav, startDestination = "welcome") {
        composable("welcome") { WelcomeScreen { nav.navigate("pairing") } }
        composable("pairing") {
            PairingScreen(vm, onBack = { nav.popBackStack() }, onDone = { nav.navigate("person") })
        }
        composable("person") {
            PersonFormScreen(vm, personId = null, onBack = { nav.popBackStack() }) { saved -> vm.finishOnboarding(saved.id) }
        }
    }
}

@Composable
private fun MainTabs(vm: MyohmViewModel) {
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val route = entry?.destination?.route
    Scaffold(
        containerColor = MyohmColor.background,
        bottomBar = { if (route in Routes.tabs) MyohmBottomBar(nav, route) }
    ) { padding ->
        Box(Modifier.padding(bottom = padding.calculateBottomPadding())) {
            MyohmNavHost(nav, vm)
        }
    }
}

@Composable
private fun MyohmBottomBar(nav: NavHostController, current: String?) {
    val items = listOf(
        Triple(Routes.HOME, L("Measure"), Icons.Filled.GraphicEq),
        Triple(Routes.PEOPLE, L("People"), Icons.Filled.People),
        Triple(Routes.HISTORY, L("History"), Icons.AutoMirrored.Filled.ShowChart)
    )
    NavigationBar(containerColor = Color.White, tonalElevation = 0.dp) {
        items.forEach { (route, label, icon) ->
            NavigationBarItem(
                selected = current == route,
                onClick = { nav.switchTab(route) },
                icon = { Icon(icon, contentDescription = null) },
                label = { Text(label) },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = MyohmColor.brand,
                    selectedTextColor = MyohmColor.brand,
                    indicatorColor = MyohmColor.brandSoft,
                    unselectedIconColor = MyohmColor.muted,
                    unselectedTextColor = MyohmColor.muted
                )
            )
        }
    }
}

fun NavHostController.switchTab(route: String) {
    navigate(route) {
        popUpTo(graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}

/** Back to the tab root the user came from. */
fun NavHostController.closeFlow() {
    // Pop one screen at a time (public API) until the top is a tab root.
    while (currentDestination?.route !in Routes.tabs) {
        if (!popBackStack()) break
    }
}

@Composable
private fun MyohmNavHost(nav: NavHostController, vm: MyohmViewModel) {
    NavHost(nav, startDestination = Routes.HOME) {
        composable(Routes.HOME) {
            HomeScreen(
                vm,
                onMuscle = { nav.navigate(Routes.MUSCLE) },
                onWholeBody = { nav.navigate(Routes.PLACEMENT) },
                onRepeat = { kind -> if (kind == null) nav.navigate(Routes.PLACEMENT) else nav.navigate(Routes.measuring(kind)) },
                onPairing = { nav.navigate(Routes.PAIRING) },
                onSettings = { nav.navigate(Routes.SETTINGS) }
            )
        }
        composable(Routes.PEOPLE) {
            PeopleScreen(
                vm,
                onOpen = { nav.navigate(Routes.result(it)) },
                onEdit = { nav.navigate(Routes.personForm(it)) },
                onAdd = { nav.navigate(Routes.personForm(null)) },
                onMeasure = { nav.switchTab(Routes.HOME) }
            )
        }
        composable(Routes.HISTORY) {
            HistoryScreen(vm, onOpen = { nav.navigate(Routes.result(it)) })
        }
        composable(Routes.MUSCLE) {
            MuscleSelectScreen(vm, onBack = { nav.popBackStack() }) { kind -> nav.navigate(Routes.measuring(kind)) }
        }
        composable(Routes.PLACEMENT) {
            PlacementScreen(vm, onBack = { nav.popBackStack() }) { kind -> nav.navigate(Routes.measuring(kind)) }
        }
        composable(Routes.MEASURING, arguments = listOf(navArgument("kind") { type = NavType.StringType })) { e ->
            val kind = MeasurementKind.decode(e.arguments?.getString("kind").orEmpty())
            if (kind == null) {
                nav.popBackStack()
            } else {
                MeasuringScreen(vm, kind, onCancel = { nav.popBackStack() }) { id ->
                    nav.navigate(Routes.result(id)) {
                        popUpTo(Routes.MEASURING) { inclusive = true }
                    }
                }
            }
        }
        composable(Routes.RESULT, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e ->
            ResultScreen(
                vm,
                id = e.arguments?.getString("id").orEmpty(),
                onClose = { nav.closeFlow() },
                onEquation = { id, eq -> nav.navigate(Routes.equation(id, eq)) },
                onRepeat = { kind ->
                    nav.closeFlow()
                    nav.navigate(Routes.measuring(kind))
                },
                onEditPerson = { nav.navigate(Routes.personForm(it)) }
            )
        }
        composable(
            Routes.EQUATION,
            arguments = listOf(
                navArgument("id") { type = NavType.StringType },
                navArgument("eq") { type = NavType.StringType; nullable = true; defaultValue = null }
            )
        ) { e ->
            val eq = e.arguments?.getString("eq")?.let { name -> BodyEquation.entries.firstOrNull { it.name == name } }
            EquationScreen(vm, e.arguments?.getString("id").orEmpty(), eq, onBack = { nav.popBackStack() })
        }
        composable(
            Routes.PERSON_FORM,
            arguments = listOf(navArgument("id") { type = NavType.StringType; nullable = true; defaultValue = null })
        ) { e ->
            val id = e.arguments?.getString("id")
            PersonFormScreen(vm, personId = id, onBack = { nav.popBackStack() }) { saved ->
                if (id == null) vm.selectPerson(saved.id)
                nav.popBackStack()
            }
        }
        composable(Routes.PAIRING) {
            PairingScreen(vm, onBack = { nav.popBackStack() }, onDone = { nav.popBackStack() })
        }
        composable(Routes.SETTINGS) {
            SettingsScreen(
                vm,
                onBack = { nav.popBackStack() },
                onPairing = { nav.navigate(Routes.PAIRING) },
                onLaboratory = { nav.navigate(Routes.LABORATORY) }
            )
        }
        composable(Routes.LABORATORY) {
            Column(Modifier.fillMaxSize().background(MyohmColor.background)) {
                MeasurementScreen(
                    laboratoryMode = true,
                    onConfigure = { nav.navigate(Routes.FREQUENCY_CONFIG) },
                    onNavigateBack = { nav.popBackStack() },
                    onNavigateToHistory = { nav.popBackStack() }
                )
            }
        }
        composable(Routes.FREQUENCY_CONFIG) {
            FrequencyConfigurationScreen(onNavigateBack = { nav.popBackStack() })
        }
    }
}
