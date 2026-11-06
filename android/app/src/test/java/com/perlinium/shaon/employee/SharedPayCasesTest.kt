package com.perlinium.shaon.employee

import com.perlinium.shaon.employee.data.Employee
import com.perlinium.shaon.employee.data.Shift
import com.perlinium.shaon.employee.data.Special
import com.perlinium.shaon.employee.logic.isOvernight
import com.perlinium.shaon.employee.logic.parseHM
import com.perlinium.shaon.employee.logic.round2
import com.perlinium.shaon.employee.logic.shiftMinutes
import com.perlinium.shaon.employee.logic.shiftPay
import com.perlinium.shaon.employee.logic.shiftPayAgorot
import com.perlinium.shaon.employee.logic.toAgorot
import com.perlinium.shaon.employee.logic.totals
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** shared/pay-cases.json and shared/money-cases.json — the same cases the website and the Mac app are tested with. */
class SharedPayCasesTest {
    private fun JSONObject.optD(k: String): Double? = if (!has(k) || isNull(k)) null else getDouble(k)
    private fun json(name: String) = JSONObject(javaClass.classLoader!!.getResource(name)!!.readText())

    @Test fun sharedCases() {
        val cases = json("pay-cases.json").getJSONArray("cases")
        assertTrue(cases.length() > 30)
        for (i in 0 until cases.length()) {
            val c = cases.getJSONObject(i)
            val name = c.getString("name")
            val sj = c.getJSONObject("shift")
            val sp = sj.optJSONObject("special")?.let { Special(rate = it.optD("rate"), hours = it.optD("hours")) }
            val date = c.optString("date", "2026-01-01")
            val s = Shift(empId = "e", date = date, month = date.take(7), `in` = sj.getString("in"), out = sj.getString("out"),
                rate = sj.optD("rate"), special = sp)
            val emp = c.optJSONObject("emp")?.let { Employee(id = "e", name = "x", rate = it.optD("rate")) }
            assertEquals(name, c.getInt("minutes"), shiftMinutes(s.date, s.`in`, s.out))
            assertEquals(name, c.getLong("payAgorot"), shiftPayAgorot(s, emp, c.optD("defaultRate")))
            assertEquals(name, c.getLong("payAgorot") / 100.0, shiftPay(s, emp, c.optD("defaultRate")), 0.0)
            assertEquals(name, c.optBoolean("overnight", false), isOvernight(s.`in`, s.out))
        }
    }

    @Test fun rounding() {
        val list = json("money-cases.json").getJSONArray("toAgorot")
        for (i in 0 until list.length()) {
            val p = list.getJSONArray(i)
            val x = p.getDouble(0); val want = p.getLong(1)
            assertEquals("toAgorot($x)", want, toAgorot(x))
            assertEquals("round2($x)", want / 100.0, round2(x), 0.0)
        }
        assertNull(toAgorot(Double.NaN)); assertNull(toAgorot(Double.POSITIVE_INFINITY)); assertNull(toAgorot(null))
    }

    @Test fun times() {
        val list: JSONArray = json("money-cases.json").getJSONArray("parseHM")
        for (i in 0 until list.length()) {
            val p = list.getJSONArray(i)
            val text = p.getString(0)
            val want = if (p.isNull(1)) null else p.getInt(1)
            assertEquals("\"$text\"", want, parseHM(text))
        }
    }

    @Test fun totalsAreExactSums() {
        val s1 = Shift(empId = "e", date = "2026-01-01", month = "2026-01", `in` = "08:07", out = "13:52", rate = 37.5, paid = true)
        val s2 = s1.copy(paid = false)
        val s3 = s1.copy(out = "", open = true)
        val t = totals(listOf(s1, s2, s3), null, null)
        assertEquals(2 * 21563L, t.payAgorot)   // 215.63 + 215.63, not round(431.25)
        assertEquals(21563L, t.paidAgorot)
        assertEquals(215.63, t.unpaid, 0.0)
        assertEquals(690, t.minutes)
    }
}
