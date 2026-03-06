import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Conditional import magic
import 'notification_stub.dart'
    if (dart.library.js_interop) 'notification_web.dart';

class QueueWidgetService {
  static const String patientWidget = 'PatientWidgetProvider';
  static const String nurseWidget = 'NurseWidgetProvider';

  static Future<void> updateLiveWidget({
    required String patientName,
    required String queueNum,
    required String bookingId,
    String? doctorStatus,
  }) async {
    try {
      final String timeString = DateFormat('hh:mm a').format(DateTime.now());
      final String title = "Queue Update: #$queueNum";
      final String body = "Now Serving: $patientName. ${doctorStatus ?? 'In Progress'}";

      // 1. HANDLE MOBILE WIDGETS (Safely ignore on Web)
      if (!kIsWeb) {
        await HomeWidget.saveWidgetData<String>('patient_name', patientName);
        await HomeWidget.saveWidgetData<String>('queue_num', queueNum);
        await HomeWidget.saveWidgetData<String>('current_booking_id', bookingId);
        await HomeWidget.saveWidgetData<String>('last_sync', timeString);
        await HomeWidget.saveWidgetData<String>('doctor_status', doctorStatus ?? "In Progress");

        await HomeWidget.updateWidget(androidName: patientWidget, name: patientWidget);
        await HomeWidget.updateWidget(androidName: nurseWidget, name: nurseWidget);
      }

      // 2. TRIGGER NOTIFICATIONS
      if (kIsWeb) {
        triggerWebNotification(title, body);
      } else {
        await _triggerMobileNotification(title, body);
      }

      debugPrint("Queue Service Synced & Notified at $timeString");
    } catch (e) {
      debugPrint("Update Error: $e");
    }
  }

  static Future<void> _triggerMobileNotification(String title, String body) async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'queue_updates',
      'Queue Updates',
      channelDescription: 'Notifications for live queue changes',
      importance: Importance.max,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      id: DateTime.now().millisecond,
      title: title,
      body: body,
      notificationDetails: platformDetails,
    );
  }

  static Future<void> clearWidget() async {
    try {
      if (!kIsWeb) {
        await HomeWidget.saveWidgetData('patient_name', "No Active Session");
        await HomeWidget.saveWidgetData('queue_num', "-");
        await HomeWidget.saveWidgetData('current_booking_id', null);

        await HomeWidget.updateWidget(androidName: patientWidget, name: patientWidget);
        await HomeWidget.updateWidget(androidName: nurseWidget, name: nurseWidget);
      }
      debugPrint("Widgets Cleared");
    } catch (e) {
      debugPrint("Clear Error: $e");
    }
  }

  @pragma('vm:entry-point')
  static Future<void> backgroundCallback(Uri? uri) async {
    if (uri?.scheme == 'homeWidget') {
      final String? id = uri?.queryParameters['id'];
      final String action = uri?.host ?? '';
      if (id != null) {
        String newStatus = (action == 'done') ? 'completed' : 'missed';
        await performStatusUpdate(id, newStatus);
      }
    }
  }

  static Future<void> performStatusUpdate(String id, String status) async {
    try {
      await Supabase.instance.client.rpc(
        'advance_queue_safely',
        params: {'target_booking_id': id, 'new_status': status},
      );
    } catch (e) {
      debugPrint("Database Error: $e");
    }
  }
}