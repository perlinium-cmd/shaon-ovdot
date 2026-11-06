package com.perlinium.shaon.employee.work

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.action.ActionParameters
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.compose.ui.graphics.Color
import com.perlinium.shaon.employee.data.Phase
import com.perlinium.shaon.employee.data.Repo
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/** Home-screen widget: shows the state and one big button (כניסה / יציאה). */
class ClockWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        Repo.init(context); Repo.ensureStarted()
        withTimeoutOrNull(3000) { Repo.openLoaded.first { it } }
        provideContent { GlanceTheme { Content() } }
    }

    @Composable
    private fun Content() {
        val ready = Repo.phase.value == Phase.Ready
        val open = Repo.openShift.value
        val bg = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFF172020))
        val fg = ColorProvider(day = Color(0xFF12201F), night = Color(0xFFE6EFEE))
        val btn = if (open != null) ColorProvider(day = Color(0xFFC2410C), night = Color(0xFFFB8A4C)) else ColorProvider(day = Color(0xFF0F766E), night = Color(0xFF2BC4B1))
        val onBtn = if (open != null) ColorProvider(day = Color.White, night = Color(0xFF2B1205)) else ColorProvider(day = Color.White, night = Color(0xFF032B27))
        Column(
            GlanceModifier.fillMaxSize().background(bg).cornerRadius(24.dp).padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                when { !ready -> "לא מחובר"; open != null -> "במשמרת מאז ${open.`in`}"; else -> "לא במשמרת" },
                style = TextStyle(color = fg, fontSize = 14.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center),
            )
            Spacer(GlanceModifier.height(8.dp))
            Text(
                if (open != null) "■  יציאה" else "▶  כניסה",
                modifier = GlanceModifier.fillMaxWidth().background(btn).cornerRadius(999.dp).padding(vertical = 12.dp)
                    .clickable(actionRunCallback<ToggleClock>()),
                style = TextStyle(color = onBtn, fontSize = 18.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center),
            )
        }
    }

    companion object {
        suspend fun refresh(context: Context) { runCatching { ClockWidget().updateAll(context) } }
        suspend fun hasAny(context: Context) = GlanceAppWidgetManager(context).getGlanceIds(ClockWidget::class.java).isNotEmpty()
    }
}

class ToggleClock : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        Repo.init(context); Repo.ensureStarted()
        if (Repo.phase.value != Phase.Ready) return
        if (!Repo.awaitOpenLoaded(4000)) return   // unknown state: never guess between in and out
        val open = Repo.openShift.value
        if (open != null) Notifier.after(context, open, Repo.clockOutOrAsk(open))
        else Repo.clockIn()
        ClockWidget().update(context, glanceId)
    }
}

class ClockWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ClockWidget()
}
