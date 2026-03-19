import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles web-compatible call signalling via Supabase Realtime.
///
/// Flow:
///   Caller  → [initiateCall]  → inserts row into call_sessions (status=ringing)
///   Callee  → [listenForCalls] → receives INSERT event → shows dialog
///   Callee accepts → [acceptCall] → updates status=accepted + navigates
///   Either  → [endCall]  → updates status=ended
///
/// On mobile the existing Zego invitation system still handles everything.
/// This service is only active when kIsWeb == true OR as fallback.
class RealtimeCallService {
  static final RealtimeCallService _i = RealtimeCallService._();
  factory RealtimeCallService() => _i;
  RealtimeCallService._();

  final _client = Supabase.instance.client;

  RealtimeChannel? _channel;
  StreamController<IncomingCallPayload>? _incomingCtrl;

  // ── Caller side ─────────────────────────────────────────────────────────

  /// Write a call_sessions row so the patient's listener fires.
  Future<String?> initiateCall({
    required String callId,       // normalised Zego room id
    required String callerId,
    required String callerName,
    required String calleeId,     // patient auth uid
    required String bookingId,
  }) async {
    try {
      await _client.from('call_sessions').insert({
        'id':          callId,
        'caller_id':   callerId,
        'caller_name': callerName,
        'callee_id':   calleeId,
        'booking_id':  bookingId,
        'status':      'ringing',
        'created_at':  DateTime.now().toIso8601String(),
      });
      debugPrint('RealtimeCall: initiated $callId → $calleeId');
      return callId;
    } catch (e) {
      debugPrint('RealtimeCall initiateCall error: $e');
      return null;
    }
  }

  /// Cancel a pending call (caller hung up before answer).
  Future<void> cancelCall(String callId) async {
    try {
      await _client
          .from('call_sessions')
          .update({'status': 'cancelled'})
          .eq('id', callId);
    } catch (_) {}
  }

  // ── Callee side ─────────────────────────────────────────────────────────

  /// Start listening for incoming calls addressed to [myUserId].
  /// Returns a stream of [IncomingCallPayload].
  Stream<IncomingCallPayload> listenForCalls(String myUserId) {
    _incomingCtrl?.close();
    _incomingCtrl = StreamController<IncomingCallPayload>.broadcast();

    try {
      _channel?.unsubscribe();
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
              final row = payload.newRecord;
              if (row['status'] != 'ringing') return;
              _incomingCtrl?.add(IncomingCallPayload(
                callId:     row['id']?.toString() ?? '',
                callerId:   row['caller_id']?.toString() ?? '',
                callerName: row['caller_name']?.toString() ?? 'Doctor',
                bookingId:  row['booking_id']?.toString() ?? '',
              ));
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('RealtimeCall: listenForCalls error: $e');
    }

    return _incomingCtrl!.stream;
  }

  /// Accept an incoming call.
  Future<void> acceptCall(String callId) async {
    try {
      await _client
          .from('call_sessions')
          .update({'status': 'accepted'})
          .eq('id', callId);
    } catch (_) {}
  }

  /// Decline an incoming call.
  Future<void> declineCall(String callId) async {
    try {
      await _client
          .from('call_sessions')
          .update({'status': 'declined'})
          .eq('id', callId);
    } catch (_) {}
  }

  // ── Both sides ───────────────────────────────────────────────────────────

  /// Update status to ended and clean up.
  Future<void> endCall(String callId) async {
    try {
      await _client
          .from('call_sessions')
          .update({'status': 'ended'})
          .eq('id', callId);
    } catch (_) {}
  }

  void dispose() {
    _channel?.unsubscribe();
    _incomingCtrl?.close();
    _channel = null;
    _incomingCtrl = null;
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
