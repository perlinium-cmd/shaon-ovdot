package com.perlinium.shaon.employee.data

import android.content.Context
import android.os.Build
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.MetadataChanges
import com.google.firebase.firestore.Source
import com.perlinium.shaon.employee.logic.Direct
import com.perlinium.shaon.employee.logic.dateStr
import com.perlinium.shaon.employee.logic.hm
import com.perlinium.shaon.employee.logic.monthStr
import com.perlinium.shaon.employee.logic.nowLocal
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import java.security.SecureRandom

sealed interface Phase {
    data object Loading : Phase
    /** Not connected to a manager yet (or was disconnected). */
    data class NeedsPairing(val message: String? = null) : Phase
    /** Has a saved connection but needs internet once to restore it. */
    data object NeedsNetwork : Phase
    data object Ready : Phase
}

/** Everything the phone reads and writes. One instance for the whole app (screens, widget, tile, notifications). */
object Repo {
    private lateinit var store: SessionStore
    private lateinit var appContext: Context
    private val auth get() = FirebaseAuth.getInstance()
    private val db get() = FirebaseFirestore.getInstance()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val startLock = Mutex()
    private val listeners = mutableListOf<ListenerRegistration>()
    private var monthListener: ListenerRegistration? = null
    @Volatile private var started = false

    private val _phase = MutableStateFlow<Phase>(Phase.Loading)
    val phase = _phase.asStateFlow()
    val session = MutableStateFlow<Session?>(null)
    val employee = MutableStateFlow<Employee?>(null)
    val settings = MutableStateFlow(Settings(null, null))
    /** The running shift (clocked in, not out). Includes clock-ins that were saved offline. */
    val openShift = MutableStateFlow<Shift?>(null)
    val openLoaded = MutableStateFlow(false)
    val month = MutableStateFlow(monthStr(nowLocal().toLocalDate()))
    val monthShifts = MutableStateFlow<List<Shift>?>(null)
    val payments = MutableStateFlow<List<Payment>>(emptyList())
    val requests = MutableStateFlow<List<ShiftRequest>>(emptyList())
    /** A write the server refused. Shown in red until dismissed, so nothing fails silently. */
    val writeError = MutableStateFlow<String?>(null)
    /** Latest shift list of the current month, incl. the last finished shift, for "last time" hints. */
    val recentShifts = MutableStateFlow<List<Shift>>(emptyList())

    fun init(context: Context) {
        if (::store.isInitialized) return
        appContext = context.applicationContext
        store = SessionStore(appContext)
    }

    // ---------------- start / connect ----------------

    fun start() { scope.launch { ensureStarted() } }

    suspend fun ensureStarted() = startLock.withLock {
        if (started && _phase.value == Phase.Ready) return@withLock
        val local = store.local()
        val user = auth.currentUser
        if (local != null && user != null && user.uid == local.deviceUid) {
            ready(local); return@withLock
        }
        val saved = local ?: store.fromBlockStore() ?: runCatching { fromRestoreCard() }.getOrNull()
        if (saved == null) { _phase.value = Phase.NeedsPairing(); return@withLock }
        try {
            ready(reconnect(saved))
        } catch (e: Revoked) {
            store.clear(); _phase.value = Phase.NeedsPairing("החיבור לטלפון הזה בוטל במחשב. כדי להתחבר שוב צריך קוד חדש.")
        } catch (e: Exception) {
            _phase.value = if (e.isNetwork()) Phase.NeedsNetwork else Phase.NeedsPairing("לא הצלחנו לשחזר את החיבור. צריך קוד חדש מהמחשב.")
        }
    }

    private class Revoked : Exception()

    private fun Exception.isNetwork() = this is FirebaseNetworkException ||
        (this is FirebaseFirestoreException && code == FirebaseFirestoreException.Code.UNAVAILABLE) ||
        cause is FirebaseNetworkException

