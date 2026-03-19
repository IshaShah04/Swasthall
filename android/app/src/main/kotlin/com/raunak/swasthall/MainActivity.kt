package com.raunak.swasthall

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "com.raunak.swasthall/widget"
    }

    private var pendingWidgetRoute: String? = null
    private var pendingUserId: String? = null
    private var pendingAppointmentId: String? = null
    private var pendingTaskId: String? = null
    private var pendingAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleWidgetIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWidgetIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getWidgetLaunchData" -> {
                        if (pendingWidgetRoute != null) {
                            result.success(mapOf(
                                "route"         to (pendingWidgetRoute ?: ""),
                                "userId"        to (pendingUserId ?: ""),
                                "appointmentId" to (pendingAppointmentId ?: ""),
                                "taskId"        to (pendingTaskId ?: ""),
                                "action"        to (pendingAction ?: ""),
                            ))
                            pendingWidgetRoute   = null
                            pendingUserId        = null
                            pendingAppointmentId = null
                            pendingTaskId        = null
                            pendingAction        = null
                        } else {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleWidgetIntent(intent: Intent?) {
        if (intent == null) return

        val action = intent.action ?: return

        // Only handle known widget actions — ACTION_MARK_DONE/SKIP removed
        // since patient widget no longer has those buttons
        val isWidgetAction = action in listOf(
            PatientWidgetProvider.ACTION_OPEN_QUEUE,
            NurseWidgetProvider.ACTION_OPEN_TASKS,
            NurseWidgetProvider.ACTION_TASK_DONE,
            NurseWidgetProvider.ACTION_TASK_SKIP,
        )
        if (!isWidgetAction) return

        val rawRoute = intent.getStringExtra(PatientWidgetProvider.EXTRA_WIDGET_ROUTE) ?: ""
        val userId   = intent.getStringExtra(PatientWidgetProvider.EXTRA_USER_ID) ?: ""

        val allowedRoutes = setOf("/patient_queue", "/nurse_tasks", "/widget_action", "/widget_nurse_action")
        val safeRoute = if (rawRoute in allowedRoutes) rawRoute else "/patient_queue"

        pendingWidgetRoute   = safeRoute
        pendingUserId        = userId
        pendingAppointmentId = intent.getStringExtra(PatientWidgetProvider.EXTRA_APPOINTMENT_ID) ?: ""
        pendingTaskId        = intent.getStringExtra(NurseWidgetProvider.EXTRA_TASK_ID) ?: ""
        pendingAction        = intent.getStringExtra("widgetAction") ?: ""
    }
}