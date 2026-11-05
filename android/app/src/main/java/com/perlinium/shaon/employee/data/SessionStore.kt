package com.perlinium.shaon.employee.data

import android.content.Context
import com.google.android.gms.auth.blockstore.Blockstore
import com.google.android.gms.auth.blockstore.RetrieveBytesRequest
import com.google.android.gms.auth.blockstore.StoreBytesData
import kotlinx.coroutines.tasks.await
import org.json.JSONObject

/**
 * Where the phone remembers which manager/employee it belongs to.
 *  - SharedPreferences: the normal place (also covered by Android's own backup).
 *  - Google Block Store: survives uninstall/reinstall and moves to a new phone with the user's backup,
 *    so the app can reconnect by itself ("connect once, forever").
 */
class SessionStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("session", Context.MODE_PRIVATE)
    private val blockstore = Blockstore.getClient(context)

    private fun Session.json() = JSONObject()
        .put("ownerUid", ownerUid).put("empId", empId).put("empName", empName)
        .put("keyId", keyId).put("deviceUid", deviceUid).toString()

    private fun parse(s: String?): Session? = runCatching {
        val j = JSONObject(s ?: return null)
        Session(j.getString("ownerUid"), j.getString("empId"), j.optString("empName"), j.getString("keyId"), j.getString("deviceUid"))
    }.getOrNull()

    fun local(): Session? = parse(prefs.getString("session", null))

    suspend fun save(s: Session) {
        prefs.edit().putString("session", s.json()).commit()
        runCatching {
            blockstore.storeBytes(
                StoreBytesData.Builder().setKey(KEY).setBytes(s.json().toByteArray()).setShouldBackupToCloud(true).build()
            ).await()
        }
    }

    /** The session kept by Block Store (after a reinstall or on a new phone). */
    suspend fun fromBlockStore(): Session? = runCatching {
        val res = blockstore.retrieveBytes(RetrieveBytesRequest.Builder().setKeys(listOf(KEY)).build()).await()
        res.blockstoreDataMap[KEY]?.bytes?.let { parse(String(it)) }
    }.getOrNull()

    suspend fun clear() {
        prefs.edit().remove("session").commit()
        runCatching {
            blockstore.deleteBytes(com.google.android.gms.auth.blockstore.DeleteBytesRequest.Builder().setKeys(listOf(KEY)).build()).await()
        }
    }

    private companion object { const val KEY = "shaon_session" }
}
