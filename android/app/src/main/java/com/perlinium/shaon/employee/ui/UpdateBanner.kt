package com.perlinium.shaon.employee.ui

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.SystemUpdate
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.perlinium.shaon.employee.update.Updater
import com.perlinium.shaon.employee.update.Updater.State

/** Once, at the top of the app: look for a new version whenever the app comes to the screen, and open the installer. */
@Composable
fun UpdateEffects() {
    if (!Updater.enabled) return
    val ctx = LocalContext.current
    LifecycleEventEffect(Lifecycle.Event.ON_START) { Updater.check(ctx) }
    LaunchedEffect(Unit) {
        Updater.openInstaller.collect { file ->
            if (!Updater.install(ctx, file)) Toast.makeText(ctx, "לא נמצאה בטלפון תוכנה להתקנת עדכונים", Toast.LENGTH_LONG).show()
        }
    }
}

/** "יש גרסה חדשה" — nothing at all is shown when the app is up to date. */
@Composable
fun UpdateBanner(modifier: Modifier = Modifier) {
    val state by Updater.state.collectAsState()
    val s = state
    if (s is State.Idle) return
    val ctx = LocalContext.current
    val c = LocalShaon.current
    val (title, sub, action) = when (s) {
        is State.Available -> Triple("יש גרסה חדשה לאפליקציה", "העדכון לוקח כמה שניות. השעות שלך נשמרות.", "לעדכן")
        is State.Downloading -> Triple("מוריד את הגרסה החדשה…", "${s.percent}%", null)
        is State.Ready -> Triple("הגרסה החדשה מוכנה", "נשאר רק ללחוץ \"עדכון\" בחלון של אנדרואיד.", "להתקנה")
        is State.Failed -> Triple("ההורדה לא הצליחה", "כדאי לבדוק שיש אינטרנט ולנסות שוב.", "לנסות שוב")
        State.Idle -> return
    }
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(c.startSoft)
            .padding(start = 14.dp, end = 10.dp, top = 10.dp, bottom = 10.dp)
            .semantics { liveRegion = LiveRegionMode.Polite },
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.SystemUpdate, null, tint = c.onStartSoft)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleSmall, color = c.onStartSoft)
                Text(sub, style = MaterialTheme.typography.bodySmall, color = c.onStartSoft.copy(alpha = .85f))
            }
            if (action != null) {
                Spacer(Modifier.width(8.dp))
                Button(
                    onClick = { Updater.download(ctx) },
                    colors = ButtonDefaults.buttonColors(containerColor = c.start, contentColor = c.onStart),
                ) { Text(action) }
            }
        }
        if (s is State.Downloading) {
            LinearProgressIndicator(
                progress = { s.percent / 100f },
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp, end = 4.dp),
                color = c.start, trackColor = c.onStartSoft.copy(alpha = .15f),
            )
        }
    }
}
