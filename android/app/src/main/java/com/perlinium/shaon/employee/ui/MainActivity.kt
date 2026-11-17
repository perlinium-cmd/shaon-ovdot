package com.perlinium.shaon.employee.ui

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.perlinium.shaon.employee.data.Phase
import com.perlinium.shaon.employee.data.Repo
import com.perlinium.shaon.employee.data.Shift
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val incoming = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        readIntent(intent)
        setContent { ShaonTheme { App(incoming.value) } }
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); readIntent(intent) }

    /** shaon://pair/CODE — the QR on the Mac, scanned with the phone's regular camera. */
    private fun readIntent(i: Intent?) {
        val d = i?.data ?: return
        if (d.scheme == "shaon" && d.host == "pair") incoming.value = codeFrom(d.toString())
    }
}

private enum class Tab(val label: String) { Clock("שעון"), Month("החודש שלי"), Requests("בקשות") }

@Composable
private fun App(incomingCode: String?) {
    val phase by Repo.phase.collectAsState()
    UpdateEffects()
    when (val p = phase) {
        Phase.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        is Phase.NeedsPairing -> Scaffold { pad ->
            Column(Modifier.padding(pad).fillMaxSize()) {
                UpdateBanner(Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp))
                Box(Modifier.weight(1f)) { PairingScreen(p.message, incomingCode) }
            }
        }
        Phase.NeedsNetwork -> Scaffold { pad ->
            Column(Modifier.padding(pad).fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)) {
                Icon(Icons.Rounded.WifiOff, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("צריך אינטרנט פעם אחת כדי לשחזר את החיבור", style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
                Text("אחרי זה האפליקציה עובדת גם בלי קליטה.", style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center)
                Button(onClick = { Repo.start() }) { Text("לנסות שוב") }
            }
        }
        Phase.Ready -> Main()
    }
}

@Composable
private fun Main() {
    var tab by rememberSaveable { mutableStateOf(Tab.Clock) }
    var sheetFor by remember { mutableStateOf<Pair<Boolean, Shift?>?>(null) }   // (open?, shift)
    val snack = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val reqs by Repo.requests.collectAsState()
    val pendingCount = reqs.count { it.status == "pending" }

    // Notifications (Android 13+): the "on shift" notification with its exit button needs this.
    val askNotif = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    LaunchedEffect(Unit) { if (Build.VERSION.SDK_INT >= 33) askNotif.launch(Manifest.permission.POST_NOTIFICATIONS) }

    fun undoable(msg: String, undo: () -> Unit) {
        scope.launch {
            snack.currentSnackbarData?.dismiss()
            // Undo instead of "are you sure?": no friction, and mistakes are one tap away from fixed.
            val canUndo = !msg.startsWith("המשמרת בוטלה")
            if (snack.showSnackbar(msg, actionLabel = if (canUndo) "ביטול" else null, duration = if (canUndo) SnackbarDuration.Long else SnackbarDuration.Short) == SnackbarResult.ActionPerformed) undo()
        }
    }

    Scaffold(
        snackbarHost = {
            SnackbarHost(snack) { data ->
                androidx.compose.material3.Snackbar(
                    data, shape = androidx.compose.foundation.shape.RoundedCornerShape(14.dp),
                    containerColor = MaterialTheme.colorScheme.inverseSurface,
                    actionColor = MaterialTheme.colorScheme.inversePrimary,   // brand teal, readable in both themes
                )
            }
        },
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceContainer) {
                Tab.entries.forEach { t ->
                    NavigationBarItem(
                        selected = tab == t, onClick = { tab = t },
                        label = { Text(t.label, style = MaterialTheme.typography.labelMedium) },
                        icon = {
                            val icon = when (t) { Tab.Clock -> Icons.Rounded.Schedule; Tab.Month -> Icons.Rounded.CalendarMonth; Tab.Requests -> Icons.Rounded.EditNote }
                            if (t == Tab.Requests && pendingCount > 0) BadgedBox(badge = { Badge { Text("$pendingCount") } }) { Icon(icon, null) }
                            else Icon(icon, null)
                        },
                    )
                }
            }
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize()) {
            UpdateBanner(Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp))
            Box(Modifier.weight(1f)) {
                when (tab) {
                    Tab.Clock -> ClockScreen(onUndo = ::undoable, onOpenMonth = { tab = Tab.Month }, onRequest = { sheetFor = true to it })
                    Tab.Month -> MonthScreen(onShift = { sheetFor = true to it })
                    Tab.Requests -> RequestsScreen(onNew = { sheetFor = true to null })
                }
            }
        }
    }

    sheetFor?.let { (_, shift) ->
        RequestSheet(shift, onClose = { sheetFor = null }) { msg, wasRequest ->
            sheetFor = null
            if (wasRequest) tab = Tab.Requests
            scope.launch { snack.showSnackbar(msg) }
        }
    }
}