    /**
     * Restore card id: a hash of this app's Android ID. That ID is the same after uninstall/reinstall
     * (same signing key), is different for every app, and other apps can't read it.
     */
    private fun restoreId(): String? {
        val aid = android.provider.Settings.Secure.getString(appContext.contentResolver, android.provider.Settings.Secure.ANDROID_ID) ?: return null
        val d = java.security.MessageDigest.getInstance("SHA-256").digest("shaon-restore:$aid".toByteArray())
        return d.joinToString("") { "%02x".format(it) }
    }

    private suspend fun fromRestoreCard(): Session? {
        val rid = restoreId() ?: return null
        auth.currentUser ?: auth.signInAnonymously().await()
        val c = db.document("restore/$rid").get(Source.SERVER).await()
        if (!c.exists()) return null
        return Session(c.getString("ownerUid") ?: return null, c.getString("empId") ?: return null,
            c.getString("empName") ?: "", c.getString("keyId") ?: return null, c.getString("deviceUid") ?: "")
    }

    private fun writeRestoreCard(s: Session) {
        val rid = restoreId() ?: return
        db.document("restore/$rid").set(mapOf(
            "ownerUid" to s.ownerUid, "empId" to s.empId, "empName" to s.empName, "keyId" to s.keyId, "deviceUid" to s.deviceUid,
        ))   // best effort; the next start writes it again
    }

    private fun deviceModel() = "${Build.MANUFACTURER} ${Build.MODEL}".trim().take(80)

    /** After a reinstall / on a new phone: sign in again and move the saved key to this install. */
    private suspend fun reconnect(saved: Session): Session {
        val uid = (auth.currentUser ?: auth.signInAnonymously().await().user)!!.uid
        val dev = db.document("users/${saved.ownerUid}/devices/$uid").get(Source.SERVER).await()
        if (dev.exists()) return saved.copy(deviceUid = uid).also { store.save(it) }   // same install, prefs were lost

        val keyRef = db.document("users/${saved.ownerUid}/deviceKeys/${saved.keyId}")
        val key = try { keyRef.get(Source.SERVER).await() } catch (e: FirebaseFirestoreException) {
            if (e.code == FirebaseFirestoreException.Code.PERMISSION_DENIED) throw Revoked() else throw e
        }
        if (!key.exists()) throw Revoked()
        val empId = key.getString("empId") ?: throw Revoked()
        suspend fun commit(deleteOld: Boolean) = db.batch().apply {
            set(db.document("users/${saved.ownerUid}/devices/$uid"),
                mapOf("empId" to empId, "keyId" to saved.keyId, "model" to deviceModel(), "pairedAt" to FieldValue.serverTimestamp()))
            update(keyRef, "deviceId", uid)
            if (deleteOld && saved.deviceUid.isNotBlank() && saved.deviceUid != uid) delete(db.document("users/${saved.ownerUid}/devices/${saved.deviceUid}"))
        }.commit().await()
        try { commit(deleteOld = true) } catch (e: FirebaseFirestoreException) {
            if (e.code != FirebaseFirestoreException.Code.PERMISSION_DENIED) throw e
            commit(deleteOld = false)   // the old record was already removed
        }
        return saved.copy(empId = empId, deviceUid = uid).also { store.save(it) }
    }

    sealed interface PairResult {
        data object Ok : PairResult
        data class Failed(val message: String) : PairResult
    }

