package com.perlinium.shaon.employee.logic

import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

val HE: Locale = Locale.forLanguageTag("he-IL")
fun zone(): ZoneId = ZoneId.systemDefault()

fun dateStr(d: LocalDate): String = d.toString()                       // 2026-11-05
fun monthStr(d: LocalDate): String = d.toString().substring(0, 7)       // 2026-11
fun hm(t: LocalTime): String = "%02d:%02d".format(t.hour, t.minute)     // 08:14
fun nowLocal(ms: Long = System.currentTimeMillis()) = Instant.ofEpochMilli(ms).atZone(zone())

/** 510 -> "8:30" */
fun fmtHM(min: Int): String = "${min / 60}:${"%02d".format(min % 60)}"
fun fmtHMS(totalSec: Long): String { val s = maxOf(0, totalSec); return "%d:%02d:%02d".format(s / 3600, (s % 3600) / 60, s % 60) }

/** 1234.5 -> "1,234.50 ₪", 40 -> "40 ₪". Formats the exact whole agorot, never a float. */
fun fmtMoney(n: Double): String {
    val a = toAgorot(n) ?: 0L
    val f = NumberFormat.getNumberInstance(HE).apply {
        minimumFractionDigits = if (a % 100 == 0L) 0 else 2
        maximumFractionDigits = 2
    }
    return "${f.format(java.math.BigDecimal.valueOf(a, 2))} ₪"
}

fun parseDate(s: String): LocalDate = runCatching { LocalDate.parse(s) }.getOrDefault(LocalDate.now())
fun fmtWeekday(s: String): String = parseDate(s).dayOfWeek.getDisplayName(TextStyle.SHORT, HE)
fun fmtDayMonth(s: String): String { val d = parseDate(s); return "${d.dayOfMonth}/${d.monthValue}" }
fun fmtLongDate(d: LocalDate): String = d.format(DateTimeFormatter.ofPattern("EEEE, d בMMMM", HE))
fun fmtMonth(month: String): String = parseDate("$month-01").format(DateTimeFormatter.ofPattern("LLLL yyyy", HE))
fun shiftMonth(month: String, delta: Long): String = monthStr(parseDate("$month-01").plusMonths(delta))

fun greeting(hour: Int): String = when (hour) {
    in 5..11 -> "בוקר טוב"
    in 12..16 -> "צהריים טובים"
    in 17..21 -> "ערב טוב"
    else -> "לילה טוב"
}
