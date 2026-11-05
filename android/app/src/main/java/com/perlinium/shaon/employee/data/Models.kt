package com.perlinium.shaon.employee.data

import com.google.firebase.Timestamp
import com.google.firebase.firestore.DocumentSnapshot

// Same collections and field names as the website and the Mac app (see firestore.rules).

data class Special(val rate: Double?, val hours: Double?)

data class Employee(val id: String, val name: String, val rate: Double?)

data class Settings(val defaultRate: Double?, val timeFormat: String?)

data class Shift(
    val id: String = "",
    val empId: String,
    val date: String,          // YYYY-MM-DD (day of clock-in)
    val month: String,         // YYYY-MM
    val `in`: String,          // HH:MM
    val out: String,           // HH:MM, "" while still clocked in
    val rate: Double? = null,
    val special: Special? = null,
    val paid: Boolean = false,
    val open: Boolean = false,
    val source: String? = null,
    val inAt: Long? = null,
    val outSyncedAt: Long? = null,
    val syncedAt: Long? = null,
    val note: String? = null,
    val fixedBy: String? = null,
    /** Saved on this phone but not on the server yet (no reception). */
    val pending: Boolean = false,
)

data class Payment(val id: String, val date: String, val amount: Double, val method: String?)

data class ShiftRequest(
    val id: String,
    val type: String,          // fix | add
    val shiftId: String?,
    val date: String,
    val `in`: String,
    val out: String,
    val note: String?,
    val status: String,        // pending | approved | rejected | cancelled
    val createdAt: Long?,
    val pending: Boolean = false,
)

/** Which manager space and employee this phone belongs to. Kept on the phone and in Block Store. */
data class Session(val ownerUid: String, val empId: String, val empName: String, val keyId: String, val deviceUid: String)

// ---- Firestore -> models (by hand, so release builds need no reflection rules) ----

private fun Any?.num(): Double? = (this as? Number)?.toDouble()
private fun Any?.ms(): Long? = when (this) {
    is Number -> toLong()
    is Timestamp -> toDate().time
    else -> null
}

fun DocumentSnapshot.toShift(): Shift? {
    val empId = getString("empId") ?: return null
    val sp = get("special") as? Map<*, *>
    return Shift(
        id = id, empId = empId,
        date = getString("date") ?: return null, month = getString("month") ?: "",
        `in` = getString("in") ?: "", out = getString("out") ?: "",
        rate = get("rate").num(),
        special = sp?.let { Special(it["rate"].num(), it["hours"].num()) },
        paid = getBoolean("paid") == true, open = getBoolean("open") == true,
        source = getString("source"), inAt = get("inAt").ms(),
        syncedAt = get("syncedAt").ms(), outSyncedAt = get("outSyncedAt").ms(),
        note = getString("note"), fixedBy = getString("fixedBy"),
        pending = metadata.hasPendingWrites(),
    )
}

fun DocumentSnapshot.toEmployee(): Employee? =
    if (!exists()) null else Employee(id, getString("name") ?: "", get("rate").num())

fun DocumentSnapshot.toSettings(): Settings = Settings(get("defaultRate").num(), getString("timeFormat"))

fun DocumentSnapshot.toPayment(): Payment? {
    val date = getString("date") ?: return null
    return Payment(id, date, get("amount").num() ?: 0.0, getString("method"))
}

fun DocumentSnapshot.toRequest(): ShiftRequest? {
    val type = getString("type") ?: return null
    return ShiftRequest(
    id = id, type = type, shiftId = getString("shiftId"),
    date = getString("date") ?: "", `in` = getString("in") ?: "", out = getString("out") ?: "",
    note = getString("note"), status = getString("status") ?: "pending", createdAt = get("createdAt").ms(),
    pending = metadata.hasPendingWrites(),
    )
}