    /** First connection with the code shown on the manager's Mac. */
    suspend fun pair(rawCode: String): PairResult {
        val code = rawCode.uppercase().filter { it.isLetterOrDigit() }
        if (code.length != 8) return PairResult.Failed("הקוד צריך להיות 8 תווים, כמו שמופיע במחשב")
        return try {
            val uid = (auth.currentUser ?: auth.signInAnonymously().await().user)!!.uid
            val pRef = db.document("pairings/$code")
            val p = try { pRef.get(Source.SERVER).await() } catch (e: FirebaseFirestoreException) {
                if (e.code == FirebaseFirestoreException.Code.PERMISSION_DENIED) return PairResult.Failed("הקוד לא תקף. ייתכן שפג תוקפו (10 דקות) או שכבר השתמשו בו. צרו קוד חדש במחשב.")
                throw e
            }
            val ownerUid = p.getString("ownerUid") ?: return PairResult.Failed("הקוד לא תקף. צרו קוד חדש במחשב.")
            val empId = p.getString("empId")!!
            val keyId = randomKey()
            db.batch().apply {
                set(db.document("users/$ownerUid/devices/$uid"), mapOf(
                    "empId" to empId, "pairCode" to code, "keyId" to keyId, "model" to deviceModel(), "pairedAt" to FieldValue.serverTimestamp()))
                set(db.document("users/$ownerUid/deviceKeys/$keyId"), mapOf(
                    "empId" to empId, "deviceId" to uid, "createdAt" to FieldValue.serverTimestamp()))
                update(pRef, mapOf("usedBy" to uid, "usedAt" to FieldValue.serverTimestamp()))
            }.commit().await()
            val s = Session(ownerUid, empId, p.getString("empName") ?: "", keyId, uid)
            store.save(s)
            startLock.withLock { ready(s) }
            PairResult.Ok
        } catch (e: Exception) {
            if (e.isNetwork()) PairResult.Failed("אין חיבור לאינטרנט. החיבור הראשון צריך אינטרנט, אחרי זה אפשר גם בלי.")
            else PairResult.Failed("החיבור לא הצליח. נסי שוב עם קוד חדש מהמחשב.")
        }
    }

    private fun randomKey(): String {
        val abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        val r = SecureRandom()
        return (1..48).map { abc[r.nextInt(abc.length)] }.joinToString("")
    }

    // ---------------- live data ----------------

    private fun base(s: Session) = "users/${s.ownerUid}"

    private fun ready(s: Session) {
        session.value = s
        writeRestoreCard(s)
        detach()
        val b = base(s)
        listeners += db.document("$b/devices/${s.deviceUid}").addSnapshotListener(MetadataChanges.INCLUDE) { snap, _ ->
            // The manager disconnected this phone (deleted its record). Only trust the server, not the cache.
            if (snap != null && !snap.exists() && !snap.metadata.isFromCache) scope.launch { disconnected() }
        }
        listeners += db.document("$b/employees/${s.empId}").addSnapshotListener { snap, _ -> snap?.toEmployee()?.let { employee.value = it } }
        listeners += db.document("$b/settings/main").addSnapshotListener { snap, _ -> snap?.let { settings.value = it.toSettings() } }
        listeners += db.collection("$b/shifts").whereEqualTo("empId", s.empId).whereEqualTo("open", true)
            .addSnapshotListener(MetadataChanges.INCLUDE) { snap, _ ->
                if (snap == null) return@addSnapshotListener
                openShift.value = snap.documents.mapNotNull { it.toShift() }.maxByOrNull { it.inAt ?: 0 }
                openLoaded.value = true
            }
        listeners += db.collection("$b/payments").whereEqualTo("empId", s.empId).addSnapshotListener { snap, _ ->
            payments.value = snap?.documents?.mapNotNull { it.toPayment() }?.sortedByDescending { it.date } ?: payments.value
        }
        listeners += db.collection("$b/requests").whereEqualTo("empId", s.empId).addSnapshotListener(MetadataChanges.INCLUDE) { snap, _ ->
            requests.value = snap?.documents?.mapNotNull { it.toRequest() }?.sortedByDescending { it.createdAt ?: Long.MAX_VALUE } ?: requests.value
        }
        watchMonth(month.value)
        started = true
        _phase.value = Phase.Ready
    }

    fun setMonth(m: String) { month.value = m; session.value?.let { watchMonth(m) } }

    private fun watchMonth(m: String) {
        val s = session.value ?: return
        monthListener?.remove()
        monthShifts.value = null
        monthListener = db.collection("${base(s)}/shifts").whereEqualTo("empId", s.empId).whereEqualTo("month", m)
            .addSnapshotListener(MetadataChanges.INCLUDE) { snap, _ ->
                val list = snap?.documents?.mapNotNull { it.toShift() }?.sortedWith(compareByDescending<Shift> { it.date }.thenByDescending { it.`in` }) ?: return@addSnapshotListener
                monthShifts.value = list
                if (m == monthStr(nowLocal().toLocalDate())) recentShifts.value = list
            }
    }

