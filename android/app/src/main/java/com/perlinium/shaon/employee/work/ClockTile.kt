package com.perlinium.shaon.employee.work

import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.perlinium.shaon.employee.R
import com.perlinium.shaon.employee.data.Phase
import com.perlinium.shaon.employee.data.Repo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** Quick Settings tile: clock in / out from the top of the screen. Active (highlighted) = on shift. */
class ClockTile : TileService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var watch: Job? = null

    override fun onStartListening() {
        Repo.init(this)
        watch = scope.launch {
            Repo.ensureStarted()
            Repo.openShift.collect { render() }
        }
    }

    override fun onStopListening() { watch?.cancel() }

    private fun render() {
        val tile = qsTile ?: return
        val ready = Repo.phase.value == Phase.Ready
        val open = Repo.openShift.value
        tile.icon = Icon.createWithResource(this, R.drawable.ic_stat_clock)
        tile.label = if (open != null) "יציאה" else "כניסה"
        if (Build.VERSION.SDK_INT >= 29) tile.subtitle = if (!ready) "לא מחובר" else if (open != null) "במשמרת מאז ${open.`in`}" else "שעון עובדות"
        tile.state = when { !ready -> Tile.STATE_UNAVAILABLE; open != null -> Tile.STATE_ACTIVE; else -> Tile.STATE_INACTIVE }
        tile.updateTile()
    }

    override fun onClick() {
        scope.launch {
            Repo.ensureStarted()
            if (Repo.phase.value != Phase.Ready) return@launch
            withTimeoutOrNull(4000) { Repo.openLoaded.first { it } }
            val open = Repo.openShift.value
            if (open != null) Repo.clockOut(open)?.let { out -> Notifier.clearShift(this@ClockTile); Notifier.done(this@ClockTile, open, out) }
            else Repo.clockIn()
            render()
        }
    }

    override fun onDestroy() { scope.coroutineContext[Job]?.cancel(); super.onDestroy() }
}
