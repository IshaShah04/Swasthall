package com.ishashah04.swasthall

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.IntentCompat
import com.ishashah04.swasthall.BuildConfig

class ZegoFcmBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val remoteMessage = IntentCompat.getParcelableExtra(
            intent,
            "remoteMessage",
            com.google.firebase.messaging.RemoteMessage::class.java,
        )

        if (BuildConfig.DEBUG) {
            Log.d(
                "ZegoFcmReceiver",
                "Non-ZEGO FCM keys: ${remoteMessage?.data?.keys ?: emptySet<String>()}",
            )
        }
    }
}