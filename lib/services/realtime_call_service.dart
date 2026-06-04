import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

class RealtimeCallService {
  static final RealtimeCallService _i = RealtimeCallService._();
  factory RealtimeCallService() => _i;
  RealtimeCallService._();

  final _client = Supabase.instance.client;

  RealtimeChannel? _channel;
  StreamController<IncomingCallPayload>? _incomingCtrl;
  String? _listeningUserId;
  bool _isDisposed = false;

  Future<String?> _freshAccessToken() async {
    try {
      final refreshed = await _client.auth.refreshSession();
      final token = refreshed.session?.accessToken ??
          _client.auth.currentSession?.accessToken;
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      final token = _client.auth.currentSession?.accessToken;
      return (token == null || token.isEmpty) ? null : token;
    }
  }

  Future<String?> initiateCall({
    required String callId,
    required String callerId,
    required String callerName,
    required String calleeId,
    required String bookingId,
    String callType = 'video',
  }) async {
    try {
      await _client.from('call_sessions').insert({
        'caller_id': callerId,
        'caller_name': callerName,
        'callee_id': calleeId,
        'receiver_id': calleeId,
        'booking_id': bookingId,
        'channel_name': callId,
        'call_type': callType,
        'status': 'ringing',
      });
      debugPrint('RealtimeCall: initiated channel=$callId → $calleeId');

      try {
        final token = await _freshAccessToken();
        if (token == null) {
          throw Exception('Missing session token for call notification');
        }
        await _client.functions.invoke(
          'notify-incoming-call',
          headers: {'Authorization': 'Bearer $token'},
          body: {
            'callee_id': calleeId,
            'caller_name': callerName,
            'caller_id': callerId,
            'channel_name': callId,
            'booking_id': bookingId,
          },
        );
      } catch (e) {
        debugPrint('RealtimeCall: FCM push failed (non-fatal): $e');
      }

      return callId;
    } catch (e) {
      debugPrint('RealtimeCall initiateCall error: $e');
      return null;
    }
  }

  Future<void> cancelCall(String callId) async {
    try {
      await _client.from('call_sessions').update({'status': 'cancelled'}).eq('channel_name', callId);
    } catch (_) {}
  }

  Stream<IncomingCallPayload> listenForCalls(String myUserId) {
    _isDisposed = false;
    _incomingCtrl ??= StreamController<IncomingCallPayload>.broadcast();

    if (_listeningUserId == myUserId && _channel != null) {
      return _incomingCtrl!.stream;
    }

    _teardownChannel();
    _listeningUserId = myUserId;

    try {
      _channel = _client
          .channel('calls:$myUserId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'call_sessions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'callee_id',
              value: myUserId,
            ),
            callback: (payload) {
              if (_isDisposed) return;
              final row = payload.newRecord;
              if (row['status'] != 'ringing') return;

              final callId = row['channel_name']?.toString() ?? row['id']?.toString() ?? '';
              if (callId.isEmpty) return;

              _incomingCtrl?.add(IncomingCallPayload(
                callId: callId,
                callerId: row['caller_id']?.toString() ?? '',
                callerName: row['caller_name']?.toString() ?? 'Doctor',
                bookingId: row['booking_id']?.toString() ?? '',
              ));
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('RealtimeCall: listenForCalls error: $e');
    }

    return _incomingCtrl!.stream;
  }

  Future<void> acceptCall(String callId) async {
    try {
      await _client.from('call_sessions').update({'status': 'accepted'}).eq('channel_name', callId);
    } catch (_) {}
  }

  Future<void> declineCall(String callId) async {
    try {
      await _client.from('call_sessions').update({'status': 'declined'}).eq('channel_name', callId);
    } catch (_) {}
  }

  Future<void> endCall(String callId) async {
    try {
      await _client.from('call_sessions').update({'status': 'ended'}).eq('channel_name', callId);
    } catch (_) {}
  }

  void _teardownChannel() {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        channel.unsubscribe();
      } catch (_) {}
    }
  }

  void dispose() {
    _isDisposed = true;
    _listeningUserId = null;
    _teardownChannel();
    final ctrl = _incomingCtrl;
    _incomingCtrl = null;
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.close();
    }
  }
}

class IncomingCallPayload {
  final String callId;
  final String callerId;
  final String callerName;
  final String bookingId;

  const IncomingCallPayload({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.bookingId,
  });
}
