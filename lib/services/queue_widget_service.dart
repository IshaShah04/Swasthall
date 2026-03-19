// lib/services/queue_widget_service.dart
// SECURITY FIXED + PROGRESS BAR + NURSE AUTHORITY VERSION

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QueueWidgetService {
  static const _channel = MethodChannel('com.raunak.swasthall/widget');

  // SharedPreferences keys — must match Kotlin constants exactly
  // home_widget prepends 'flutter.' automatically: 'widget_user_id' → 'flutter.widget_user_id'
  static const _kUserId        = 'widget_user_id';
  static const _kNurseUserId   = 'widget_nurse_user_id';
  static const _kAppointmentId = 'widget_appointment_id';
  static const _kTaskId        = 'widget_nurse_task_id';
  static const _kDoctorName    = 'widget_doctor_name';
  static const _kQueueNumber   = 'widget_queue_number';   // current position e.g. "4"
  static const _kQueueTotal    = 'widget_queue_total';    // total in session  e.g. "12"
  static const _kQueueProgress = 'widget_queue_progress'; // 0–100 int for ProgressBar
  static const _kNurseTaskType = 'widget_nurse_task_type';
  static const _kNursePatient  = 'widget_nurse_patient_name';

  // ── Patient Widget ──────────────────────────────────────────────────────────

  /// Original signature — called by physical.dart and consultation_payment_screen.dart.
  ///
  /// [patientName]  — patient's display name shown on widget
  /// [queueNum]     — current queue position as string e.g. "4"
  /// [bookingId]    — the appointment/booking ID (maps to appointmentId internally)
  /// [doctorStatus] — optional doctor status string shown on widget subtitle
  /// [doctorName]   — optional doctor name (falls back to doctorStatus if not provided)
  /// [totalInQueue] — total patients booked this session; drives the progress bar.
  ///                  Pass it whenever you have it. Defaults to 0 (bar stays empty
  ///                  until you provide the total).
  ///
  /// Progress bar fills as patient moves to front:
  ///   position 12 of 12 →  0% (just joined)
  ///   position  4 of 12 → 67% (getting close)
  ///   position  1 of 12 → 100% (you're next!)
  static Future<void> updateLiveWidget({
    required String patientName,
    required String queueNum,
    required String bookingId,
    String doctorStatus = '',
    String doctorName   = '',
    int    totalInQueue = 0,
  }) async {
    if (kIsWeb) return; // home_widget not supported on web

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('QueueWidgetService: skipping update — not logged in');
      return;
    }

    final position    = int.tryParse(queueNum) ?? 1;
    final total       = totalInQueue > 0 ? totalInQueue : position;
    final progressPct = (((total - position.clamp(1, total)) / total) * 100).round();

    // Use doctorName if provided, otherwise fall back to doctorStatus
    final displayDoctor = doctorName.isNotEmpty ? doctorName : doctorStatus;

    await HomeWidget.saveWidgetData<String>(_kUserId,        user.id);   // SECURITY: always from auth
    await HomeWidget.saveWidgetData<String>(_kAppointmentId, bookingId);
    await HomeWidget.saveWidgetData<String>(_kDoctorName,    displayDoctor);
    await HomeWidget.saveWidgetData<String>(_kQueueNumber,   position.toString());
    await HomeWidget.saveWidgetData<String>(_kQueueTotal,    total.toString());
    await HomeWidget.saveWidgetData<String>(_kQueueProgress, progressPct.toString());

    await HomeWidget.updateWidget(
      androidName: 'PatientWidgetProvider',
      iOSName: 'PatientWidget',
    );
  }

  /// Alternative explicit method for when you have all values as ints.
  static Future<void> updatePatientWidget({
    required String appointmentId,
    required String doctorName,
    required int    queuePosition,
    required int    totalInQueue,
  }) => updateLiveWidget(
    bookingId:    appointmentId,
    doctorName:   doctorName,
    queueNum:     queuePosition.toString(),
    totalInQueue: totalInQueue,
    patientName:  '',
  );

  // ── Nurse Widget ────────────────────────────────────────────────────────────

  static Future<void> updateNurseWidget({
    required String taskId,
    required String taskType,
    required String patientName,
  }) async {
    if (kIsWeb) return; // home_widget not supported on web

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('QueueWidgetService: skipping nurse update — not logged in');
      return;
    }

    await HomeWidget.saveWidgetData<String>(_kNurseUserId,   user.id); // SECURITY
    await HomeWidget.saveWidgetData<String>(_kTaskId,        taskId);
    await HomeWidget.saveWidgetData<String>(_kNurseTaskType, taskType);
    await HomeWidget.saveWidgetData<String>(_kNursePatient,  patientName);

    await HomeWidget.updateWidget(
      androidName: 'NurseWidgetProvider',
      iOSName: 'NurseWidget',
    );
  }

  // ── Logout / Clear ──────────────────────────────────────────────────────────

  /// Original name used by physical.dart — wipes all widget data on logout.
  /// Call this BEFORE supabase.auth.signOut().
  static Future<void> clearWidget() async {
    if (kIsWeb) return; // home_widget not supported on web

    await HomeWidget.saveWidgetData<String>(_kUserId,        '');
    await HomeWidget.saveWidgetData<String>(_kNurseUserId,   '');
    await HomeWidget.saveWidgetData<String>(_kAppointmentId, '');
    await HomeWidget.saveWidgetData<String>(_kTaskId,        '');
    await HomeWidget.saveWidgetData<String>(_kDoctorName,    '');
    await HomeWidget.saveWidgetData<String>(_kQueueNumber,   '--');
    await HomeWidget.saveWidgetData<String>(_kQueueTotal,    '0');
    await HomeWidget.saveWidgetData<String>(_kQueueProgress, '0');

    await HomeWidget.updateWidget(androidName: 'PatientWidgetProvider', iOSName: 'PatientWidget');
    await HomeWidget.updateWidget(androidName: 'NurseWidgetProvider',   iOSName: 'NurseWidget');
  }

  /// Alias for clearWidget — use whichever name you prefer.
  static Future<void> clearWidgetDataOnLogout() => clearWidget();

  // ── Widget Launch Handling ──────────────────────────────────────────────────

  static Future<WidgetLaunchData?> getWidgetLaunchData() async {
    if (kIsWeb) return null; // home_widget not supported on web
    try {
      final data = await _channel.invokeMethod<Map?>('getWidgetLaunchData');
      if (data == null) return null;

      final userId = data['userId'] as String? ?? '';
      if (userId.isEmpty) return null;

      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null || currentUser.id != userId) {
        debugPrint('QueueWidgetService: ignoring widget launch — userId mismatch');
        return null;
      }

      return WidgetLaunchData(
        route:         data['route']         as String? ?? '',
        userId:        userId,
        appointmentId: data['appointmentId'] as String? ?? '',
        taskId:        data['taskId']        as String? ?? '',
        action:        data['action']        as String? ?? '',
      );
    } on PlatformException catch (e) {
      debugPrint('QueueWidgetService: getWidgetLaunchData error: $e');
      return null;
    }
  }

  // ── Action Handlers ─────────────────────────────────────────────────────────

  static Future<void> handlePatientWidgetAction(WidgetLaunchData data) async {
    if (data.userId.isEmpty || data.appointmentId.isEmpty) return;
    final supabase = Supabase.instance.client;
    if (supabase.auth.currentUser?.id != data.userId) return;

    await supabase
        .from('appointments')
        .update({'status': data.action == 'done' ? 'completed' : 'skipped'})
        .eq('id', data.appointmentId);
  }

  static Future<void> handleNurseWidgetAction(WidgetLaunchData data) async {
    if (data.userId.isEmpty || data.appointmentId.isEmpty) return;
    final supabase = Supabase.instance.client;
    if (supabase.auth.currentUser?.id != data.userId) return;

    await supabase
        .from('appointments')
        .update({'status': data.action == 'done' ? 'completed' : 'in_progress'})
        .eq('id', data.appointmentId);
  }

  static Future<void> handleWidgetAction(WidgetLaunchData data) async {
    switch (data.route) {
      case '/widget_action':
        await handlePatientWidgetAction(data);
        break;
      case '/widget_nurse_action':
        await handleNurseWidgetAction(data);
        break;
    }
  }
}

class WidgetLaunchData {
  final String route;
  final String userId;
  final String appointmentId;
  final String taskId;
  final String action;

  const WidgetLaunchData({
    required this.route,
    required this.userId,
    required this.appointmentId,
    required this.taskId,
    required this.action,
  });
}