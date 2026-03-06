// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void triggerWebNotification(String title, String body) {
  if (html.Notification.permission == 'granted') {
    html.Notification(title, body: body);
  } else if (html.Notification.permission != 'denied') {
    html.Notification.requestPermission().then((permission) {
      if (permission == 'granted') {
        html.Notification(title, body: body);
      }
    });
  }
}