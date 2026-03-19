// lib/services/secure_logout.dart
//
// Single source of truth for all logout paths in the app.
// Import this and call SecureLogout.perform(context) from:
//   - patient_settings.dart
//   - professional_setting.dart
//   - hospital_profile.dart
//   - verification_pending_screen.dart
//
// What it does:
//   1. Clears AppCache (in-memory sensitive data)
//   2. Clears Flutter image cache (prevents medical images staying on device)
//   3. Clears QueueWidgetService (home screen widget data)
//   4. Clears FDA cache from SharedPreferences (study_hub search cache)
//   5. Removes account from AccountService secure storage
//   6. Signs out from Supabase
//   7. Navigates to login

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_cache.dart';
import 'account_service.dart';
import 'queue_widget_service.dart';

class SecureLogout {
  SecureLogout._();

  static Future<void> perform(
    BuildContext context, {
    bool removeAccount = true,
  }) async {
    final navigator = Navigator.of(context);
    final userId = Supabase.instance.client.auth.currentUser?.id;

    // 1. Clear in-memory cache (profiles, bookings, medical data)
    AppCache.clear();

    // 2. Clear Flutter image cache — prevents medical/avatar images
    //    from persisting on device after logout
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    // 3. Clear home screen widget data
    try {
      await QueueWidgetService.clearWidget();
    } catch (_) {}

    // 4. Clear FDA drug search cache from SharedPreferences
    //    (study_hub.dart stores this — not sensitive but clean up anyway)
    try {
      final prefs = await SharedPreferences.getInstance();
      final fdaKeys = prefs
          .getKeys()
          .where((k) => k.startsWith('fda_cache_'))
          .toList();
      for (final key in fdaKeys) {
        await prefs.remove(key);
      }
      // Keep language preference — not sensitive
      // Remove nothing else from prefs (voice language is fine to keep)
    } catch (_) {}

    // 5. Remove this account from saved accounts in secure storage
    if (removeAccount && userId != null) {
      try {
        await AccountService.removeAccount(userId);
      } catch (_) {}
    }

    // 6. Sign out from Supabase (invalidates JWT on server)
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    // 7. Navigate to login — replace entire stack
    if (navigator.mounted) {
      navigator.pushReplacementNamed('/login');
    }
  }

  /// Soft logout — keeps account in saved accounts list (switch account flow)
  /// Used by AccountService.switchAccount — does NOT remove from saved list
  static Future<void> softLogout(BuildContext context) async {
    await perform(context, removeAccount: false);
  }
}