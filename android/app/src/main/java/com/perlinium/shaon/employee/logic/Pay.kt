package com.perlinium.shaon.employee.logic

import com.perlinium.shaon.employee.data.Employee
import com.perlinium.shaon.employee.data.Shift
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.roundToLong

// Port of public/pay.js and mac/ShaonMac/Logic/Pay.swift — all three are tested against
// shared/pay-cases.json and shared/money-cases.json.
//
// Money is exact: every amount is a whole number of agorot. A shift's pay is worked out exactly and rounded once,
// to the nearest agora (half up); totals add up those whole agorot, so rows always sum to their total.
// Hours are real time in Israel: on the nights the clock moves, 22:00–06:00 is 7 or 9 hours, not 8.

val SHIFT_ZONE: ZoneId = ZoneId.of("Asia/Jerusalem")
private const val DAY_MIN = 24 * 60
private const val H12 = 12L * 3600 * 1000

// ---------------- times and dates ----------------

private val HM = Regex("^(\\d{1,2}):(\\d{2})$")
private fun ascii(s: String) = s.all { it in '0'..'9' }

/** "HH:MM" (or "H:MM") -> minutes since midnight; null if empty or not a valid time. */
fun parseHM(t: String?): Int? {
    val m = HM.matchEntire(t ?: return null) ?: return null
    if (!ascii(m.groupValues[1]) || !ascii(m.groupValues[2])) return null
    val h = m.groupValues[1].toInt(); val mi = m.groupValues[2].toInt()
    return if (h <= 23 && mi <= 59) h * 60 + mi else null
}

/** Minutes since midnight, 0 when not a valid time. */
fun toMin(t: String): Int = parseHM(t) ?: 0