    private fun detach() { listeners.forEach { it.remove() }; listeners.clear(); monthListener?.remove(); monthListener = null }

    private suspend fun disconnected() {
        detach()
        store.clear()
        session.value = null; employee.value = null; openShift.value = null; monthShifts.value = null
        started = false
        _phase.value = Phase.NeedsPairing("הטלפון נותק מהמחשב של המנהל. כדי להתחבר שוב צריך קוד חדש.")
    }

    // ---------------- clock in / out ----------------

    /**
     * For buttons that act while the app is closed (tile, widget, notification): wait until we know whether a shift
     * is running. If the live listener is slow (cold start after a reboot, no signal) ask the on-phone cache directly.
     * false = still unknown — then the caller does nothing, so an "exit" tap can never become a second clock-in.
     */
    suspend fun awaitOpenLoaded(timeoutMs: Long): Boolean {
        if (openLoaded.value || withTimeoutOrNull(timeoutMs) { openLoaded.first { it } } != null) return true
        val s = session.value ?: return false
        return try {
            val snap = db.collection("${base(s)}/shifts").whereEqualTo("empId", s.empId).whereEqualTo("open", true)
                .get(Source.CACHE).await()
            if (!openLoaded.value) {
                openShift.value = snap.documents.mapNotNull { it.toShift() }.maxByOrNull { it.inAt ?: 0 }
                openLoaded.value = true
            }
            true
        } catch (e: Exception) { false }
    }

    private fun fail(what: String): (Exception) -> Unit = { e ->
        writeError.value = "$what לא נשמרה בשרת. ${if (e is FirebaseFirestoreException && e.code == FirebaseFirestoreException.Code.PERMISSION_DENIED) "המנהל צריך לבדוק את החיבור של הטלפון." else "נסי שוב."}"
    }

    /** Saved on the phone instantly (works without reception) and sent to the server when possible. Returns the shift id. */
    fun clockIn(): String? {
        val s = session.value ?: return null
        if (!openLoaded.value || openShift.value != null) return null   // never two running shifts
        val now = System.currentTimeMillis()
        val t = nowLocal(now)
        val ref = db.collection("${base(s)}/shifts").document()
        val shift = Shift(id = ref.id, empId = s.empId, date = dateStr(t.toLocalDate()), month = monthStr(t.toLocalDate()),
            `in` = hm(t.toLocalTime()), out = "", open = true, source = "phone", inAt = now, pending = true)
        openShift.value = shift   // instant UI, before the listener catches up
        ref.set(mapOf(
            "empId" to s.empId, "date" to shift.date, "month" to shift.month, "in" to shift.`in`, "out" to "",
            "inAt" to now, "syncedAt" to FieldValue.serverTimestamp(), "source" to "phone", "open" to true,
            "deviceId" to s.deviceUid, "createdAt" to now,
        )).addOnFailureListener(fail("הכניסה"))
        return ref.id
    }

    fun clockOut(shift: Shift): String? {
        val s = session.value ?: return null
        val now = System.currentTimeMillis()
        val out = hm(nowLocal(now).toLocalTime())
        openShift.value = null
        db.document("${base(s)}/shifts/${shift.id}").update(mapOf(
            "out" to out, "outAt" to maxOf(now, shift.inAt ?: now), "outSyncedAt" to FieldValue.serverTimestamp(), "open" to false,
        )).addOnFailureListener(fail("היציאה"))
        return out
    }

    /** Undo a clock-in pressed by mistake (only right after it). */
    fun undoClockIn(id: String) {
        val s = session.value ?: return
        if (openShift.value?.id == id) openShift.value = null
        db.document("${base(s)}/shifts/$id").delete().addOnFailureListener(fail("הביטול"))
    }

