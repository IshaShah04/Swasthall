// lib/services/login_notification_service.dart
//
// Records a login event and pushes a "new device login" notification
// to the user's other devices — exactly like Facebook / Instagram.
//
// Call this right after a successful Supabase sign-in in login_page.dart:
//
//   unawaited(LoginNotificationService.recordLoginAndNotify());
//
// It is fire-and-forget — never blocks login, never throws.

import 'dart:async' show unawaited;          // ← fixes "unawaited not defined" error
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginNotificationService {
  static final _supabase = Supabase.instance.client;

  static Future<String?> _freshAccessToken() async {
    try {
      final refreshed = await _supabase.auth.refreshSession();
      final token = refreshed.session?.accessToken ??
          _supabase.auth.currentSession?.accessToken;
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      final token = _supabase.auth.currentSession?.accessToken;
      return (token == null || token.isEmpty) ? null : token;
    }
  }

  // ── Public entry point ───────────────────────────────────────────────────
  static Future<void> recordLoginAndNotify() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final deviceInfo = await _getDeviceInfo();
      final location   = await _getLocation();

      // 1. Store login event in Supabase (non-blocking)
      unawaited(
        _supabase.from('user_login_events').insert({
          'user_id':      user.id,
          'device_name':  deviceInfo['name'],
          'platform':     deviceInfo['platform'],
          'location':     location,
          'logged_in_at': DateTime.now().toIso8601String(),
        }).then((_) {
          debugPrint('[LoginNotif] login event stored');
        }).catchError((Object e) {
          debugPrint('[LoginNotif] failed to store event: $e');
        }),
      );

      // 2. Ask Edge Function to push FCM notification to other devices.
      // Explicit Authorization is required because the function verifies auth.uid().
      unawaited(
        (() async {
          final token = await _freshAccessToken();
          if (token == null) {
            debugPrint('[LoginNotif] no fresh token; skipping edge notification');
            return;
          }

          final r = await _supabase.functions.invoke(
            'notify-new-login',
            headers: {'Authorization': 'Bearer $token'},
            body: {
              'userId':     user.id,
              'deviceName': deviceInfo['name'],
              'platform':   deviceInfo['platform'],
              'location':   location,
              'loginTime':  DateTime.now().toIso8601String(),
            },
          );
          debugPrint('[LoginNotif] edge fn responded: ${r.status}');
        })().catchError((Object e) {
          debugPrint('[LoginNotif] edge fn error (non-fatal): $e');
        }),
      );
    } catch (_) {
      // Must NEVER re-throw — login must succeed regardless.
      debugPrint('[LoginNotif] unexpected error');
    }
  }

  // ── Device info ──────────────────────────────────────────────────────────
  static Future<Map<String, String>> _getDeviceInfo() async {
    try {
      if (kIsWeb) {
        return {'name': 'Web Browser', 'platform': 'Web'};
      }

      final plugin = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return {
          'name':     '${info.brand} ${info.model}',
          'platform': 'Android ${info.version.release}',
        };
      }

      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return {
          'name':     info.name,
          'platform': '${info.systemName} ${info.systemVersion}',
        };
      }

      if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        return {'name': info.computerName, 'platform': 'Windows'};
      }

      if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        return {'name': info.computerName, 'platform': 'macOS'};
      }

      return {'name': 'Unknown Device', 'platform': 'Unknown'};
    } catch (e) {
      debugPrint('[LoginNotif] device info error: $e');
      return {'name': 'Unknown Device', 'platform': 'Unknown'};
    }
  }

  // ── Location ─────────────────────────────────────────────────────────────
  static Future<String> _getLocation() async {
    try {
      if (kIsWeb) return 'Web session';

      final permission = await Geolocator.checkPermission();
      final hasPermission = permission == LocationPermission.whileInUse ||
                            permission == LocationPermission.always;

      if (!hasPermission) return 'Location not shared';

      // ↓ Fixed: use LocationSettings instead of deprecated desiredAccuracy/timeLimit params
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        ),
      );

      // Low-precision label only — no exact coordinates stored for privacy
      return '${pos.latitude.toStringAsFixed(2)}°N, '
             '${pos.longitude.toStringAsFixed(2)}°E';
    } catch (e) {
      debugPrint('[LoginNotif] location error: $e');
      return 'Location unavailable';
    }
  }
}
