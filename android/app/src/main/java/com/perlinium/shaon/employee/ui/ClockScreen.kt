package com.perlinium.shaon.employee.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material.icons.rounded.WarningAmber
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.perlinium.shaon.employee.data.Repo
import com.perlinium.shaon.employee.data.Shift
import com.perlinium.shaon.employee.logic.effRate
import com.perlinium.shaon.employee.logic.fmtDayMonth
import com.perlinium.shaon.employee.logic.fmtHM
import com.perlinium.shaon.employee.logic.fmtHMS
import com.perlinium.shaon.employee.logic.fmtLongDate
import com.perlinium.shaon.employee.logic.fmtMoney
import com.perlinium.shaon.employee.logic.fmtMonth
import com.perlinium.shaon.employee.logic.greeting
import com.perlinium.shaon.employee.logic.hm
import com.perlinium.shaon.employee.logic.nowLocal
import com.perlinium.shaon.employee.logic.shiftMinutes
import com.perlinium.shaon.employee.logic.shiftPay
import com.perlinium.shaon.employee.logic.totals
import kotlinx.coroutines.delay
import java.time.LocalDate

/** What happened last, for the end-of-shift summary (peak-end: finish each day on a clear, positive note). */
data class Finished(val minutes: Int, val pay: Double, val tin: String, val tout: String)

