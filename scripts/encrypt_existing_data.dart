// ignore_for_file: type=lint, unused_import, depend_on_referenced_packages, avoid_relative_lib_imports, avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:supabase/supabase.dart';
import '../lib/utils/encryption_utils.dart'; // Using relative path for the script

const batchSize = 100;

Future<void> main() async {
  // Load from local .env file — NEVER hardcode
  final env = File('.env.migration').readAsLinesSync()
    .where((l) => l.contains('='))
    .fold<Map<String, String>>({}, (map, line) {
      final parts = line.split('=');
      map[parts[0].trim()] = parts.sublist(1).join('=').trim();
      return map;
    });

  final supabaseUrl = env['SUPABASE_URL']!;
  final serviceRoleKey = env['SUPABASE_SERVICE_ROLE_KEY']!;
  final masterSalt = env['PII_ENCRYPTION_SALT']!;

  final client = SupabaseClient(supabaseUrl, serviceRoleKey);

  await _encryptTable(
    client: client,
    masterSalt: masterSalt,
    table: 'medical_records',
    sensitiveFields: ['diagnosis', 'notes', 'prescription'],
    userIdField: 'patient_id', // Assuming patient_id based on typical architecture (will adjust if needed)
  );

  await _encryptTable(
    client: client,
    masterSalt: masterSalt,
    table: 'patient_vitals',
    sensitiveFields: ['notes'],
    userIdField: 'patient_id', // Assuming patient_id
  );

  await _encryptTable(
    client: client,
    masterSalt: masterSalt,
    table: 'profiles',
    sensitiveFields: ['address', 'emergency_contact'],
    userIdField: 'id', // profiles.id IS the user_id
  );

  print('Migration complete.');
  client.dispose();
}

bool _isAlreadyEncrypted(String value) {
  try {
    final decoded = base64.decode(value);
    return decoded.length > 12; // IV (12 bytes) + at least some ciphertext
  } catch (_) {
    return false;
  }
}

Future<void> _encryptTable({
  required SupabaseClient client,
  required String masterSalt,
  required String table,
  required List<String> sensitiveFields,
  required String userIdField,
}) async {
  print('\nProcessing table: $table');
  int offset = 0;
  int totalUpdated = 0;

  while (true) {
    final rows = await client
        .from(table)
        .select()
        .range(offset, offset + batchSize - 1);

    if (rows.isEmpty) break;

    for (final row in rows) {
      final uid = row[userIdField] as String?;
      if (uid == null) continue;

      // Derive key for this user using master salt directly
      final key = await EncryptionUtils.deriveKey(uid, masterSalt);

      final updates = <String, dynamic>{};
      for (final field in sensitiveFields) {
        final value = row[field] as String?;
        if (value == null || _isAlreadyEncrypted(value)) continue;
        updates[field] = EncryptionUtils.encrypt(value, key);
      }

      if (updates.isNotEmpty) {
        await client.from(table).update(updates).eq('id', row['id']);
        totalUpdated++;
      }
    }

    print('  Processed ${offset + rows.length} rows, updated $totalUpdated so far...');
    offset += batchSize;
    if (rows.length < batchSize) break;
  }

  print('  Done. Total rows updated in $table: $totalUpdated');
}
