// lib/services/app_cache.dart
//
// Lightweight in-memory TTL cache — session-scoped only (cleared on logout).
//
// SECURITY RULES:
//   - Never cache medical_records, patient_vitals, prescriptions, lab results
//   - Never cache file URLs from medical_vault or insurance_vault
//   - Safe to cache: doctor listings, hospital data, lab listings, insurance plans
//   - Call AppCache.clear() on logout (SecureLogout does this automatically)
//
// Usage:
//   AppCache.set('hospitals', data, ttl: Duration(minutes: 5));
//   final cached = AppCache.get<List>('hospitals');
library;

class AppCache {
  AppCache._();

  static final Map<String, _CacheEntry> _store = {};

  // Keys that must NEVER be cached — medical/sensitive data
  static const _blockedPrefixes = [
    'medical_',
    'health_vault_',
    'prescription_',
    'lab_result_',
    'patient_vital_',
    'signed_url_',
    'insurance_vault_',
  ];

  static bool _isSensitive(String key) {
    for (final prefix in _blockedPrefixes) {
      if (key.startsWith(prefix)) return true;
    }
    return false;
  }

  /// Store any value with an optional TTL (default 5 minutes).
  /// Silently ignores attempts to cache sensitive keys.
  static void set(
    String key,
    dynamic value, {
    Duration ttl = const Duration(minutes: 5),
  }) {
    if (_isSensitive(key)) return; // silent guard
    _store[key] = _CacheEntry(
      value: value,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  /// Returns the cached value, or null if missing / expired.
  static T? get<T>(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _store.remove(key);
      return null;
    }
    return entry.value as T?;
  }

  /// Remove a single key.
  static void remove(String key) => _store.remove(key);

  /// Wipe everything — called by SecureLogout.perform().
  static void clear() => _store.clear();

  /// Returns true if a non-expired entry exists.
  static bool has(String key) => get(key) != null;
}

class _CacheEntry {
  final dynamic value;
  final DateTime expiresAt;
  const _CacheEntry({required this.value, required this.expiresAt});
}