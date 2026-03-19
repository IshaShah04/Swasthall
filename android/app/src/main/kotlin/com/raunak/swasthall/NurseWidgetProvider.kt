package com.raunak.swasthall

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * NurseWidgetProvider — SECURITY FIXED VERSION
 *
 * Fixes applied:
 *  1. Specific intent action (WIDGET_OPEN_NURSE_TASKS) prevents landing on physical.dart.
 *  2. All task actions include and validate the stored nurse userId.
 *  3. External intent spoofing blocked by cross-checking stored userId.
 *  4. Unauthenticated state disables action buttons.
 */
class NurseWidgetProvider : AppWidgetProvider() {

    companion object {
        const val PREFS_NAME        = "FlutterSharedPreferences"
        const val KEY_NURSE_USER_ID = "flutter.widget_nurse_user_id"
        const val KEY_TASK_ID       = "flutter.widget_nurse_task_id"
        const val KEY_PATIENT_NAME  = "flutter.widget_nurse_patient_name"
        const val KEY_TASK_TYPE     = "flutter.widget_nurse_task_type"

        const val ACTION_OPEN_TASKS   = "com.raunak.swasthall.WIDGET_OPEN_NURSE_TASKS"
        const val ACTION_TASK_DONE    = "com.raunak.swasthall.WIDGET_NURSE_TASK_DONE"
        const val ACTION_TASK_SKIP    = "com.raunak.swasthall.WIDGET_NURSE_TASK_SKIP"

        const val EXTRA_WIDGET_ROUTE  = "widgetRoute"
        const val EXTRA_USER_ID       = "userId"
        const val EXTRA_TASK_ID       = "taskId"
        const val EXTRA_ACTION        = "widgetAction"

        const val ROUTE_NURSE_TASKS   = "/nurse_tasks"
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
        val prefs       = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val nurseUserId = prefs.getString(KEY_NURSE_USER_ID, null)
        val taskId      = prefs.getString(KEY_TASK_ID, null)
        val patientName = prefs.getString(KEY_PATIENT_NAME, "Patient")
        val taskType    = prefs.getString(KEY_TASK_TYPE, "Task")

        val views = RemoteViews(context.packageName, R.layout.nurse_widget_layout)

        // SECURITY FIX: no userId = disable all action buttons
        if (nurseUserId.isNullOrBlank()) {
            views.setTextViewText(R.id.nurse_widget_title, "SwasthAll Nurse")
            views.setTextViewText(R.id.nurse_widget_subtitle, "Open app to sign in")
            views.setBoolean(R.id.nurse_btn_done, "setEnabled", false)
            views.setBoolean(R.id.nurse_btn_skip, "setEnabled", false)
            appWidgetManager.updateAppWidget(widgetId, views)
            return
        }

        views.setTextViewText(R.id.nurse_widget_title, taskType)
        views.setTextViewText(R.id.nurse_widget_subtitle, patientName)
        views.setBoolean(R.id.nurse_btn_done, "setEnabled", true)
        views.setBoolean(R.id.nurse_btn_skip, "setEnabled", true)

        // Widget body tap → nurse task list (not physical.dart)
        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_TASKS
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_WIDGET_ROUTE, ROUTE_NURSE_TASKS)
            putExtra(EXTRA_USER_ID, nurseUserId)
        }
        views.setOnClickPendingIntent(
            R.id.nurse_widget_root,
            PendingIntent.getActivity(context, widgetId * 10, openIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        )

        // Done button
        val doneIntent = Intent(context, NurseWidgetProvider::class.java).apply {
            action = ACTION_TASK_DONE
            putExtra(EXTRA_USER_ID, nurseUserId)   // SECURITY FIX
            putExtra(EXTRA_TASK_ID, taskId)
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        views.setOnClickPendingIntent(
            R.id.nurse_btn_done,
            PendingIntent.getBroadcast(context, widgetId * 10 + 1, doneIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        )

        // Skip button
        val skipIntent = Intent(context, NurseWidgetProvider::class.java).apply {
            action = ACTION_TASK_SKIP
            putExtra(EXTRA_USER_ID, nurseUserId)   // SECURITY FIX
            putExtra(EXTRA_TASK_ID, taskId)
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        views.setOnClickPendingIntent(
            R.id.nurse_btn_skip,
            PendingIntent.getBroadcast(context, widgetId * 10 + 2, skipIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        )

        appWidgetManager.updateAppWidget(widgetId, views)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        when (intent.action) {
            ACTION_TASK_DONE, ACTION_TASK_SKIP -> {
                val userId = intent.getStringExtra(EXTRA_USER_ID)
                val taskId = intent.getStringExtra(EXTRA_TASK_ID)

                if (userId.isNullOrBlank() || taskId.isNullOrBlank()) {
                    android.util.Log.w("NurseWidget", "Blocked: missing userId or taskId")
                    return
                }

                // SECURITY FIX: cross-check against stored value to block spoofed intents
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val storedNurseId = prefs.getString(KEY_NURSE_USER_ID, null)
                if (userId != storedNurseId) {
                    android.util.Log.w("NurseWidget", "Blocked: nurseId mismatch")
                    return
                }

                val action = if (intent.action == ACTION_TASK_DONE) "done" else "skip"
                val forwardIntent = Intent(context, MainActivity::class.java).apply {
                    this.action = ACTION_OPEN_TASKS
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra(EXTRA_WIDGET_ROUTE, "/widget_nurse_action")
                    putExtra(EXTRA_USER_ID, userId)
                    putExtra(EXTRA_TASK_ID, taskId)
                    putExtra(EXTRA_ACTION, action)
                }
                context.startActivity(forwardIntent)
            }
        }
    }
}