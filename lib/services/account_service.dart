import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountService {
  static const _storage = FlutterSecureStorage();
  static const _key = 'saved_accounts';

  /// Saves the current session with a safety check on user data
  static Future<void> saveCurrentAccount() async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) return;

    // Refresh user to ensure we have the absolute latest metadata (role, name, etc.)
    // This prevents the "Loading Profile" loop
    final user = session.user;
    
    final accountsJson = await _storage.read(key: _key);
    List<dynamic> accounts = accountsJson != null ? jsonDecode(accountsJson) : [];

    accounts.removeWhere((acc) => acc['id'] == user.id);

    accounts.add({
      'id': user.id,
      'email': user.email,
      'refresh_token': session.refreshToken,
      // Priority: check metadata first, then fallback
      'full_name': user.userMetadata?['full_name'] ?? 'User',
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

  /// Improved Switch Logic
  static Future<void> switchAccount(String refreshToken) async {
    try {
      // Use setSession but wrap it to ensure it completes
      await Supabase.instance.client.auth.setSession(refreshToken);
      
      // Crucial: Wait for the client to register the new user before saving
      await Future.delayed(const Duration(milliseconds: 500));
      await saveCurrentAccount();
    } catch (e) {
      debugPrint("DEBUG: Switch Account Failed: $e");
      rethrow;
    }
  }

  static Future<void> removeAccount(String userId) async {
    final jsonString = await _storage.read(key: _key);
    if (jsonString == null) return;
    
    List<dynamic> accounts = jsonDecode(jsonString);
    accounts.removeWhere((acc) => acc['id'] == userId);
    await _storage.write(key: _key, value: jsonEncode(accounts));
  }
}