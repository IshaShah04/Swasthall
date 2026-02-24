// notification_web.dart
import 'dart:js_interop';
import 'package:web/web.dart' as web;

void triggerWebNotification(String title, String body) {
  if (web.Notification.permission == 'granted') {
    web.Notification(title, web.NotificationOptions(body: body));
  } else if (web.Notification.permission != 'denied') {
    web.Notification.requestPermission().toDart.then((permission) {
      if (permission.toDart.toString() == 'granted') {
        web.Notification(title, web.NotificationOptions(body: body));
      }
    });
  }
}