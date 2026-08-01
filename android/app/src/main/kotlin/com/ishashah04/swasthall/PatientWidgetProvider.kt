package com.ishashah04.swasthall

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class PatientWidgetProvider : AppWidgetProvider() {

    companion object {
        const val PREFS_NAME           = "FlutterSharedPreferences"
        const val KEY_USER_ID          = "flutter.widget_user_id"
        const val KEY_APPOINTMENT_ID   = "flutter.widget_appointment_id"
        const val KEY_DOCTOR_NAME      = "flutter.widget_doctor_name"
        const val KEY_QUEUE_NUMBER     = "flutter.widget_queue_number"
        const val KEY_QUEUE_TOTAL      = "flutter.widget_queue_total"
        const val KEY_QUEUE_PROGRESS   = "flutter.widget_queue_progress"

        const val ACTION_OPEN_QUEUE  = "com.ishashah04.swasthall.WIDGET_OPEN_QUEUE"
        const val EXTRA_WIDGET_ROUTE   = "widgetRoute"
        const val EXTRA_USER_ID        = "userId"
        const val EXTRA_APPOINTMENT_ID = "appointmentId"
        const val ROUTE_PATIENT_BOOKINGS = "/booking"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (widgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, widgetId)
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int
    ) {
        val prefs         = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val userId        = prefs.getString(KEY_USER_ID, null)
        val appointmentId = prefs.getString(KEY_APPOINTMENT_ID, null)
        val doctorName    = prefs.getString(KEY_DOCTOR_NAME, "Doctor") ?: "Doctor"
        val queueNumber   = prefs.getString(KEY_QUEUE_NUMBER, "--") ?: "--"
        val queueTotal    = prefs.getString(KEY_QUEUE_TOTAL, "0") ?: "0"
        val queueProgress = prefs.getString(KEY_QUEUE_PROGRESS, "0")?.toIntOrNull() ?: 0

        val views = RemoteViews(context.packageName, R.layout.patient_widget_layout)

        if (userId.isNullOrBlank()) {
            views.setTextViewText(R.id.widget_queue_number, "--")
            views.setTextViewText(R.id.widget_queue_label,  "Sign in to see your queue")
            views.setTextViewText(R.id.widget_doctor_name,  "SwasthAll")
            views.setProgressBar(R.id.widget_progress_bar, 100, 0, false)
            appWidgetManager.updateAppWidget(widgetId, views)
            return
        }

        views.setTextViewText(R.id.widget_queue_number, "#$queueNumber")
        views.setTextViewText(R.id.widget_queue_label,  "of $queueTotal  •  $doctorName")
        views.setTextViewText(R.id.widget_doctor_name,  doctorName)
        views.setProgressBar(R.id.widget_progress_bar, 100, queueProgress, false)

        val isNext = queueProgress >= 90
        views.setViewVisibility(
            R.id.widget_next_label,
            if (isNext) android.view.View.VISIBLE else android.view.View.GONE
        )

        // Widget tap → open patient bookings screen in app
        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_QUEUE
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_WIDGET_ROUTE,   ROUTE_PATIENT_BOOKINGS)
            putExtra(EXTRA_USER_ID,        userId)
            putExtra(EXTRA_APPOINTMENT_ID, appointmentId ?: "")
        }
        views.setOnClickPendingIntent(
            R.id.widget_root,
            PendingIntent.getActivity(
                context, widgetId, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )

        appWidgetManager.updateAppWidget(widgetId, views)
    }
}
