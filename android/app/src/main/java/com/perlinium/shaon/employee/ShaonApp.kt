package com.perlinium.shaon.employee

import android.app.Application
import com.perlinium.shaon.employee.data.Repo
import com.perlinium.shaon.employee.work.CheckWorker
import com.perlinium.shaon.employee.work.Notifier
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

class ShaonApp : Application() {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.USE_EMULATOR) {   // test builds only: local Firebase emulators on the Mac
            com.google.firebase.auth.FirebaseAuth.getInstance().useEmulator("10.0.2.2", 9099)
            com.google.firebase.firestore.FirebaseFirestore.getInstance().useEmulator("10.0.2.2", 8080)
        }
        Notifier.channels(this)
        Repo.init(this)
        Repo.start()
        CheckWorker.schedule(this)
        // Keep the "on shift" notification in step with the real state (also for clock-ins from offline).
        MainScope().launch {
            Repo.openShift.collect { s ->
                if (s != null) Notifier.showShift(this@ShaonApp, s) else if (Repo.openLoaded.value) Notifier.clearShift(this@ShaonApp)
                com.perlinium.shaon.employee.work.ClockWidget.refresh(this@ShaonApp)   // keep the home-screen widget in step
            }
        }
    }
}
