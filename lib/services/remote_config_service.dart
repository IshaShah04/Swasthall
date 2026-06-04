// lib/services/remote_config_service.dart
//
// Fetches feature flags and config values from the `app_config` Supabase table.
// Push changes to ALL users instantly — no Play Store / App Store update needed.
//
// Usage in main.dart initState() postFrameCallback:
//   if (mounted) unawaited(RemoteConfigService.fetchAndApply(context));
//
// Usage anywhere in app:
//   if (RemoteConfigService.getBool('feature_prescription_scan')) { ... }
//   final model = RemoteConfigService.get('gemini_model', defaultValue: 'gemini-1.5-flash');


import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class RemoteConfigService {
  static final _supabase = Supabase.instance.client;
  static Map<String, String> _config = {};
  static bool _loaded = false;

  // ── Public API ───────────────────────────────────────────────────────────

  /// Fetches config from Supabase and shows dialogs if needed.
  /// Safe to call multiple times — fetches only once per session unless invalidated.
  static Future<void> fetchAndApply(BuildContext context) async {
    if (_loaded) return;

    try {
      final rows = await _supabase
          .from('app_config')
          .select('key, value')
          .timeout(const Duration(seconds: 8));

      _config = {
        for (final row in rows as List<dynamic>)
          row['key'].toString(): row['value'].toString()
      };
      _loaded = true;

      debugPrint('[RemoteConfig] Loaded ${_config.length} keys');

      if (!context.mounted) return;

      // ── Maintenance mode ────────────────────────────────────────────────
      if (getBool('maintenance_mode')) {
        _showMaintenanceDialog(context);
        return;
      }

      // ── Force update ────────────────────────────────────────────────────
      if (getBool('force_update')) {
        final info = await PackageInfo.fromPlatform();
        final minVersion = get('min_app_version', defaultValue: '1.0.0');
        if (_isVersionLower(info.version, minVersion)) {
          if (context.mounted) _showForceUpdateDialog(context);
        }
      }
    } catch (e) {
      debugPrint('[RemoteConfig] fetch failed (offline?): $e');
      _loaded = false; // retry next time
    }
  }

  static String get(String key, {String defaultValue = ''}) =>
      _config[key] ?? defaultValue;

  static bool getBool(String key, {bool defaultValue = false}) {
    final val = _config[key];
    if (val == null) return defaultValue;
    return val == 'true';
  }

  static int getInt(String key, {int defaultValue = 0}) =>
      int.tryParse(_config[key] ?? '') ?? defaultValue;

  /// Force a re-fetch on next app resume.
  static void invalidate() => _loaded = false;

  // ── Version comparison ────────────────────────────────────────────────────
  static bool _isVersionLower(String current, String minimum) {
    try {
      final c = current.split('.').map(int.parse).toList();
      final m = minimum.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final ci = i < c.length ? c[i] : 0;
        final mi = i < m.length ? m[i] : 0;
        if (ci < mi) return true;
        if (ci > mi) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────
  static void _showForceUpdateDialog(BuildContext context) {
    final storeUrl = get('store_url');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.system_update_rounded, color: Color(0xFF6366F1)),
              SizedBox(width: 8),
              Text('Update Required'),
            ],
          ),
          content: const Text(
            'A new version of Swasthall is available with important improvements. '
            'Please update to continue.',
          ),
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Update Now'),
              onPressed: () async {
                if (storeUrl.isNotEmpty) {
                  final uri = Uri.tryParse(storeUrl);
                  if (uri != null) await launchUrl(uri);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  static void _showMaintenanceDialog(BuildContext context) {
    final message = get(
      'maintenance_message',
      defaultValue:
          'We are performing scheduled maintenance. Please try again in a few minutes.',
    );
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.construction_rounded, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text('Under Maintenance'),
            ],
          ),
          content: Text(message),
        ),
      ),
    );
  }
}
