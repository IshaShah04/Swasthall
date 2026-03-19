import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountService {
  static const _storage = FlutterSecureStorage();
  static const _key = 'saved_accounts';

  static Future<void> saveCurrentAccount() async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    final user = client.auth.currentUser;

    if (session == null || user == null) return;
    if (session.refreshToken == null || session.refreshToken!.isEmpty) return;

    final accountsJson = await _storage.read(key: _key);
    final List<dynamic> accounts =
        accountsJson != null ? jsonDecode(accountsJson) : [];

    accounts.removeWhere((acc) => acc['id'] == user.id);

    accounts.add({
      'id': user.id,
      'email': user.email,
      'refresh_token': session.refreshToken,
      'full_name': user.userMetadata?['full_name'] ?? user.email ?? 'User',
      'role': user.userMetadata?['role'] ?? 'patient',
      'avatar_url': user.userMetadata?['avatar_url'],
      'last_login': DateTime.now().toIso8601String(),
    });

    await _storage.write(key: _key, value: jsonEncode(accounts));
    debugPrint("DEBUG: Account Service saved user: ${user.id}");
  }

  static Future<List<Map<String, dynamic>>> getSavedAccounts() async {
    try {
      final jsonString = await _storage.read(key: _key);
      if (jsonString == null) return [];
      return List<Map<String, dynamic>>.from(jsonDecode(jsonString));
    } catch (e) {
      debugPrint("DEBUG: Error reading accounts: $e");
      return [];
    }
  }

  static Future<void> switchAccount(String refreshToken) async {
    try {
      final response =
          await Supabase.instance.client.auth.setSession(refreshToken);

      if (response.session == null || response.user == null) {
        throw Exception('Session restore failed');
      }
    } catch (e) {
      debugPrint("DEBUG: Switch Account Failed: $e");
      rethrow;
    }

    try {
      await saveCurrentAccount();
    } catch (e) {
      debugPrint("DEBUG: saveCurrentAccount after switch failed: $e");
    }
  }

  static Future<void> removeAccount(String userId) async {
    final jsonString = await _storage.read(key: _key);
    if (jsonString == null) return;

    final List<dynamic> accounts = jsonDecode(jsonString);
    accounts.removeWhere((acc) => acc['id'] == userId);
    await _storage.write(key: _key, value: jsonEncode(accounts));
  }
}