@Composable
fun ClockScreen(
    onUndo: (message: String, undo: () -> Unit) -> Unit,
    onOpenMonth: () -> Unit,
    onRequest: (Shift?) -> Unit,
) {
    val open by Repo.openShift.collectAsState()
    val loaded by Repo.openLoaded.collectAsState()
    val emp by Repo.employee.collectAsState()
    val session by Repo.session.collectAsState()
    val settings by Repo.settings.collectAsState()
    val recent by Repo.recentShifts.collectAsState()
    val error by Repo.writeError.collectAsState()
    val view = LocalView.current
    var finished by rememberSaveable(stateSaver = FinishedSaver) { mutableStateOf<Finished?>(null) }
    var lastTap by remember { mutableLongStateOf(0L) }

    // Ticks every second while working, every 30 s otherwise (greeting / date).
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(open != null) { while (true) { now = System.currentTimeMillis(); delay(if (open != null) 1000 else 30_000) } }
    val t = nowLocal(now)
    val name = emp?.name ?: session?.empName ?: ""
    val rate = effRate(emp, settings.defaultRate)

    fun tap(action: () -> Unit) {
        val ms = System.currentTimeMillis()
        if (ms - lastTap < 1200) return          // a double tap never creates two shifts
        lastTap = ms
        view.confirmTick()
        action()
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Greeting: personal and calm.
        Column {
            Text("${greeting(t.hour)}${if (name.isNotBlank()) ", $name" else ""}", style = MaterialTheme.typography.headlineMedium)
            Text(fmtLongDate(t.toLocalDate()), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        error?.let { ErrorBanner(it) { Repo.writeError.value = null } }

        AnimatedContent(
            targetState = open != null, label = "state",
            transitionSpec = { (fadeIn(tween(220)) + scaleIn(initialScale = .96f, animationSpec = tween(220))) togetherWith fadeOut(tween(120)) },
        ) { working ->
            val s = open
            if (working && s != null) Working(s, now, rate, settings.defaultRate, emp) {
                tap {
                    // Out less than a minute after in = a mistaken tap: cancel instead of saving an empty shift.
                    if (System.currentTimeMillis() - (s.inAt ?: 0L) < 60_000) {
                        Repo.undoClockIn(s.id); finished = null
                        onUndo("המשמרת בוטלה (פחות מדקה)") {}
                        return@tap
                    }
                    val out = Repo.clockOut(s) ?: return@tap
                    val done = s.copy(out = out, open = false)
                    finished = Finished(shiftMinutes(s.`in`, out), shiftPay(done, emp, settings.defaultRate), s.`in`, out)
                    onUndo("נרשמה יציאה ב-$out") { Repo.undoClockOut(s); finished = null }
                }
            } else Idle(enabled = loaded || session != null, last = recent.firstOrNull { !it.open && it.out.isNotEmpty() }) {
                tap {
                    val id = Repo.clockIn() ?: return@tap
                    finished = null
                    onUndo("נרשמה כניסה ב-${hm(nowLocal().toLocalTime())}") { Repo.undoClockIn(id) }
                }
            }
        }

        AnimatedVisibility(finished != null && open == null) {
            finished?.let { DoneCard(it) { finished = null } }
        }

        open?.let { s ->
            val mins = ((now - (s.inAt ?: now)) / 60000).toInt()
            if (mins >= 10 * 60) LongShiftCard(mins) { onRequest(s) }
            if (s.pending) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { OfflineNote() }
        }

        MonthCard(onOpenMonth)

        if (open == null) {
            TextButton(onClick = { onRequest(null) }, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                Text("שכחת ללחוץ כניסה? בקשי להוסיף משמרת", style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

@Composable
private fun Idle(enabled: Boolean, last: Shift?, onClockIn: () -> Unit) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(8.dp))
        BigButton(start = true, enabled = enabled, onClick = onClockIn)
        Spacer(Modifier.height(14.dp))
        Text(
            if (last != null) "בפעם האחרונה: ${fmtDayMonth(last.date)} · ${last.`in`}–${last.out}" else "לחיצה אחת כשמגיעים לעבודה",
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun Working(s: Shift, now: Long, rate: Double, defaultRate: Double?, emp: com.perlinium.shaon.employee.data.Employee?, onClockOut: () -> Unit) {
    val secs = (now - (s.inAt ?: now)) / 1000
    val soFar = shiftPay(s.copy(out = hm(nowLocal(now).toLocalTime())), emp, defaultRate)
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        StatusChip("את במשמרת", ChipKind.Live)
        Spacer(Modifier.height(8.dp))
        Text(
            fmtHMS(secs), style = MaterialTheme.typography.displayLarge,
            modifier = Modifier.semantics { contentDescription = "במשמרת ${secs / 3600} שעות ו-${(secs % 3600) / 60} דקות" },
        )
        Text("נכנסת ב-${s.`in`}${if (rate > 0 && soFar >= 1) " · עד עכשיו ≈ ${fmtMoney(soFar)}" else ""}",
            style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(18.dp))
        BigButton(start = false, enabled = true, onClick = onClockOut)
    }
}

/**
 * The one big button. Teal ▶ "כניסה" / orange ■ "יציאה" — color, shape and word all agree,
 * so the state is clear at a glance, in sunlight, and for color-blind users.
 */
@Composable
private fun BigButton(start: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val c = LocalShaon.current
    val reduce = reducedMotion()
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed && !reduce) .94f else 1f, spring(dampingRatio = .55f, stiffness = 600f), label = "press")
    val base = if (start) c.start else c.stop
    val on = if (start) c.onStart else c.onStop
    val pulse = rememberInfiniteTransition(label = "pulse")
    val ring by pulse.animateFloat(1f, 1.10f, infiniteRepeatable(tween(1400, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "ring")

    BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        val size = minOf(maxWidth * .62f, 232.dp)
        // Soft breathing halo while working: "something is running" without words.
        if (!start && !reduce) Box(Modifier.size(size).scale(ring).clip(CircleShape).background(base.copy(alpha = .12f)))
        Box(
            Modifier
                .size(size)
                .scale(scale)
                .shadow(if (enabled) 10.dp else 0.dp, CircleShape, spotColor = base)
                .clip(CircleShape)
                // A soft top light gives the button depth: it reads as something to press.
                .background(Brush.verticalGradient(listOf(base.compositeOver(Color.White, .16f), base)))
                .border(3.dp, Color.White.copy(alpha = .18f), CircleShape)
                .clickable(interactionSource = interaction, indication = null, enabled = enabled, onClick = onClick)
                .semantics {
                    role = Role.Button
                    contentDescription = if (start) "כניסה. סימון תחילת משמרת" else "יציאה. סימון סוף משמרת"
                    stateDescription = if (start) "לא במשמרת" else "במשמרת"
                },
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(if (start) Icons.Rounded.PlayArrow else Icons.Rounded.Stop, null, tint = on, modifier = Modifier.size(size * .26f))
                Text(if (start) "כניסה" else "יציאה", style = MaterialTheme.typography.headlineLarge, color = on)
            }
        }
    }
}

private fun Color.compositeOver(other: Color, amount: Float) = Color(
    red = red * (1 - amount) + other.red * amount, green = green * (1 - amount) + other.green * amount,
    blue = blue * (1 - amount) + other.blue * amount, alpha = alpha,
)

@Composable
private fun DoneCard(f: Finished, onClose: () -> Unit) {
    val c = LocalShaon.current
    Surface(shape = RoundedCornerShape(20.dp), color = c.startSoft, contentColor = c.onStartSoft,
        modifier = Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite }) {
        Row(Modifier.padding(start = 16.dp, top = 14.dp, bottom = 14.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.CheckCircle, null, modifier = Modifier.size(36.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text("סיימת להיום. כל הכבוד!", style = MaterialTheme.typography.titleMedium)
                Text("${f.tin}–${f.tout} · ${fmtHM(f.minutes)} שעות" + if (f.pay > 0) " · ${fmtMoney(f.pay)}" else "",
                    style = MaterialTheme.typography.bodyLarge.nums())
            }
            IconButton(onClick = onClose) { Icon(Icons.Rounded.Close, contentDescription = "סגירה") }
        }
    }
}

@Composable
private fun LongShiftCard(mins: Int, onFix: () -> Unit) {
    val c = LocalShaon.current
    Surface(shape = RoundedCornerShape(18.dp), color = c.warnSoft, contentColor = c.onWarnSoft, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.WarningAmber, null)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text("את במשמרת כבר ${fmtHM(mins)} שעות", style = MaterialTheme.typography.titleSmall)
                Text("שכחת ללחוץ יציאה? אפשר לבקש תיקון של השעה.", style = MaterialTheme.typography.bodyMedium)
            }
            TextButton(onClick = onFix) { Text("תיקון") }
        }
    }
}

@Composable
private fun MonthCard(onOpen: () -> Unit) {
    val shifts by Repo.recentShifts.collectAsState()
    val emp by Repo.employee.collectAsState()
    val settings by Repo.settings.collectAsState()
    val tt = totals(shifts.filter { !it.open }, emp, settings.defaultRate)
    val month = LocalDate.now().toString().substring(0, 7)
    Surface(
        onClick = onOpen, shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainer,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(Modifier.padding(horizontal = 18.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("${fmtMonth(month)} עד עכשיו", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("${fmtHM(tt.minutes)} שעות", style = MaterialTheme.typography.headlineSmall.nums())
                    Spacer(Modifier.width(12.dp))
                    if (tt.pay > 0) Text(fmtMoney(tt.pay), style = MaterialTheme.typography.titleMedium.nums(), color = MaterialTheme.colorScheme.primary)
                }
            }
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = "לפירוט החודש", tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private val FinishedSaver = androidx.compose.runtime.saveable.Saver<Finished?, List<Any>>(
    save = { f -> f?.let { listOf(it.minutes, it.pay, it.tin, it.tout) } ?: emptyList() },
    restore = { l -> if (l.size == 4) Finished(l[0] as Int, l[1] as Double, l[2] as String, l[3] as String) else null },
)
