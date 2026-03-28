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
    required String callId,       // normalised Zego room id (used as channel_name)
    required String callerId,
    required String callerName,
    required String calleeId,     // patient auth uid
    required String bookingId,
    String callType = 'video',
  }) async {
    try {
      await _client.from('call_sessions').insert({
        // id has gen_random_uuid() default — let DB generate it
        'caller_id':    callerId,
        'caller_name':  callerName,
        'callee_id':    calleeId,
        'receiver_id':  calleeId,   // schema has both callee_id + receiver_id
        'booking_id':   bookingId,
        'channel_name': callId,     // Zego room ID — what both sides join
        'call_type':    callType,
        'status':       'ringing',
      });
      debugPrint('RealtimeCall: initiated channel=$callId → $calleeId');

      // Send FCM push so patient phone wakes up even when backgrounded.
      // Realtime alone only works when the app is foregrounded.
      try {
        await _client.functions.invoke('notify-incoming-call', body: {
          'callee_id':   calleeId,
          'caller_name': callerName,
          'channel_name': callId,
          'booking_id':  bookingId,
        });
        debugPrint('RealtimeCall: FCM push sent to $calleeId');
      } catch (e) {
        // Non-fatal — Realtime still works if app is foregrounded
        debugPrint('RealtimeCall: FCM push failed (non-fatal): $e');
      }

      return callId;
    } catch (e) {
      debugPrint('RealtimeCall initiateCall error: \$e');
      return null;
    }
  }

  /// Cancel a pending call (caller hung up before answer).
  Future<void> cancelCall(String callId) async {
    try {
      await _client
          .from('call_sessions')
          .update({'status': 'cancelled'})
          .eq('channel_name', callId);
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
              debugPrint('🔔 Realtime call received: status=${row['status']}, '
                  'callee=${row['callee_id']}, channel=${row['channel_name']}');
              if (row['status'] != 'ringing') return;
              final callId = row['channel_name']?.toString() ?? row['id']?.toString() ?? '';
              if (callId.isEmpty) {
                debugPrint('⚠️ Incoming call has no channel_name, skipping');
                return;
              }
              _incomingCtrl?.add(IncomingCallPayload(
                callId:     callId,
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
          .eq('channel_name', callId);
    } catch (_) {}
  }

  /// Decline an incoming call.
  Future<void> declineCall(String callId) async {
    try {
      await _client
          .from('call_sessions')
          .update({'status': 'declined'})
          .eq('channel_name', callId);
    } catch (_) {}
  }

  // ── Both sides ───────────────────────────────────────────────────────────

  /// Update status to ended and clean up.
  Future<void> endCall(String callId) async {
    try {
      await _client
          .from('call_sessions')
          .update({'status': 'ended'})
          .eq('channel_name', callId);
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
