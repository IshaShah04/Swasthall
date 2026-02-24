package com.example.health_department

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider

class NurseWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.nurse_widget_layout).apply {
                
                // Extract data sent from Flutter
                val queueNum = widgetData.getString("queue_num", "#--")
                val patientName = widgetData.getString("patient_name", "No Patient")
                val lastSync = widgetData.getString("last_sync", "Never")
                val bookingId = widgetData.getString("current_booking_id", "")

                setTextViewText(R.id.queue_num, queueNum)
                setTextViewText(R.id.patient_name, patientName)
                setTextViewText(R.id.last_sync, "Last Action: $lastSync")

                // Setup Click Listeners using HomeWidgetBackgroundIntent
                if (!bookingId.isNullOrEmpty()) {
                    // Action: Done
                    val doneUri = Uri.parse("homeWidget://done?id=$bookingId")
                    val doneIntent = HomeWidgetBackgroundIntent.getBroadcast(context, doneUri)
                    setOnClickPendingIntent(R.id.widget_done, doneIntent)

                    // Action: Skip
                    val skipUri = Uri.parse("homeWidget://skip?id=$bookingId")
                    val skipIntent = HomeWidgetBackgroundIntent.getBroadcast(context, skipUri)
                    setOnClickPendingIntent(R.id.widget_skip, skipIntent)
                }
            }
            
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}