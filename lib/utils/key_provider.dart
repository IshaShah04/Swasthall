import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'encryption_utils.dart';

class KeyProvider {
  static Uint8List? _cachedKey;
  static String? _cachedUid;

  /// Returns the derived 256-bit encryption key for the current session.
  /// Cached in memory — never written to disk.
  static Future<Uint8List> getKey() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw Exception('No active session');

    final uid = session.user.id;

    // Return cached key if same user
    if (_cachedKey != null && _cachedUid == uid) return _cachedKey!;

    final response = await Supabase.instance.client.functions.invoke(
      'get-encryption-salt',
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );

    if (response.status != 200) {
      throw Exception('Failed to fetch encryption salt: ${response.data}');
    }

    final derivedSalt = response.data['derived_salt'] as String;
    _cachedKey = await EncryptionUtils.deriveKey(uid, derivedSalt);
    _cachedUid = uid;

    return _cachedKey!;
  }

  /// Call on sign-out to clear the in-memory key.
  static void clearKey() {
    _cachedKey = null;
    _cachedUid = null;
  }
}
