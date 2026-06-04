// lib/services/queue_widget_service.dart
// SECURITY FIXED + PROGRESS BAR + NURSE AUTHORITY VERSION

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QueueWidgetService {
  static const _channel = MethodChannel('com.raunak.swasthall/widget');

  static const _kUserId = 'widget_user_id';
  static const _kNurseUserId = 'widget_nurse_user_id';
  static const _kAppointmentId = 'widget_appointment_id';
  static const _kTaskId = 'widget_nurse_task_id';
  static const _kDoctorName = 'widget_doctor_name';
  static const _kQueueNumber = 'widget_queue_number';
  static const _kQueueTotal = 'widget_queue_total';
  static const _kQueueProgress = 'widget_queue_progress';
  static const _kNurseTaskType = 'widget_nurse_task_type';
  static const _kNursePatient = 'widget_nurse_patient_name';

  static Future<void> updateLiveWidget({
    required String patientName,
    required String queueNum,
    required String bookingId,
    String doctorStatus = '',
    String doctorName = '',
    int totalInQueue = 0,
  }) async {
    if (kIsWeb) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('QueueWidgetService: skipping update — not logged in');
      return;
    }

    final position = int.tryParse(queueNum) ?? 1;
    final total = totalInQueue > 0 ? totalInQueue : position;
    final clampedPosition = position.clamp(1, total);
    final progressPct = total <= 0
        ? 0
        : (((total - clampedPosition) / total) * 100).round();
    final displayDoctor = doctorName.isNotEmpty ? doctorName : doctorStatus;

    await HomeWidget.saveWidgetData<String>(_kUserId, user.id);
    await HomeWidget.saveWidgetData<String>(_kAppointmentId, bookingId);
    await HomeWidget.saveWidgetData<String>(_kDoctorName, displayDoctor);
    await HomeWidget.saveWidgetData<String>(_kQueueNumber, position.toString());
    await HomeWidget.saveWidgetData<String>(_kQueueTotal, total.toString());
    await HomeWidget.saveWidgetData<String>(_kQueueProgress, progressPct.toString());

    await HomeWidget.updateWidget(
      androidName: 'PatientWidgetProvider',
      iOSName: 'PatientWidget',
    );
  }

  static Future<void> updatePatientWidget({
    required String appointmentId,
    required String doctorName,
    required int queuePosition,
    required int totalInQueue,
  }) => updateLiveWidget(
        bookingId: appointmentId,
        doctorName: doctorName,
        queueNum: queuePosition.toString(),
        totalInQueue: totalInQueue,
        patientName: '',
      );

  static Future<void> updateNurseWidget({
    required String taskId,
    required String taskType,
    required String patientName,
  }) async {
    if (kIsWeb) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('QueueWidgetService: skipping nurse update — not logged in');
      return;
    }

    await HomeWidget.saveWidgetData<String>(_kNurseUserId, user.id);
    await HomeWidget.saveWidgetData<String>(_kTaskId, taskId);
    await HomeWidget.saveWidgetData<String>(_kNurseTaskType, taskType);
    await HomeWidget.saveWidgetData<String>(_kNursePatient, patientName);

    await HomeWidget.updateWidget(
      androidName: 'NurseWidgetProvider',
      iOSName: 'NurseWidget',
    );
  }

  static Future<void> updatePatientRealtimeWidget({
    required String appointmentId,
    required String doctorName,
    required int originalQueueNumber,
    required int currentlyServing,
  }) {
    final total = originalQueueNumber <= 0 ? 1 : originalQueueNumber;
    final position = originalQueueNumber <= 0
        ? 1
        : (originalQueueNumber - currentlyServing).clamp(1, total);

    return updatePatientWidget(
      appointmentId: appointmentId,
      doctorName: doctorName,
      queuePosition: position,
      totalInQueue: total,
    );
  }

  static Future<void> clearPatientWidget() async {
    if (kIsWeb) return;

    await HomeWidget.saveWidgetData<String>(_kUserId, '');
    await HomeWidget.saveWidgetData<String>(_kAppointmentId, '');
    await HomeWidget.saveWidgetData<String>(_kDoctorName, '');
    await HomeWidget.saveWidgetData<String>(_kQueueNumber, '--');
    await HomeWidget.saveWidgetData<String>(_kQueueTotal, '0');
    await HomeWidget.saveWidgetData<String>(_kQueueProgress, '0');

    await HomeWidget.updateWidget(
      androidName: 'PatientWidgetProvider',
      iOSName: 'PatientWidget',
    );
  }

  static Future<void> clearNurseWidget() async {
    if (kIsWeb) return;

    await HomeWidget.saveWidgetData<String>(_kNurseUserId, '');
    await HomeWidget.saveWidgetData<String>(_kTaskId, '');
    await HomeWidget.saveWidgetData<String>(_kNurseTaskType, '');
    await HomeWidget.saveWidgetData<String>(_kNursePatient, '');

    await HomeWidget.updateWidget(
      androidName: 'NurseWidgetProvider',
      iOSName: 'NurseWidget',
    );
  }

  static Future<void> clearWidget() async {
    if (kIsWeb) return;

    await clearPatientWidget();
    await clearNurseWidget();
  }

  static Future<void> clearWidgetDataOnLogout() => clearWidget();

  static Future<WidgetLaunchData?> getWidgetLaunchData() async {
    if (kIsWeb) return null;
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
        route: data['route'] as String? ?? '',
        userId: userId,
        appointmentId: data['appointmentId'] as String? ?? '',
        taskId: data['taskId'] as String? ?? '',
        action: data['action'] as String? ?? '',
      );
    } on PlatformException catch (e) {
      debugPrint('QueueWidgetService: getWidgetLaunchData error: $e');
      return null;
    }
  }

  static Future<void> _markBookingAction({
    required String bookingId,
    required bool isDone,
  }) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (kDebugMode) {
        debugPrint('QueueWidgetService: ignoring booking action without session');
      }
      return;
    }

    try {
      if (isDone) {
        await supabase.rpc(
          'mark_booking_completed',
          params: {'p_booking_id': bookingId},
        );
      } else {
        await supabase.rpc(
          'mark_booking_missed',
          params: {'p_booking_id': bookingId},
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('QueueWidgetService: booking action RPC failed: ');
      }
    }
  }

  static Future<void> handlePatientWidgetAction(WidgetLaunchData data) async {
    if (data.userId.isEmpty || data.appointmentId.isEmpty) return;
    final supabase = Supabase.instance.client;
    if (supabase.auth.currentUser?.id != data.userId) return;

    await _markBookingAction(
      bookingId: data.appointmentId,
      isDone: data.action == 'done' || data.action == 'completed',
    );
  }

  static Future<void> handleNurseWidgetAction(WidgetLaunchData data) async {
    if (data.userId.isEmpty) return;
    final supabase = Supabase.instance.client;
    if (supabase.auth.currentUser?.id != data.userId) return;

    final bookingId = data.taskId.isNotEmpty ? data.taskId : data.appointmentId;
    if (bookingId.isEmpty) return;

    await _markBookingAction(
      bookingId: bookingId,
      isDone: data.action == 'done' || data.action == 'completed',
    );
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
