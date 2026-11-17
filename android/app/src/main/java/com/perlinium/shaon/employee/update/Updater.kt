package com.perlinium.shaon.employee.update

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import androidx.core.content.FileProvider
import com.perlinium.shaon.employee.BuildConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** A version published by tools/release-android.sh to Firebase Hosting (public/android/latest.json). */
data class Release(val versionCode: Int, val versionName: String, val url: String, val sha256: String, val size: Long)

/**
 * Updates without the Play Store: the app reads latest.json on Firebase Hosting, and when there is a newer
 * version it shows "יש גרסה חדשה". One tap downloads it, checks it is exactly the published file (size + SHA-256,
 * our package, the announced version) and opens Android's own installer. Android itself refuses an update
 * that is not signed with the same release key, so a wrong file can never replace the app.
 */
object Updater {
    sealed interface State {
        data object Idle : State
        data class Available(val release: Release) : State
        data class Downloading(val release: Release, val percent: Int) : State
        data class Ready(val release: Release, val file: File) : State
        data class Failed(val release: Release) : State
    }

    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> = _state

    /** Asks the screen to open the installer (only heard while the app is on screen). */
    private val _openInstaller = MutableSharedFlow<File>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val openInstaller: SharedFlow<File> = _openInstaller

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var job: Job? = null
    private var lastCheck = 0L

    /** A debug build is signed with the debug key, so the release APK could never install over it. */
    val enabled: Boolean get() = BuildConfig.UPDATE_FEED.isNotEmpty()

    /** Called whenever the app comes to the screen; quiet on any failure (no network = try next time). */
    fun check(ctx: Context) {
        if (!enabled) return
        val busy = _state.value.let { it is State.Downloading || it is State.Ready }
        val now = SystemClock.elapsedRealtime()
        if (busy || job?.isActive == true || (lastCheck != 0L && now - lastCheck < 10 * 60_000)) return
        lastCheck = now
        val app = ctx.applicationContext
        job = scope.launch {
            val release = runCatching { parse(get(BuildConfig.UPDATE_FEED), BuildConfig.UPDATE_FEED) }.getOrNull() ?: return@launch
            if (isNewer(release, BuildConfig.VERSION_CODE)) {
                if (_state.value !is State.Downloading && _state.value !is State.Ready) _state.value = State.Available(release)
            } else {
                _state.value = State.Idle
                dir(app).deleteRecursively()   // an update that already went in
            }
        }
    }

    /** The tap on "לעדכן": download, verify, then hand over to Android's installer. */
    fun download(ctx: Context) {
        val release = when (val s = _state.value) {
            is State.Available -> s.release
            is State.Failed -> s.release
            is State.Ready -> if (s.file.exists()) { _openInstaller.tryEmit(s.file); return } else s.release   // cache cleared: fetch again
            else -> return
        }
        val app = ctx.applicationContext
        _state.value = State.Downloading(release, 0)
        job = scope.launch {
            val file = runCatching { fetch(app, release) }.getOrNull()
            if (file == null) { _state.value = State.Failed(release); return@launch }
            _state.value = State.Ready(release, file)
            _openInstaller.tryEmit(file)
        }
    }

    /** Android's installer shows "לעדכן את האפליקציה?"; the first time it also asks to allow updates from this app. */
    fun install(ctx: Context, file: File): Boolean {
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.updates", file)
        val i = Intent(Intent.ACTION_VIEW).setDataAndType(uri, APK_TYPE)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try { ctx.startActivity(i); true } catch (_: ActivityNotFoundException) { false }
    }

    // ---- pure parts (unit tested) ----

    /** latest.json -> Release, or null when anything is missing or odd. A relative url is relative to the feed. */
    fun parse(json: String, feedUrl: String): Release? = runCatching {
        val o = JSONObject(json)
        val code = o.getInt("versionCode")
        val name = o.getString("versionName")
        val sha = o.getString("sha256").lowercase()
        val size = o.getLong("size")
        val url = URL(URL(feedUrl), o.getString("url")).toString()
        if (code <= 0 || name.isBlank() || size <= 0 || !SHA256.matches(sha)) return null
        if (!url.startsWith("https://") && !BuildConfig.USE_EMULATOR) return null
        Release(code, name, url, sha, size)
    }.getOrNull()

    fun isNewer(r: Release, currentVersionCode: Int) = r.versionCode > currentVersionCode

    fun sha256Hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }

    // ---- network / files ----

    private const val APK_TYPE = "application/vnd.android.package-archive"
    private val SHA256 = Regex("^[0-9a-f]{64}$")
    private const val MAX_SIZE = 100L * 1024 * 1024

    private fun dir(ctx: Context) = File(ctx.cacheDir, "updates")

    private fun open(url: String): HttpURLConnection = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = 15_000; readTimeout = 30_000; useCaches = false
        setRequestProperty("Cache-Control", "no-cache")
    }

    private fun get(url: String): String {
        val c = open(url)
        try {
            if (c.responseCode != 200) error("HTTP ${c.responseCode}")
            return c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
        } finally { c.disconnect() }
    }

    private fun fetch(ctx: Context, r: Release): File {
        require(r.size in 1..MAX_SIZE)
        val d = dir(ctx).apply { deleteRecursively(); mkdirs() }
        val part = File(d, "shaon-${r.versionCode}.part")
        val apk = File(d, "shaon-${r.versionCode}.apk")
        val md = MessageDigest.getInstance("SHA-256")
        val c = open(r.url)
        try {
            if (c.responseCode != 200) error("HTTP ${c.responseCode}")
            var done = 0L
            c.inputStream.use { input ->
                part.outputStream().use { out ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        done += n
                        if (done > r.size) error("bigger than announced")
                        md.update(buf, 0, n); out.write(buf, 0, n)
                        _state.value = State.Downloading(r, (done * 100 / r.size).toInt())
                    }
                }
            }
            if (done != r.size) error("size $done != ${r.size}")
        } finally { c.disconnect() }
        if (sha256Hex(md.digest()) != r.sha256) { part.delete(); error("checksum") }
        // Exactly the version that was announced, and our own app (not just any APK at that address).
        val info = if (Build.VERSION.SDK_INT >= 33)
            ctx.packageManager.getPackageArchiveInfo(part.path, android.content.pm.PackageManager.PackageInfoFlags.of(0))
        else @Suppress("DEPRECATION") ctx.packageManager.getPackageArchiveInfo(part.path, 0)
        @Suppress("DEPRECATION")
        val vc = info?.let { if (Build.VERSION.SDK_INT >= 28) it.longVersionCode.toInt() else it.versionCode }
        if (info?.packageName != ctx.packageName || vc != r.versionCode) { part.delete(); error("not our APK") }
        if (!part.renameTo(apk)) error("rename")
        return apk
    }
}
