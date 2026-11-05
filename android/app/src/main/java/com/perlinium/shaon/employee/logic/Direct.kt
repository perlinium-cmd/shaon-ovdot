package com.perlinium.shaon.employee.logic

import com.perlinium.shaon.employee.data.Shift
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

/*
 * Which changes the phone saves right away, and which go to the manager for approval
 * (the same limits are enforced by firestore.rules):
 *   - a forgotten shift, typed in on the day it ended
 *   - a clock-in or clock-out moved EARLIER (she remembered later that she came / left earlier),
 *     while the shift is running or on the day it ended
 * Anything else (a later time, an older day) is a request.
 */

const val MAX_EARLIER_IN_MS = 12 * 3600_000L

/** Local time [time] on [date] as ms since 1970. */
fun localMillis(date: String, time: String, zone: ZoneId = zone()): Long =
    LocalDate.parse(date).atTime(LocalTime.parse(time)).atZone(zone).toInstant().toEpochMilli()

/** Start and end in ms; an exit earlier than the entry is on the next day. */
fun spanMillis(date: String, tin: String, tout: String, zone: ZoneId = zone()): Pair<Long, Long> {
    val a = localMillis(date, tin, zone)
    var b = localMillis(date, tout, zone)
    if (b <= a) b = LocalDate.parse(date).plusDays(1).atTime(LocalTime.parse(tout)).atZone(zone).toInstant().toEpochMilli()
    return a to b
}

private fun dayOf(ms: Long, zone: ZoneId): LocalDate = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()

/** A change the phone may save without approval. outAt null = the shift keeps running. */
data class Direct(val inAt: Long, val outAt: Long?)

/** A forgotten shift: saved right away if it ended today (and not in the future). null = needs approval. */
fun directAdd(date: String, tin: String, tout: String, now: Long, zone: ZoneId = zone()): Direct? {
    if (tin.isEmpty() || tout.isEmpty() || tin == tout) return null
    val (a, b) = spanMillis(date, tin, tout, zone)
    if (b > now || dayOf(b, zone) != dayOf(now, zone)) return null
    return Direct(a, b)
}

/**
 * New times for an existing shift (newOut "" = a running shift keeps running).
 * Saved right away only if every change moves a time earlier. null = needs approval.
 */
fun directFix(s: Shift, newIn: String, newOut: String, now: Long, zone: ZoneId = zone()): Direct? {
    val oldInAt = s.inAt ?: return null
    if (s.paid || s.source != "phone" || newIn.isEmpty()) return null
    val inAt = if (newIn == s.`in`) oldInAt else localMillis(s.date, newIn, zone)
    if (inAt > oldInAt || inAt <= oldInAt - MAX_EARLIER_IN_MS) return null

    fun outMs(t: String): Long { var b = localMillis(s.date, t, zone); if (b <= inAt) b = spanMillis(s.date, newIn, t, zone).second; return b }

    if (s.open) {
        if (newOut.isEmpty()) return if (inAt < oldInAt) Direct(inAt, null) else null
        val outAt = outMs(newOut)                       // clocking out at the time she really left
        return if (outAt in (inAt + 1)..now) Direct(inAt, outAt) else null
    }
    val oldOutAt = s.outAt ?: return null
    if (newOut.isEmpty() || dayOf(oldOutAt, zone) != dayOf(now, zone)) return null   // only on the day it ended
    val outAt = if (newOut == s.out) oldOutAt else outMs(newOut)
    if (outAt > oldOutAt || outAt <= inAt) return null
    return if (inAt < oldInAt || outAt < oldOutAt) Direct(inAt, outAt) else null
}

/** True if [a, b] overlaps any of the other shifts (open ones run until [now]). */
fun overlapsAny(a: Long, b: Long, others: List<Shift>, now: Long, zone: ZoneId = zone()): Boolean = others.any { o ->
    val start = o.inAt ?: runCatching { localMillis(o.date, o.`in`, zone) }.getOrNull() ?: return@any false
    val end = if (o.open) now else o.outAt ?: runCatching { spanMillis(o.date, o.`in`, o.out, zone).second }.getOrNull() ?: return@any false
    a < end && start < b
}
