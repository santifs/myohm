package com.volumhealth.app

import android.app.Application
import com.volumhealth.app.background.AutoSyncObserver
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

@HiltAndroidApp
class VolumHealthApplication : Application() {
    @Inject lateinit var autoSyncObserver: AutoSyncObserver

    override fun onCreate() {
        super.onCreate()
        autoSyncObserver
    }
}
