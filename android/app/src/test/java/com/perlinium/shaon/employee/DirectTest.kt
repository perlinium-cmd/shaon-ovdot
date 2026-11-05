package com.perlinium.shaon.employee

import com.perlinium.shaon.employee.data.Shift
import com.perlinium.shaon.employee.logic.Direct
import com.perlinium.shaon.employee.logic.directAdd
import com.perlinium.shaon.employee.logic.directFix
import com.perlinium.shaon.employee.logic.localMillis
import com.perlinium.shaon.employee.logic.overlapsAny
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

/** What the phone saves right away (the manager only gets a notice) and what goes to him for approval. */
class DirectTest {
    private val zone = ZoneId.of("Asia/Jerusalem")
    private fun at(date: String, time: String) = localMillis(date, time, zone)
    private val today = "2026-11-05"
    private val yesterday = "2026-11-04"
    private val now = at(today, "18:00")

    private fun open(date: String = today, tin: String = "08:00") =
        Shift(id = "s", empId = "e", date = date, month = date.take(7), `in` = tin, out = "", open = true, source = "phone", inAt = at(date, tin))

    private fun closed(date: String = today, tin: String = "08:00", tout: String = "16:00", outDate: String = date) =
        Shift(id = "s", empId = "e", date = date, month = date.take(7), `in` = tin, out = tout, source = "phone",
            inAt = at(date, tin), outAt = at(outDate, tout))

    private fun fix(s: Shift, tin: String, tout: String) = directFix(s, tin, tout, now, zone)

    // A forgotten shift, typed in after work

    @Test fun forgottenShiftThatEndedTodayIsSaved() {
        assertEquals(Direct(at(today, "09:00"), at(today, "12:00")), directAdd(today, "09:00", "12:00", now, zone))
    }

    @Test fun nightShiftThatEndedThisMorningIsSaved() {
        assertEquals(Direct(at(yesterday, "22:00"), at(today, "06:00")), directAdd(yesterday, "22:00", "06:00", now, zone))
    }

    @Test fun olderDayOrFutureOrEmptyNeedsApproval() {
        assertNull("yesterday's shift", directAdd(yesterday, "09:00", "12:00", now, zone))
        assertNull("ends later today", directAdd(today, "17:00", "19:00", now, zone))
        assertNull("same in and out", directAdd(today, "09:00", "09:00", now, zone))
        assertNull("missing time", directAdd(today, "", "12:00", now, zone))
    }

    // Still at work, remembered she came in earlier

    @Test fun earlierClockInKeepsShiftRunning() {
        assertEquals(Direct(at(today, "07:40"), null), fix(open(), "07:40", ""))
    }

    @Test fun laterOrSameClockInNeedsApproval() {
        assertNull(fix(open(), "08:20", ""))
        assertNull("nothing changed", fix(open(), "08:00", ""))
    }

    @Test fun clockInAtMostTwelveHoursEarlier() {
        assertEquals(Direct(at(today, "01:30"), null), fix(open(tin = "13:00"), "01:30", ""))
        assertNull(fix(open(tin = "13:00"), "00:30", ""))
    }

    // Forgot to clock out: records when she really left

    @Test fun closesRunningShiftAtThePastTimeSheLeft() {
        assertEquals(Direct(at(today, "08:00"), at(today, "17:00")), fix(open(), "08:00", "17:00"))
        assertEquals(Direct(at(today, "07:30"), at(today, "17:00")), fix(open(), "07:30", "17:00"))
    }

    @Test fun cannotCloseRunningShiftInTheFuture() {
        assertNull(fix(open(), "08:00", "18:30"))
        assertNull("before the clock-in = tomorrow morning", fix(open(), "08:00", "07:00"))
    }

    @Test fun closesYesterdaysRunningNightShift() {
        val s = open(date = yesterday, tin = "22:00")
        assertEquals(Direct(at(yesterday, "22:00"), at(today, "06:00")), fix(s, "22:00", "06:00"))
    }

    // Shift that ended today: times moved earlier

    @Test fun earlierClockOutOrClockInIsSaved() {
        assertEquals(Direct(at(today, "08:00"), at(today, "15:30")), fix(closed(), "08:00", "15:30"))
        assertEquals(Direct(at(today, "07:30"), at(today, "16:00")), fix(closed(), "07:30", "16:00"))
        assertEquals(Direct(at(today, "07:30"), at(today, "15:30")), fix(closed(), "07:30", "15:30"))
    }

    @Test fun laterTimesNeedApproval() {
        assertNull(fix(closed(), "08:00", "16:30"))
        assertNull(fix(closed(), "07:30", "16:30"))
        assertNull(fix(closed(), "08:30", "16:00"))
        assertNull("nothing changed", fix(closed(), "08:00", "16:00"))
        assertNull("cannot reopen it", fix(closed(), "08:00", ""))
    }

    @Test fun shiftThatEndedYesterdayNeedsApproval() {
        assertNull(fix(closed(date = yesterday), "08:00", "15:00"))
    }

    @Test fun nightShiftEndedThisMorningCanEndEarlier() {
        val s = closed(date = yesterday, tin = "22:00", tout = "06:00", outDate = today)
        assertEquals(Direct(at(yesterday, "22:00"), at(today, "05:30")), fix(s, "22:00", "05:30"))
    }

    @Test fun onlyUnpaidShiftsFromThisPhone() {
        assertNull("paid", fix(closed().copy(paid = true), "07:30", "16:00"))
        assertNull("added by the manager", fix(closed().copy(source = null), "07:30", "16:00"))
        assertNull("approved request", fix(closed().copy(source = "request"), "07:30", "16:00"))
        assertNull("no phone clock", fix(open().copy(inAt = null), "07:30", ""))
    }

    // Overlap with other shifts

    @Test fun overlapChecks() {
        val morning = closed(tin = "08:00", tout = "12:00")
        assertTrue(overlapsAny(at(today, "11:00"), at(today, "13:00"), listOf(morning), now, zone))
        assertFalse("touching is fine", overlapsAny(at(today, "12:00"), at(today, "13:00"), listOf(morning), now, zone))
        val running = open(tin = "14:00")
        assertTrue("a running shift lasts until now", overlapsAny(at(today, "17:00"), at(today, "17:30"), listOf(running), now, zone))
        assertFalse(overlapsAny(at(today, "12:30"), at(today, "13:30"), listOf(morning, running), now, zone))
    }
}
