package com.dude555afk.orvia

import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.IBinder

class OAuthBrowserService : Service() {
    private val binder = Binder()
    override fun onBind(intent: Intent?): IBinder = binder
}