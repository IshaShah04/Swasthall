// lib/services/offline_booking_queue.dart
//
// Queues paid booking attempts locally when the network/DB is unavailable.
// Retries automatically when connectivity is restored.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class QueuedBooking {
  final String idempotencyKey;
  final Map<String, dynamic> params;
  final DateTime queuedAt;
  final String rpcName;
  int retryCount;

  QueuedBooking({
    required this.idempotencyKey,
    required this.params,
    required this.queuedAt,
    required this.rpcName,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'idempotencyKey': idempotencyKey,
        'params': params,
        'queuedAt': queuedAt.toIso8601String(),
        'rpcName': rpcName,
        'retryCount': retryCount,
      };

  factory QueuedBooking.fromJson(Map<String, dynamic> j) => QueuedBooking(
        idempotencyKey: j['idempotencyKey'] as String,
        params: Map<String, dynamic>.from(j['params'] as Map),
        queuedAt: DateTime.parse(j['queuedAt'] as String),
        rpcName: (j['rpcName'] as String?)?.trim().isNotEmpty == true
            ? (j['rpcName'] as String).trim()
            : 'book_appointment_atomic_paid',
        retryCount: (j['retryCount'] as int?) ?? 0,
      );
}

class OfflineBookingQueue {
  OfflineBookingQueue._();

  static const _storage = FlutterSecureStorage();
  static const _queueKey = 'offline_booking_queue_v2';
  static const _maxRetries = 5;
  static const _maxQueueAge = Duration(hours: 24);
  static bool _isRetrying = false;

  static Future<Map<String, dynamic>> submit({
    required Map<String, dynamic> rpcParams,
    String rpcName = 'book_appointment_atomic_paid',
  }) async {
    final existingKey = (rpcParams['p_idempotency_key'] ?? '').toString().trim();
    final key = existingKey.isNotEmpty ? existingKey : const Uuid().v4();
    final paramsWithKey = {...rpcParams, 'p_idempotency_key': key};

    try {
      final result = await _callRpc(rpcName, paramsWithKey);
      return {'success': true, 'booking': result};
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      final isTransient = _isTransientError(errStr);
      final isHard = _isHardError(errStr);

      if (isHard) {
        return {'success': false, 'error': e.toString()};
      }

      if (isTransient) {
        await _enqueue(QueuedBooking(
          idempotencyKey: key,
          params: paramsWithKey,
          queuedAt: DateTime.now(),
          rpcName: rpcName,
        ));
        return {'success': false, 'queued': true};
      }

      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<void> retryAll() async {
    if (_isRetrying) return;
    _isRetrying = true;

    try {
      final queue = await _loadQueue();
      if (queue.isEmpty) return;

      final kept = <QueuedBooking>[];

      for (final booking in queue) {
        if (DateTime.now().difference(booking.queuedAt) > _maxQueueAge) {
          continue;
        }
        if (booking.retryCount >= _maxRetries) {
          continue;
        }

        try {
          await _callRpc(booking.rpcName, booking.params);
          debugPrint('OfflineQueue: booking ${booking.idempotencyKey} submitted');
        } catch (e) {
          final errStr = e.toString().toLowerCase();
          if (_isHardError(errStr) || errStr.contains('idempotency')) {
            continue;
          }
          booking.retryCount++;
          kept.add(booking);
        }
      }

      await _saveQueue(kept);
    } finally {
      _isRetrying = false;
    }
  }

  static Future<int> pendingCount() async {
    final q = await _loadQueue();
    return q.length;
  }

  static Future<void> clear() async {
    await _storage.delete(key: _queueKey);
  }

  static bool _isTransientError(String errStr) {
    return errStr.contains('socket') ||
        errStr.contains('network') ||
        errStr.contains('timeout') ||
        errStr.contains('connection') ||
        errStr.contains('500') ||
        errStr.contains('502') ||
        errStr.contains('503') ||
        errStr.contains('504') ||
        errStr.contains('unavailable');
  }

  static bool _isHardError(String errStr) {
    return errStr.contains('already booked') ||
        errStr.contains('duplicate active booking') ||
        errStr.contains('slot') ||
        errStr.contains('fully booked') ||
        errStr.contains('42p') ||
        errStr.contains('42703') ||
        errStr.contains('42883') ||
        errStr.contains('permission') ||
        errStr.contains('invalid payment provider') ||
        errStr.contains('verified payment transaction not found');
  }

  static Future<dynamic> _callRpc(String rpcName, Map<String, dynamic> params) {
    return Supabase.instance.client.rpc(rpcName, params: params);
  }

  static Future<void> _enqueue(QueuedBooking booking) async {
    final queue = await _loadQueue();
    final alreadyExists = queue.any((q) => q.idempotencyKey == booking.idempotencyKey);
    if (alreadyExists) return;
    queue.add(booking);
    await _saveQueue(queue);
  }

  static Future<List<QueuedBooking>> _loadQueue() async {
    try {
      final raw = await _storage.read(key: _queueKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => QueuedBooking.fromJson(Map<String, dynamic>.from(e as Map)))
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
