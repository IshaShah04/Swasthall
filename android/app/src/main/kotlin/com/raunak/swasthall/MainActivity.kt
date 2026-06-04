package com.raunak.swasthall

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL      = "com.raunak.swasthall/widget"
        const val CALL_CHANNEL = "com.raunak.swasthall/web_call"
    }

    // ── Widget state ──────────────────────────────────────────────────────────
    private var pendingWidgetRoute: String? = null
    private var pendingUserId: String? = null
    private var pendingAppointmentId: String? = null
    private var pendingTaskId: String? = null
    private var pendingAction: String? = null

    // ── Web call state ────────────────────────────────────────────────────────
    // Holds call data when app was opened from a killed state via notification tap.
    // Delivered to Flutter once the engine is ready via getPendingWebCall.
    private var pendingWebCallData: Map<String, String>? = null
    private var callMethodChannel: MethodChannel? = null

    // ─────────────────────────────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleWidgetIntent(intent)
        handleWebCallIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWidgetIntent(intent)
        handleWebCallIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Widget channel ────────────────────────────────────────────────────
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

        // ── Web call channel ──────────────────────────────────────────────────
        callMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CALL_CHANNEL
        )
        callMethodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                // Flutter asks: was there a pending accepted web call when app opened?
                "getPendingWebCall" -> {
                    result.success(pendingWebCallData)
                    pendingWebCallData = null
                }
                // Flutter tells native: dismiss the web call notification
                "dismissWebCallNotification" -> {
                    WebCallNotificationService.dismissNotification(this)
                    result.success(null)
                }
                // Flutter tells native: show the CallStyle full-screen call UI
                "showWebCallNotification" -> {
                    val callerName = call.argument<String>("callerName") ?: "Doctor"
                    val callId     = call.argument<String>("callId") ?: ""
                    val bookingId  = call.argument<String>("bookingId") ?: ""
                    WebCallNotificationService.showIncomingCallNotification(
                        this, callerName, callId, bookingId
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // If an accepted web call arrived before the engine was ready, deliver it now
        pendingWebCallData?.let { data ->
            callMethodChannel?.invokeMethod("onWebCallAccepted", data)
            pendingWebCallData = null
        }
    }

    // ── Handle intents from WebCallNotificationService ────────────────────────
    private fun handleWebCallIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return

        when (action) {
            WebCallNotificationService.ACTION_ACCEPT_WEB_CALL,
            WebCallNotificationService.ACTION_SHOW_WEB_CALL -> {
                val callerName = intent.getStringExtra(WebCallNotificationService.EXTRA_CALLER_NAME) ?: ""
                val callId     = intent.getStringExtra(WebCallNotificationService.EXTRA_CALL_ID) ?: ""
                val bookingId  = intent.getStringExtra(WebCallNotificationService.EXTRA_BOOKING_ID) ?: ""
                if (callId.isEmpty()) return

                // Always dismiss the notification first
                WebCallNotificationService.dismissNotification(this)

                // Only navigate into the call if the user pressed Accept
                if (action != WebCallNotificationService.ACTION_ACCEPT_WEB_CALL) return

                val data = mapOf(
                    "callerName" to callerName,
                    "callId"     to callId,
                    "bookingId"  to bookingId,
                )

                val ch = callMethodChannel
                if (ch != null) {
                    // Engine already running — deliver immediately
                    ch.invokeMethod("onWebCallAccepted", data)
                } else {
                    // Engine not ready yet — store, delivered in configureFlutterEngine
                    pendingWebCallData = data
                }
            }
        }
    }

    // ── Handle intents from app widgets ──────────────────────────────────────
    private fun handleWidgetIntent(intent: Intent?) {
        if (intent == null) return

        val action = intent.action ?: return

        val isWidgetAction = action in listOf(
            PatientWidgetProvider.ACTION_OPEN_QUEUE,
            NurseWidgetProvider.ACTION_OPEN_TASKS,
            NurseWidgetProvider.ACTION_TASK_DONE,
            NurseWidgetProvider.ACTION_TASK_SKIP,
        )
        if (!isWidgetAction) return

        val rawRoute = intent.getStringExtra(PatientWidgetProvider.EXTRA_WIDGET_ROUTE) ?: ""
        val userId   = intent.getStringExtra(PatientWidgetProvider.EXTRA_USER_ID) ?: ""

        val allowedRoutes = setOf("/patient_queue", "/booking", "/nurse_tasks", "/widget_action", "/widget_nurse_action")
        val safeRoute = if (rawRoute in allowedRoutes) rawRoute else "/booking"

        pendingWidgetRoute   = safeRoute
        pendingUserId        = userId
        pendingAppointmentId = intent.getStringExtra(PatientWidgetProvider.EXTRA_APPOINTMENT_ID) ?: ""
        pendingTaskId        = intent.getStringExtra(NurseWidgetProvider.EXTRA_TASK_ID) ?: ""
        pendingAction        = intent.getStringExtra("widgetAction") ?: ""
    }
}
