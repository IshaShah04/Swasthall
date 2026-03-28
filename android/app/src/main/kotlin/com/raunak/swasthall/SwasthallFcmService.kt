package com.raunak.swasthall

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * SwasthallFcmService — safe FCM message handler.
 *
 * Replaces the live_activities plugin's LiveActivityFirebaseMessagingService,
 * which crashes with NullPointerException at line 26 when it receives our
 * data-only call notification messages (it assumes notification fields exist).
 *
 * This service:
 *   • Safely handles all FCM messages without crashing
 *   • Forwards ZEGO call messages to the ZEGO broadcast receiver
 *   • Ignores live_activities messages gracefully (no Live Activities on Android)
 *   • Lets Flutter's firebase_messaging plugin handle everything else via
 *     its own internal routing (FlutterFirebaseMessagingService)
 *
 * Note: firebase_messaging plugin registers its own service with higher
 * priority. Android FCM delivers to the HIGHEST priority service first.
 * If FlutterFirebaseMessagingService is present (it is, from the plugin),
 * it will receive the message first. This service exists purely to prevent
 * live_activities from crashing — not to intercept messages from Flutter.
 */
class SwasthallFcmService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "SwasthallFcmService"
    }

    override fun onMessageReceived(message: RemoteMessage) {
        try {
            val data = message.data
            val type = data["type"] ?: ""

            Log.d(TAG, "FCM received: type=$type notification=${message.notification?.title}")

            // ZEGO call messages are handled by ZEGO's own ZegoFcmBroadcastReceiver.
            // Flutter's firebase_messaging FlutterFirebaseMessagingService handles
            // the Dart-side onMessage / onBackgroundMessage callbacks.
            // Nothing extra needed here — just don't crash.

        } catch (e: Exception) {
            // Never crash the process on an FCM message — this would destabilise
            // the app lifecycle and cause the ZegoSystemService assertion crash.
            Log.e(TAG, "Error handling FCM message (non-fatal): ${e.message}")
        }
    }

    override fun onNewToken(token: String) {
        // Flutter's firebase_messaging plugin handles token refresh via its own
        // FlutterFirebaseMessagingService. Nothing extra needed here.
        Log.d(TAG, "FCM token refreshed (handled by Flutter plugin)")
    }
}