data class YMD(val y: Int, val m: Int, val d: Int)
private fun isLeap(y: Int) = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
private fun daysIn(y: Int, m: Int) = intArrayOf(31, if (isLeap(y)) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[m - 1]
private val YMD_RE = Regex("^(\\d{4})-(\\d{2})-(\\d{2})$")

/** "YYYY-MM-DD" -> a real calendar date, else null. */
fun parseYMD(s: String?): YMD? {
    val r = YMD_RE.matchEntire(s ?: return null) ?: return null
    if (!r.groupValues.drop(1).all { ascii(it) }) return null
    val y = r.groupValues[1].toInt(); val m = r.groupValues[2].toInt(); val d = r.groupValues[3].toInt()
    if (y < 1900 || m !in 1..12 || d < 1 || d > daysIn(y, m)) return null
    return YMD(y, m, d)
}
private fun nextDay(v: YMD) = when {
    v.d < daysIn(v.y, v.m) -> YMD(v.y, v.m, v.d + 1)
    v.m < 12 -> YMD(v.y, v.m + 1, 1)
    else -> YMD(v.y + 1, 1, 1)
}
private fun utcMidnight(v: YMD): Long = LocalDate.of(v.y, v.m, v.d).toEpochDay() * 86_400_000L

/** Israel's offset from UTC, in ms, at a moment (+2h in winter, +3h in summer). */
fun zoneOffsetMs(utcMs: Long): Long = SHIFT_ZONE.rules.getOffset(Instant.ofEpochMilli(utcMs)).totalSeconds * 1000L

/**
 * The moment (ms since 1970) of a wall-clock time in Israel. Same as java.time: in the hour that repeats in autumn,
 * the earlier (summer) moment; a time skipped in spring is moved forward by the gap (02:30 -> 03:30).
 */
fun zonedMs(day: YMD, minOfDay: Int): Long {
    val naive = utcMidnight(day) + minOfDay * 60_000L
    val before = zoneOffsetMs(naive - H12); val after = zoneOffsetMs(naive + H12)
    val c1 = naive - before; val c2 = naive - after
    val ok1 = zoneOffsetMs(c1) == before; val ok2 = zoneOffsetMs(c2) == after
    return when {
        ok1 && ok2 -> minOf(c1, c2)
        ok2 -> c2
        else -> c1
    }
}

/** True when the clock does not move from the start of [day] until 2 days later (all days but 2 a year). */
private fun steadyFrom(day: YMD): Boolean {
    val t = utcMidnight(day)
    return zoneOffsetMs(t - 6 * 3_600_000L) == zoneOffsetMs(t + 54 * 3_600_000L)
}

/**
 * Minutes worked on [date] (the day of the clock-in). If out is earlier than in, the shift ends the next day.
 * Real time: counts the hour the clock moves. 0 when a time is missing or invalid, or in equals out.
 */
fun shiftMinutes(date: String?, tin: String?, tout: String?): Int {
    val a = parseHM(tin) ?: return 0
    val b = parseHM(tout) ?: return 0
    if (a == b) return 0
    val wall = if (b > a) b - a else b - a + DAY_MIN
    val d = parseYMD(date) ?: return wall
    if (steadyFrom(d)) return wall
    val start = zonedMs(d, a)
    val end = zonedMs(if (b > a) d else nextDay(d), b)
    val real = ((end - start) / 60_000.0).roundToLong().toInt()
    return if (real > 0) real else wall
}

/** The same shift by the clock on the wall (ignores the clock moving), for showing the difference. */
fun wallMinutes(tin: String?, tout: String?): Int {
    val a = parseHM(tin) ?: return 0
    val b = parseHM(tout) ?: return 0
    return if (a == b) 0 else if (b > a) b - a else b - a + DAY_MIN
}

fun isOvernight(tin: String?, tout: String?): Boolean {
    val a = parseHM(tin) ?: return false
    val b = parseHM(tout) ?: return false
    return b < a
}

// ---------------- money ----------------

private val NUM = Regex("^(\\d+)(?:\\.(\\d+))?(?:[eE]([+-]?\\d+))?$")

/**
 * Exact whole agorot of an amount in shekels, rounded half up (half away from zero below 0); null if not finite.
 * Reads the number's shortest decimal form, so 1.005 -> 101 (not 100).
 */
fun toAgorot(x: Double?): Long? {
    if (x == null || !x.isFinite()) return null
    val r = NUM.matchEntire(abs(x).toString()) ?: return null
    val digits = r.groupValues[1] + r.groupValues[2]
    val point = r.groupValues[1].length + (r.groupValues[3].ifEmpty { "0" }.toIntOrNull() ?: return null) + 2
    var whole = 0L; var next = 0
    when {
        point <= 0 -> next = if (point == 0) digits[0].digitToInt() else 0
        point >= digits.length -> whole = (digits + "0".repeat(point - digits.length)).toLongOrNull() ?: return null
        else -> { whole = digits.substring(0, point).toLongOrNull() ?: return null; next = digits[point].digitToInt() }
    }
    val a = whole + if (next >= 5) 1 else 0
    return if (x < 0 && a != 0L) -a else a
}

/** Rounded to the agora, as a number (2 decimals at most). */
fun round2(n: Double): Double = (toAgorot(n) ?: 0L) / 100.0

/** num / den rounded to the nearest whole number, half away from zero (den > 0). */
private fun divRound(num: Long, den: Long): Long {
    val q = (2 * abs(num) + den) / (2 * den)
    return if (num < 0) -q else q
}

private fun Double?.finite(): Double? = if (this != null && isFinite()) this else null

/** Hourly rate for an employee: their own rate, else the default rate, else 0. */
fun effRate(emp: Employee?, defaultRate: Double?): Double = emp?.rate.finite() ?: defaultRate.finite() ?: 0.0
/** Hourly rate for a shift: a rate set on the shift wins over the employee's rate. */
fun shiftRate(s: Shift, emp: Employee?, defaultRate: Double?): Double = s.rate.finite() ?: effRate(emp, defaultRate)

private class Sp(val rate: Double, val hours: Double?)
private fun specialOf(s: Shift): Sp? {
    val r = s.special?.rate.finite() ?: return null
    return Sp(r, s.special?.hours.finite())
}

/** Minutes of a shift paid at its special rate (all of it, or only `special.hours`). Can have a fraction. */
fun specialMinutes(s: Shift): Double {
    val sp = specialOf(s) ?: return 0.0
    val m = shiftMinutes(s.date, s.`in`, s.out).toDouble()
    return sp.hours?.let { minOf(m, maxOf(0.0, it * 60)) } ?: m
}

/** Pay for one shift in whole agorot. Worked out exactly in fifths of a minute (0.01 hour = 0.6 minute), rounded once. */
fun shiftPayAgorot(s: Shift, emp: Employee?, defaultRate: Double?): Long {
    val total = shiftMinutes(s.date, s.`in`, s.out)
    if (total <= 0) return 0
    val units = total * 5L
    val sp = specialOf(s)
    val spUnits = when {
        sp == null -> 0L
        sp.hours == null -> units
        else -> minOf(units, maxOf(0L, (toAgorot(sp.hours) ?: 0L) * 3))
    }
    val amount = (units - spUnits) * (toAgorot(shiftRate(s, emp, defaultRate)) ?: 0L) +
        spUnits * (sp?.let { toAgorot(it.rate) } ?: 0L)
    return divRound(amount, 300)
}

/** Pay for one shift in shekels (always a whole number of agorot). */
fun shiftPay(s: Shift, emp: Employee?, defaultRate: Double?): Double = shiftPayAgorot(s, emp, defaultRate) / 100.0

/** Month totals; amounts kept in whole agorot so they add up exactly. */
data class MonthTotals(val minutes: Int, val payAgorot: Long, val paidAgorot: Long, val shifts: Int) {
    val pay: Double get() = payAgorot / 100.0
    val paid: Double get() = paidAgorot / 100.0
    val unpaid: Double get() = (payAgorot - paidAgorot) / 100.0
}

fun totals(shifts: List<Shift>, emp: Employee?, defaultRate: Double?): MonthTotals {
    var minutes = 0; var pay = 0L; var paid = 0L
    for (s in shifts) {
        val p = shiftPayAgorot(s, emp, defaultRate)
        minutes += shiftMinutes(s.date, s.`in`, s.out); pay += p
        if (s.paid) paid += p
    }
    return MonthTotals(minutes, pay, paid, shifts.size)
}
