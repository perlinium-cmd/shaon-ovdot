package com.perlinium.shaon.employee.logic

import com.perlinium.shaon.employee.data.Employee
import com.perlinium.shaon.employee.data.Shift
import kotlin.math.min
import kotlin.math.roundToLong

// Port of public/pay.js and mac/ShaonMac/Logic/Pay.swift — all three are tested against shared/pay-cases.json.

fun round2(n: Double): Double = (n * 100).roundToLong() / 100.0

fun toMin(t: String): Int {
    val p = t.split(":").mapNotNull { it.toIntOrNull() }
    return if (p.size == 2) p[0] * 60 + p[1] else 0
}

/** Minutes worked. If out is earlier than in, the shift crosses midnight. */
fun shiftMinutes(tin: String, tout: String): Int {
    if (tin.isEmpty() || tout.isEmpty()) return 0
    var diff = toMin(tout) - toMin(tin)
    if (diff < 0) diff += 24 * 60
    return diff
}

fun isOvernight(tin: String, tout: String): Boolean = tin.isNotEmpty() && tout.isNotEmpty() && toMin(tout) < toMin(tin)

fun effRate(emp: Employee?, defaultRate: Double?): Double = emp?.rate ?: defaultRate ?: 0.0
fun shiftRate(s: Shift, emp: Employee?, defaultRate: Double?): Double = s.rate ?: effRate(emp, defaultRate)

fun specialMinutes(s: Shift): Double {
    val sp = s.special ?: return 0.0
    if (sp.rate == null) return 0.0
    val m = shiftMinutes(s.`in`, s.out).toDouble()
    return sp.hours?.let { min(m, it * 60) } ?: m
}

fun shiftPay(s: Shift, emp: Employee?, defaultRate: Double?): Double {
    val m = shiftMinutes(s.`in`, s.out).toDouble()
    val sp = specialMinutes(s)
    return ((m - sp) / 60) * shiftRate(s, emp, defaultRate) + (sp / 60) * (s.special?.rate ?: 0.0)
}

data class MonthTotals(val minutes: Int, val pay: Double, val paid: Double, val shifts: Int) {
    val unpaid: Double get() = round2(pay - paid)
}

fun totals(shifts: List<Shift>, emp: Employee?, defaultRate: Double?): MonthTotals {
    var minutes = 0; var pay = 0.0; var paid = 0.0
    for (s in shifts) {
        val p = shiftPay(s, emp, defaultRate)
        minutes += shiftMinutes(s.`in`, s.out); pay += p
        if (s.paid) paid += p
    }
    return MonthTotals(minutes, pay, paid, shifts.size)
}
