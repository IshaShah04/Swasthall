// web_download_web.dart
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html';

void triggerWebDownload(String url, String fileName) {
  // Create an anchor element and trigger a download
  AnchorElement(href: url)
    ..download = fileName
    ..click();
}