    /** Undo a clock-out pressed by mistake: the shift keeps running. */
    fun undoClockOut(shift: Shift) {
        val s = session.value ?: return
        openShift.value = shift.copy(out = "", open = true)
        db.document("${base(s)}/shifts/${shift.id}").update(mapOf(
            "out" to "", "outAt" to FieldValue.delete(), "outSyncedAt" to FieldValue.delete(), "open" to true,
        )).addOnFailureListener(fail("הביטול"))
    }

    // ---------------- saved without approval (see logic/Direct.kt) ----------------

    private fun noticeData(s: Session, type: String, shiftId: String, date: String, tin: String, tout: String) = mutableMapOf<String, Any>(
        "empId" to s.empId, "type" to type, "shiftId" to shiftId, "date" to date, "in" to tin, "out" to tout,
        "createdAt" to FieldValue.serverTimestamp(), "deviceId" to s.deviceUid,
    )

    /** A forgotten shift typed in on the day it ended. Saved on the phone at once, like a clock-in. */
    fun addManualShift(date: String, tin: String, tout: String, d: Direct): Boolean {
        val s = session.value ?: return false
        val ref = db.collection("${base(s)}/shifts").document()
        val notice = db.collection("${base(s)}/notices").document()
        db.batch().apply {
            set(ref, mapOf(
                "empId" to s.empId, "date" to date, "month" to date.substring(0, 7), "in" to tin, "out" to tout,
                "inAt" to d.inAt, "outAt" to (d.outAt ?: return false), "syncedAt" to FieldValue.serverTimestamp(),
                "source" to "phone", "open" to false, "manual" to true, "deviceId" to s.deviceUid,
                "createdAt" to System.currentTimeMillis(), "noticeId" to notice.id,
            ))
            set(notice, noticeData(s, "manual", ref.id, date, tin, tout))
        }.commit().addOnFailureListener(fail("המשמרת"))
        return true
    }

    /** Clock-in and/or clock-out moved earlier. A running shift either keeps running or is clocked out at [newOut]. */
    fun fixEarlier(shift: Shift, newIn: String, newOut: String, d: Direct): Boolean {
        val s = session.value ?: return false
        val ref = db.document("${base(s)}/shifts/${shift.id}")
        val notice = db.collection("${base(s)}/notices").document()
        val change = mutableMapOf<String, Any>("edited" to true, "noticeId" to notice.id)
        if (newIn != shift.`in`) { change["in"] = newIn; change["inAt"] = d.inAt }
        val closes = shift.open && d.outAt != null
        if (d.outAt != null && (shift.open || newOut != shift.out)) { change["out"] = newOut; change["outAt"] = d.outAt }
        if (closes) { change["outSyncedAt"] = FieldValue.serverTimestamp(); change["open"] = false }
        if (shift.open) openShift.value = if (closes) null else shift.copy(`in` = newIn, inAt = d.inAt)   // instant UI
        db.batch().apply {
            update(ref, change)
            set(notice, noticeData(s, "fix", shift.id, shift.date, newIn, if (closes || !shift.open) newOut else "").apply {
                put("prevIn", shift.`in`); put("prevOut", shift.out)
            })
        }.commit().addOnFailureListener(fail("המשמרת"))
        return true
    }

    // ---------------- requests ----------------

    fun sendRequest(type: String, shiftId: String?, date: String, tin: String, tout: String, note: String) {
        val s = session.value ?: return
        val data = mutableMapOf<String, Any>(
            "empId" to s.empId, "type" to type, "date" to date, "in" to tin, "out" to tout,
            "status" to "pending", "createdAt" to FieldValue.serverTimestamp(), "deviceId" to s.deviceUid,
        )
        if (shiftId != null) data["shiftId"] = shiftId
        if (note.isNotBlank()) data["note"] = note.trim().take(500)
        db.collection("${base(s)}/requests").add(data).addOnFailureListener(fail("הבקשה"))
    }

    fun cancelRequest(id: String) {
        val s = session.value ?: return
        db.document("${base(s)}/requests/$id").update(mapOf("status" to "cancelled", "decidedAt" to FieldValue.serverTimestamp()))
            .addOnFailureListener(fail("ביטול הבקשה"))
    }
}
