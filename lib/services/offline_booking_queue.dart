// lib/services/offline_booking_queue.dart
//
// Queues booking attempts locally when the network/DB is unavailable.
// Retries automatically when connectivity is restored.
//
// HOW IT WORKS:
//   1. consultation_payment_screen.dart calls OfflineBookingQueue.submit()
//      instead of calling the RPC directly.
//   2. If the RPC succeeds → booking confirmed normally.
//   3. If the RPC fails (network/DB down) → saved to secure queue.
//   4. On next app launch or when connectivity restores → auto-retried.
//   5. Patient sees "Booking queued — will confirm shortly" instead of error.
//
// SECURITY:
//   - Queue stored in flutter_secure_storage (encrypted on device).
//   - Booking data contains no sensitive medical info (just slot/time/amount).
//   - Queue is cleared after successful submission or on logout.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class QueuedBooking {
  final String idempotencyKey;
  final Map<String, dynamic> params;
  final DateTime queuedAt;
  int retryCount;

  QueuedBooking({
    required this.idempotencyKey,
    required this.params,
    required this.queuedAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'idempotencyKey': idempotencyKey,
        'params': params,
        'queuedAt': queuedAt.toIso8601String(),
        'retryCount': retryCount,
      };

  factory QueuedBooking.fromJson(Map<String, dynamic> j) => QueuedBooking(
        idempotencyKey: j['idempotencyKey'] as String,
        params: Map<String, dynamic>.from(j['params'] as Map),
        queuedAt: DateTime.parse(j['queuedAt'] as String),
        retryCount: (j['retryCount'] as int?) ?? 0,
      );
}

class OfflineBookingQueue {
  OfflineBookingQueue._();

  static const _storage = FlutterSecureStorage();
  static const _queueKey = 'offline_booking_queue';
  static const _maxRetries = 5;
  static const _maxQueueAge = Duration(hours: 24);
  static bool _isRetrying = false;

  // ─────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────

  /// Submit a booking. Tries immediately; queues if offline/DB down.
  /// Returns: {'success': true, 'booking': {...}} on success
  ///          {'success': false, 'queued': true} if queued for retry
  ///          {'success': false, 'error': '...'} on hard failure
  static Future<Map<String, dynamic>> submit({
    required Map<String, dynamic> rpcParams,
  }) async {
    // Generate idempotency key — prevents duplicates on retry
    final key = const Uuid().v4();
    final paramsWithKey = {...rpcParams, 'p_idempotency_key': key};

    try {
      final result = await _callRpc(paramsWithKey);
      return {'success': true, 'booking': result};
    } catch (e) {
      final errStr = e.toString().toLowerCase();

      // Transient errors → queue for retry
      final isTransient = errStr.contains('socket') ||
          errStr.contains('network') ||
          errStr.contains('timeout') ||
          errStr.contains('connection') ||
          errStr.contains('500') ||
          errStr.contains('503') ||
          errStr.contains('unavailable');

      // Hard errors → don't queue (slot taken, validation failed etc.)
      final isHard = errStr.contains('already booked') ||
          errStr.contains('slot') ||
          errStr.contains('42p') ||   // Postgres errors
          errStr.contains('23') ||    // constraint violations
          errStr.contains('permission');

      if (isHard) {
        return {'success': false, 'error': e.toString()};
      }

      if (isTransient) {
        await _enqueue(QueuedBooking(
          idempotencyKey: key,
          params: paramsWithKey,
          queuedAt: DateTime.now(),
        ));
        return {'success': false, 'queued': true};
      }

      return {'success': false, 'error': e.toString()};
    }
  }

  /// Call on app launch and when connectivity restores.
  /// Retries all queued bookings.
  static Future<void> retryAll() async {
    if (_isRetrying) return;
    _isRetrying = true;

    try {
      final queue = await _loadQueue();
      if (queue.isEmpty) return;

      final toRemove = <String>[];
      final updated = <QueuedBooking>[];

      for (final booking in queue) {
        // Discard stale bookings (older than 24 hours)
        if (DateTime.now().difference(booking.queuedAt) > _maxQueueAge) {
          toRemove.add(booking.idempotencyKey);
          continue;
        }

        if (booking.retryCount >= _maxRetries) {
          toRemove.add(booking.idempotencyKey);
          continue;
        }

        try {
          await _callRpc(booking.params);
          toRemove.add(booking.idempotencyKey); // success
          debugPrint('OfflineQueue: booking ${booking.idempotencyKey} submitted');
        } catch (e) {
          final errStr = e.toString().toLowerCase();
          // Hard error — discard
          if (errStr.contains('already booked') ||
              errStr.contains('23') ||
              errStr.contains('idempotency')) {
            toRemove.add(booking.idempotencyKey);
          } else {
            // Still transient — keep and increment retry
            booking.retryCount++;
            updated.add(booking);
          }
        }
      }

      final remaining =
          queue.where((b) => !toRemove.contains(b.idempotencyKey)).toList();
      // Merge updated retry counts
      for (final u in updated) {
        final idx = remaining.indexWhere((b) => b.idempotencyKey == u.idempotencyKey);
        if (idx >= 0) remaining[idx] = u;
      }

      await _saveQueue(remaining);
    } finally {
      _isRetrying = false;
    }
  }

  /// How many bookings are waiting in the queue.
  static Future<int> pendingCount() async {
    final q = await _loadQueue();
    return q.length;
  }

  /// Clear queue on logout.
  static Future<void> clear() async {
    await _storage.delete(key: _queueKey);
  }

  // ─────────────────────────────────────────────────────────────────
  // PRIVATE HELPERS
  // ─────────────────────────────────────────────────────────────────

  static Future<dynamic> _callRpc(Map<String, dynamic> params) {
    return Supabase.instance.client
        .rpc('book_appointment_atomic', params: params);
  }

  static Future<void> _enqueue(QueuedBooking booking) async {
    final queue = await _loadQueue();
    queue.add(booking);
    await _saveQueue(queue);
  }

  static Future<List<QueuedBooking>> _loadQueue() async {
    try {
      final raw = await _storage.read(key: _queueKey);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => QueuedBooking.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveQueue(List<QueuedBooking> queue) async {
    await _storage.write(
      key: _queueKey,
      value: jsonEncode(queue.map((b) => b.toJson()).toList()),
    );
  }
}