package com.perlinium.shaon.employee.work

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.perlinium.shaon.employee.R
import com.perlinium.shaon.employee.data.Phase
import com.perlinium.shaon.employee.data.Repo
import com.perlinium.shaon.employee.data.Shift
import com.perlinium.shaon.employee.logic.fmtHM
import com.perlinium.shaon.employee.logic.shiftMinutes
import com.perlinium.shaon.employee.ui.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeUnit

/** Notifications: the ongoing "on shift" one (with an exit button), reminders, request answers. */
object Notifier {
    private const val CH_SHIFT = "shift"
    private const val CH_ALERTS = "alerts"
    const val ID_SHIFT = 1
    private const val ID_REMIND = 2
    private const val ID_DONE = 3
    private const val ID_REQ = 100

    fun channels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CH_SHIFT, "משמרת פעילה", NotificationManager.IMPORTANCE_LOW).apply {
            description = "מראה שאת במשמרת, עם כפתור יציאה"; setShowBadge(false)
        })
        nm.createNotificationChannel(NotificationChannel(CH_ALERTS, "תזכורות ותשובות", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "תזכורת אם שכחת ללחוץ יציאה, ותשובות לבקשות"
        })
    }

    private fun can(ctx: Context) = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun openApp(ctx: Context) = PendingIntent.getActivity(ctx, 0, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    private fun clockOutAction(ctx: Context) = PendingIntent.getBroadcast(ctx, 1, Intent(ctx, ClockReceiver::class.java).setAction(ClockReceiver.CLOCK_OUT),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    fun showShift(ctx: Context, s: Shift) {
        if (!can(ctx)) return
        val n = NotificationCompat.Builder(ctx, CH_SHIFT)
            .setSmallIcon(R.drawable.ic_stat_clock)
            .setContentTitle("את במשמרת")
            .setContentText("נכנסת ב-${s.`in`}")
            .setWhen(s.inAt ?: System.currentTimeMillis()).setUsesChronometer(true).setShowWhen(true)
            .setOngoing(true).setOnlyAlertOnce(true).setCategory(NotificationCompat.CATEGORY_STATUS)
            .setColor(0xFF0F766E.toInt())
            .setContentIntent(openApp(ctx))
            .addAction(0, "יציאה", clockOutAction(ctx))
            .build()
        runCatching { NotificationManagerCompat.from(ctx).notify(ID_SHIFT, n) }
    }

    fun clearShift(ctx: Context) = NotificationManagerCompat.from(ctx).cancel(ID_SHIFT)

    fun done(ctx: Context, s: Shift, out: String) {
        if (!can(ctx)) return
        val n = NotificationCompat.Builder(ctx, CH_ALERTS).setSmallIcon(R.drawable.ic_stat_clock)
            .setContentTitle("נרשמה יציאה ב-$out")
            .setContentText("${s.`in`}–$out · ${fmtHM(shiftMinutes(s.`in`, out))} שעות. טעות? אפשר לבקש תיקון באפליקציה.")
            .setContentIntent(openApp(ctx)).setAutoCancel(true).setTimeoutAfter(10 * 60_000).build()
        runCatching { NotificationManagerCompat.from(ctx).notify(ID_DONE, n) }
    }

    fun remind(ctx: Context, s: Shift, mins: Long) {
        if (!can(ctx)) return
        val n = NotificationCompat.Builder(ctx, CH_ALERTS).setSmallIcon(R.drawable.ic_stat_clock)
            .setContentTitle("עדיין בעבודה?")
            .setContentText("את במשמרת כבר ${fmtHM(mins.toInt())} שעות (מאז ${s.`in`}). אם סיימת, לחצי יציאה.")
            .setContentIntent(openApp(ctx)).setAutoCancel(true)
            .addAction(0, "יציאה", clockOutAction(ctx)).build()
        runCatching { NotificationManagerCompat.from(ctx).notify(ID_REMIND, n) }
    }

    fun requestAnswered(ctx: Context, id: String, approved: Boolean, what: String) {
        if (!can(ctx)) return
        val n = NotificationCompat.Builder(ctx, CH_ALERTS).setSmallIcon(R.drawable.ic_stat_clock)
            .setContentTitle(if (approved) "הבקשה שלך אושרה" else "הבקשה שלך נדחתה")
            .setContentText(what).setContentIntent(openApp(ctx)).setAutoCancel(true).build()
        runCatching { NotificationManagerCompat.from(ctx).notify(ID_REQ + (id.hashCode() and 0xffff), n) }
    }
}

/** "יציאה" pressed on a notification. Works even when the app is closed. */
class ClockReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != CLOCK_OUT) return
        val pending = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.Main).launch {
            try {
                Repo.init(ctx); Repo.ensureStarted()
                if (Repo.phase.value == Phase.Ready) {
                    withTimeoutOrNull(5000) { Repo.openLoaded.first { it } }
                    Repo.openShift.value?.let { s -> Repo.clockOut(s)?.let { out -> Notifier.clearShift(ctx); Notifier.done(ctx, s, out) } }
                }
            } finally { pending.finish() }
        }
    }
    companion object { const val CLOCK_OUT = "com.perlinium.shaon.employee.CLOCK_OUT" }
}

/**
 * Every ~15 minutes, also after a reboot: brings back the "on shift" notification,
 * reminds after 10 hours, and tells her when a request was answered.
 */
class CheckWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        val ctx = applicationContext
        Repo.init(ctx); Repo.ensureStarted()
        if (Repo.phase.value != Phase.Ready) return Result.success()
        withTimeoutOrNull(8000) { Repo.openLoaded.first { it } }
        val prefs = ctx.getSharedPreferences("worker", Context.MODE_PRIVATE)
        val s = Repo.openShift.value
        if (s == null) Notifier.clearShift(ctx) else {
            Notifier.showShift(ctx, s)
            val mins = (System.currentTimeMillis() - (s.inAt ?: System.currentTimeMillis())) / 60000
            if (mins >= 10 * 60 && prefs.getString("reminded", null) != s.id) {
                Notifier.remind(ctx, s, mins); prefs.edit().putString("reminded", s.id).apply()
            }
        }
        // Answers to requests since last time.
        val seen = prefs.getStringSet("answered", emptySet())!!.toMutableSet()
        val first = !prefs.contains("answered")
        for (r in Repo.requests.value) if ((r.status == "approved" || r.status == "rejected") && r.id !in seen) {
            if (!first) Notifier.requestAnswered(ctx, r.id, r.status == "approved", "${r.date.substring(8)}/${r.date.substring(5, 7)} · ${r.`in`}${if (r.out.isNotEmpty()) "–" + r.out else ""}")
            seen += r.id
        }
        prefs.edit().putStringSet("answered", seen).apply()
        return Result.success()
    }

    companion object {
        fun schedule(ctx: Context) = WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(
            "check", ExistingPeriodicWorkPolicy.KEEP, PeriodicWorkRequestBuilder<CheckWorker>(15, TimeUnit.MINUTES).build(),
        )
    }
}
