package com.perlinium.shaon.employee

import com.perlinium.shaon.employee.data.Employee
import com.perlinium.shaon.employee.data.Shift
import com.perlinium.shaon.employee.data.Special
import com.perlinium.shaon.employee.logic.isOvernight
import com.perlinium.shaon.employee.logic.shiftMinutes
import com.perlinium.shaon.employee.logic.shiftPay
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** shared/pay-cases.json — the same cases the website and the Mac app are tested with. */
class SharedPayCasesTest {
    private fun JSONObject.optD(k: String): Double? = if (!has(k) || isNull(k)) null else getDouble(k)

    @Test fun sharedCases() {
        val text = javaClass.classLoader!!.getResource("pay-cases.json")!!.readText()
        val cases = JSONObject(text).getJSONArray("cases")
        assertTrue(cases.length() > 0)
        for (i in 0 until cases.length()) {
            val c = cases.getJSONObject(i)
            val name = c.getString("name")
            val sj = c.getJSONObject("shift")
            val sp = sj.optJSONObject("special")?.let { Special(rate = it.optD("rate"), hours = it.optD("hours")) }
            val s = Shift(empId = "e", date = "2026-01-01", month = "2026-01", `in` = sj.getString("in"), out = sj.getString("out"),
                rate = sj.optD("rate"), special = sp)
            val emp = c.optJSONObject("emp")?.let { Employee(id = "e", name = "x", rate = it.optD("rate")) }
            assertEquals(name, c.getInt("minutes"), shiftMinutes(s.`in`, s.out))
            assertEquals(name, c.getDouble("pay"), shiftPay(s, emp, c.optD("defaultRate")), 0.001)
            assertEquals(name, c.optBoolean("overnight", false), isOvernight(s.`in`, s.out))
        }
    }
}
