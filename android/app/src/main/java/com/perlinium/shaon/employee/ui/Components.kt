package com.perlinium.shaon.employee.ui

import android.os.Build
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.CloudOff
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/** Confirming haptic (a short, firm tick) — used only for the actions that matter: clock in/out, send. */
fun View.confirmTick() {
    performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY)
}

/** Respect the phone's "remove animations" setting. */
@Composable
fun reducedMotion(): Boolean {
    val ctx = LocalContext.current
    return remember { Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface,
        modifier = modifier.semantics { heading() })
}

@Composable
fun StatTile(label: String, value: String, modifier: Modifier = Modifier, highlight: Boolean = false) {
    val c = LocalShaon.current
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(18.dp),
        color = if (highlight) c.start else MaterialTheme.colorScheme.surfaceContainer,
        contentColor = if (highlight) c.onStart else MaterialTheme.colorScheme.onSurface,
        tonalElevation = 0.dp,
        shadowElevation = if (highlight) 2.dp else 0.dp,
    ) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp).semantics(mergeDescendants = true) {}) {
            Text(label, style = MaterialTheme.typography.labelMedium,
                color = if (highlight) c.onStart.copy(alpha = .85f) else MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.headlineSmall.nums(), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

enum class ChipKind { Paid, Waiting, Live, Approved, Rejected, Neutral }

@Composable
fun StatusChip(text: String, kind: ChipKind) {
    val c = LocalShaon.current
    val (bg, fg) = when (kind) {
        ChipKind.Paid, ChipKind.Approved -> c.startSoft to c.onStartSoft
        ChipKind.Waiting -> c.warnSoft to c.onWarnSoft
        ChipKind.Live -> c.startSoft to c.onStartSoft
        ChipKind.Rejected -> c.dangerSoft to c.onDangerSoft
        ChipKind.Neutral -> MaterialTheme.colorScheme.surfaceContainerHigh to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Row(
        Modifier.clip(CircleShape).background(bg).padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (kind == ChipKind.Live) LiveDot(size = 8)
        Text(text, style = MaterialTheme.typography.labelMedium, color = fg, maxLines = 1)
    }
}

@Composable
fun LiveDot(size: Int = 10) {
    Spacer(Modifier.size(size.dp).clip(CircleShape).background(LocalShaon.current.live))
}

/** A write the server refused — stays until dismissed, so money never disappears quietly. */
@Composable
fun ErrorBanner(text: String, onDismiss: () -> Unit) {
    val c = LocalShaon.current
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.dangerSoft).padding(start = 14.dp, top = 6.dp, bottom = 6.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.ErrorOutline, null, tint = c.onDangerSoft)
        Spacer(Modifier.width(10.dp))
        Text(text, Modifier.weight(1f), color = c.onDangerSoft, style = MaterialTheme.typography.bodyMedium)
        IconButton(onClick = onDismiss) { Icon(Icons.Rounded.Close, contentDescription = "סגירה", tint = c.onDangerSoft) }
    }
}

/** Shown while something is saved only on the phone (no reception yet). */
@Composable
fun OfflineNote(text: String = "נשמר בטלפון. יישלח לשרת כשתחזור קליטה.") {
    val c = LocalShaon.current
    Row(
        Modifier.clip(CircleShape).background(c.warnSoft).padding(horizontal = 12.dp, vertical = 6.dp)
            .semantics { contentDescription = text },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.CloudOff, null, tint = c.onWarnSoft, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(6.dp))
        Text(text, style = MaterialTheme.typography.labelMedium, color = c.onWarnSoft)
    }
}

val Transparent = Color.Transparent
