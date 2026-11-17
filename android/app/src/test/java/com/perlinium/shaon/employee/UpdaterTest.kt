package com.perlinium.shaon.employee

import com.perlinium.shaon.employee.update.Release
import com.perlinium.shaon.employee.update.Updater
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest

class UpdaterTest {
    private val feed = "https://shaon-ovdot-2c10.web.app/android/latest.json"
    private val sha = "a".repeat(64)
    private fun json(vararg kv: Pair<String, Any>) = org.json.JSONObject(kv.toMap()).toString()
    private val good = arrayOf("versionCode" to 4, "versionName" to "1.3", "url" to "shaon.apk", "sha256" to sha, "size" to 4_200_000)

    @Test fun parsesTheFileTheReleaseScriptWrites() {
        val r = Updater.parse(json(*good), feed)!!
        assertEquals(Release(4, "1.3", "https://shaon-ovdot-2c10.web.app/android/shaon.apk", sha, 4_200_000), r)
    }

    @Test fun absoluteHttpsUrlIsKept() {
        val r = Updater.parse(json(*good, "url" to "https://example.com/x.apk"), feed)!!
        assertEquals("https://example.com/x.apk", r.url)
    }

    @Test fun refusesPlainHttpOutsideTests() {
        assertNull(Updater.parse(json(*good, "url" to "http://example.com/x.apk"), feed))
    }

    @Test fun refusesMissingOrOddFields() {
        assertNull(Updater.parse("not json", feed))
        assertNull(Updater.parse("{}", feed))
        assertNull(Updater.parse(json(*good, "sha256" to "xyz"), feed))
        assertNull(Updater.parse(json(*good, "sha256" to "A".repeat(63)), feed))
        assertNull(Updater.parse(json(*good, "size" to 0), feed))
        assertNull(Updater.parse(json(*good, "versionCode" to 0), feed))
        assertNull(Updater.parse(json(*good, "versionName" to " "), feed))
    }

    @Test fun uppercaseChecksumIsAccepted() {
        assertEquals(sha, Updater.parse(json(*good, "sha256" to sha.uppercase()), feed)!!.sha256)
    }

    @Test fun onlyAHigherVersionCodeIsAnUpdate() {
        val r = Updater.parse(json(*good), feed)!!
        assertTrue(Updater.isNewer(r, 3))
        assertFalse(Updater.isNewer(r, 4))   // already installed
        assertFalse(Updater.isNewer(r, 5))   // never "update" to an older version
    }

    @Test fun sha256MatchesShasum() {
        val d = MessageDigest.getInstance("SHA-256").digest("abc".toByteArray())
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", Updater.sha256Hex(d))
    }
}
