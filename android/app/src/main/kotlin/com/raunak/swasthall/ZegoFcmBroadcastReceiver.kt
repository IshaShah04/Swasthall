package com.raunak.swasthall

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ZegoFcmBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val remoteMessage = intent.getParcelableExtra<com.google.firebase.messaging.RemoteMessage>("remoteMessage")
        Log.d("ZegoFcmReceiver", "Non-ZEGO FCM: ${remoteMessage?.data}")
    }
}