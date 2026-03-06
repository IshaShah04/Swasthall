package com.raunak.swasthall

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class PatientWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.patient_widget_layout).apply {
                
                // 1. Get data saved from Flutter
                val name = widgetData.getString("patient_name", "No Patient")
                val queue = widgetData.getString("queue_num", "-")
                val sync = widgetData.getString("last_sync", "Just now")
                val docStatus = widgetData.getString("doctor_status", "Waiting...")

                // 2. Set Text (No buttons here!)
                setTextViewText(R.id.patient_name, name)
                setTextViewText(R.id.queue_num, "#$queue")
                setTextViewText(R.id.last_sync, "Updated: $sync")
                setTextViewText(R.id.doctor_status, docStatus)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}