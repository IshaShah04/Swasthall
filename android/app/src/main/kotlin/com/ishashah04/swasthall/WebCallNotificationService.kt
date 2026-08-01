package com.ishashah04.swasthall

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

// ── WebCallNotificationService ────────────────────────────────────────────────
// Shows a WhatsApp-style full-screen incoming call notification for web→phone calls.
// Triggered by FCM background message handler via a broadcast.
// On Android 12+ uses CallStyle notification with system call UI.
// On older Android falls back to a high-priority heads-up notification.
//
// Flutter side sends: ACTION_SHOW_WEB_CALL broadcast with extras:
//   callerName, callId, bookingId
// User taps Accept → MainActivity gets EXTRA_WEB_CALL_ACCEPT=true
// User taps Decline → notification dismissed, Flutter told via broadcast

class WebCallNotificationService : BroadcastReceiver() {

    companion object {
        const val ACTION_SHOW_WEB_CALL    = "com.ishashah04.swasthall.SHOW_WEB_CALL"
        const val ACTION_ACCEPT_WEB_CALL  = "com.ishashah04.swasthall.ACCEPT_WEB_CALL"
        const val ACTION_DECLINE_WEB_CALL = "com.ishashah04.swasthall.DECLINE_WEB_CALL"

        const val EXTRA_CALLER_NAME = "callerName"
        const val EXTRA_CALL_ID     = "callId"
        const val EXTRA_BOOKING_ID  = "bookingId"

        const val NOTIFICATION_ID   = 9001
        const val CHANNEL_ID        = "web_incoming_call"
        const val CHANNEL_NAME      = "Incoming Web Calls"

        fun showIncomingCallNotification(
            context: Context,
            callerName: String,
            callId: String,
            bookingId: String,
        ) {
            createChannel(context)

            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // ── Accept PendingIntent: opens app and passes accept flag ────────
            val acceptIntent = Intent(context, MainActivity::class.java).apply {
                action = ACTION_ACCEPT_WEB_CALL
                flags  = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra(EXTRA_CALLER_NAME, callerName)
                putExtra(EXTRA_CALL_ID,     callId)
                putExtra(EXTRA_BOOKING_ID,  bookingId)
            }
            val acceptPi = PendingIntent.getActivity(
                context, 1, acceptIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // ── Decline PendingIntent: broadcast to dismiss ────────────────────
            val declineIntent = Intent(context, WebCallNotificationService::class.java).apply {
                action = ACTION_DECLINE_WEB_CALL
                putExtra(EXTRA_CALL_ID, callId)
            }
            val declinePi = PendingIntent.getBroadcast(
                context, 2, declineIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // ── Full-screen intent: shows on lock screen ──────────────────────
            val fullScreenIntent = Intent(context, MainActivity::class.java).apply {
                action = ACTION_SHOW_WEB_CALL
                flags  = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra(EXTRA_CALLER_NAME, callerName)
                putExtra(EXTRA_CALL_ID,     callId)
                putExtra(EXTRA_BOOKING_ID,  bookingId)
            }
            val fullScreenPi = PendingIntent.getActivity(
                context, 3, fullScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Android 12+ — CallStyle notification (WhatsApp-style)
                buildCallStyleNotification(
                    context, callerName, acceptPi, declinePi, fullScreenPi
                )
            } else {
                // Android < 12 — high-priority heads-up with action buttons
                buildLegacyNotification(
                    context, callerName, acceptPi, declinePi, fullScreenPi
                )
            }

            nm.notify(NOTIFICATION_ID, notification)
        }

        @RequiresApi(Build.VERSION_CODES.S)
        private fun buildCallStyleNotification(
            context: Context,
            callerName: String,
            acceptPi: PendingIntent,
            declinePi: PendingIntent,
            fullScreenPi: PendingIntent,
        ): Notification {
            val caller = Person.Builder()
                .setName(callerName)
                .setImportant(true)
                .build()

            return Notification.Builder(context, CHANNEL_ID)
                .setStyle(
                    Notification.CallStyle.forIncomingCall(caller, declinePi, acceptPi)
                        .setAnswerButtonColorHint(0xFF4CAF50.toInt())
                        .setDeclineButtonColorHint(0xFFF44336.toInt())
                )
                .setSmallIcon(android.R.drawable.ic_menu_call)
                .setFullScreenIntent(fullScreenPi, true)
                .setOngoing(true)
                .setAutoCancel(false)
                .build()
        }

        private fun buildLegacyNotification(
            context: Context,
            callerName: String,
            acceptPi: PendingIntent,
            declinePi: PendingIntent,
            fullScreenPi: PendingIntent,
        ): Notification {
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle("Incoming call")
                .setContentText("$callerName is calling you")
                .setSmallIcon(android.R.drawable.ic_menu_call)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setFullScreenIntent(fullScreenPi, true)
                .setOngoing(true)
                .setAutoCancel(false)
                .addAction(
                    android.R.drawable.ic_menu_call, "Accept", acceptPi
                )
                .addAction(
                    android.R.drawable.ic_delete, "Decline", declinePi
                )
                .build()
        }

        fun dismissNotification(context: Context) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(NOTIFICATION_ID)
        }

        private fun createChannel(context: Context) {
            val channel = NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description         = "Incoming video calls from web"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setSound(
                    android.provider.Settings.System.DEFAULT_RINGTONE_URI,
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 500, 500)
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    // ── BroadcastReceiver: handle decline action ──────────────────────────────
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_SHOW_WEB_CALL -> {
                // FCM background triggered this — show the call notification
                val callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: "Doctor"
                val callId     = intent.getStringExtra(EXTRA_CALL_ID) ?: ""
                val bookingId  = intent.getStringExtra(EXTRA_BOOKING_ID) ?: ""
                showIncomingCallNotification(context, callerName, callId, bookingId)
            }
            ACTION_DECLINE_WEB_CALL -> {
                dismissNotification(context)
                // Broadcast to Flutter if app is alive via ZEGO broadcast channel
                val flutterIntent = Intent("com.ishashah04.swasthall.WEB_CALL_DECLINED").apply {
                    putExtra(EXTRA_CALL_ID, intent.getStringExtra(EXTRA_CALL_ID))
                }
                context.sendBroadcast(flutterIntent)
            }
        }
    }
}
