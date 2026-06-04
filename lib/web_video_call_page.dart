import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:zego_express_engine/zego_express_engine.dart';

import 'config/env_config.dart';
import 'services/realtime_call_service.dart';
import 'supabase_handler.dart';
import 'main.dart';

/// Web-only video call page using ZegoExpressEngine directly.
/// ZegoUIKitPrebuiltCall uses dart:io (Platform.isAndroid) which crashes on web.
/// ZegoExpressEngine supports Flutter Web natively.
///
/// Both sides (web + mobile) join the same roomID so they connect to each other.
class WebVideoCallPage extends StatefulWidget {
  final String callID;           // Zego room ID (e.g. room_83e013f7...)
  final String userID;           // Zego user ID of the caller
  final String userName;
  final String patientID;
  final String patientName;
  final String professionalRole;
  final String bookingId;

  const WebVideoCallPage({
    super.key,
    required this.callID,
    required this.userID,
    required this.userName,
    required this.patientID,
    required this.patientName,
    required this.professionalRole,
    required this.bookingId,
  });

  @override
  State<WebVideoCallPage> createState() => _WebVideoCallPageState();
}

class _WebVideoCallPageState extends State<WebVideoCallPage> {
  // ── State ──────────────────────────────────────────────────────────────
  bool _engineReady   = false;
  bool _inRoom        = false;
  bool _micOn         = true;
  bool _cameraOn      = true;
  bool _ending        = false;

  Widget? _localView;
  Widget? _remoteView;
  String? _remoteStreamId;   // stream ID of the patient when they join

  Timer? _maxDurationTimer;

  // Stream IDs follow convention: "{userId}_main"
  String get _myStreamId => '${widget.userID}_main';

  @override
  void initState() {
    super.initState();
    _initAndJoin();
    _maxDurationTimer = Timer(const Duration(minutes: 60), _hangUp);
  }

  @override
  void dispose() {
    _maxDurationTimer?.cancel();
    _leaveAndDestroy();
    super.dispose();
  }

  // ── Zego setup ─────────────────────────────────────────────────────────

  Future<void> _initAndJoin() async {
    // 1. Create engine — web does NOT support appSign, omit it.
    //    Token is passed in loginRoom instead.
    await ZegoExpressEngine.createEngineWithProfile(
      ZegoEngineProfile(
        EnvConfig.zegoAppId,
        ZegoScenario.Default,
        // No appSign here — web uses token auth in loginRoom
      ),
    );

    // 2. Register event handlers BEFORE joining room
    ZegoExpressEngine.onRoomStreamUpdate = _onRoomStreamUpdate;
    ZegoExpressEngine.onRoomStateUpdate  = _onRoomStateUpdate;

    // 3. Create local preview view
    final localView = await ZegoExpressEngine.instance.createCanvasView((id) {
      ZegoExpressEngine.instance.startPreview(
        canvas: ZegoCanvas(id, viewMode: ZegoViewMode.AspectFill),
      );
    });

    if (!mounted) return;
    setState(() {
      _localView   = localView;
      _engineReady = true;
    });

    // 4. Login room with token auth.
    //    Token expires in 1 hour (3600s). For production, generate server-side.
    //    For development/pilot, Zego debug token works:
    //    https://zegocloud.com/docs/video-call/get-started/flutter-web
    final token = await _fetchToken(widget.callID, widget.userID);
    if (token == null) {
      debugPrint('[WebCall] Token fetch failed — cannot join room');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to get call token. Try again.')),
        );
        Navigator.of(context).pop();
      }
      return;
    }

    final user = ZegoUser(widget.userID, widget.userName);
    final config = ZegoRoomConfig.defaultConfig()
      ..token = token
      ..isUserStatusNotify = true;  // notify when other user joins/leaves

    await ZegoExpressEngine.instance.loginRoom(
      widget.callID,
      user,
      config: config,
    );

    // 5. Start publishing local stream
    await ZegoExpressEngine.instance.startPublishingStream(_myStreamId);
  }

  /// Fetch a Zego token from your Supabase edge function.
  /// The edge function uses your Zego ServerSecret (never expose in client).
  /// Falls back to null on error.
  Future<String?> _fetchToken(String roomId, String userId) async {
    try {
      debugPrint('[WebCall] Fetching token for room=$roomId user=$userId');

      // Refresh session first
      try {
        await SupabaseHandler().client.auth.refreshSession();
      } catch (e) {
        debugPrint('[WebCall] Session refresh error: $e');
      }

      final session = SupabaseHandler().client.auth.currentSession;
      final accessToken = session?.accessToken;
      debugPrint('[WebCall] Session user=${session?.user.id} token_len=${accessToken?.length}');

      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('[WebCall] Missing auth token; cannot request call token');
        return null;
      }

      // Use raw http.post instead of functions.invoke() — Flutter Web's
      // Supabase client ignores the headers param and sends a stale JWT.
      // Raw HTTP with explicit headers is reliable on all platforms.
      final supabaseUrl = EnvConfig.supabaseUrl;
      final anonKey     = EnvConfig.supabaseAnonKey;

      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/zego-token'),
        headers: {
          'Content-Type':  'application/json',
          'apikey':        anonKey,
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'room_id':        roomId,
          'user_id':        userId,
          'expire_seconds': 3600,
        }),
      );

      debugPrint('[WebCall] HTTP ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}');

      if (response.statusCode == 200) {
        final data  = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token']?.toString();
        if (token != null && token.isNotEmpty) {
          debugPrint('[WebCall] Token received, length=${token.length}');
          return token;
        }
      }
      debugPrint('[WebCall] Token fetch failed: ${response.statusCode} ${response.body}');
      return null;
    } catch (e, stack) {
      debugPrint('[WebCall] Token fetch error: $e');
      debugPrint('[WebCall] Stack: $stack');
      return null;
    }
  }

  void _onRoomStateUpdate(String roomID, ZegoRoomState state,
      int errorCode, Map<String, dynamic> extendedData) {
    debugPrint('[WebCall] Room state: $state, error: $errorCode');
    if (!mounted) return;
    setState(() => _inRoom = state == ZegoRoomState.Connected);
  }

  Future<void> _onRoomStreamUpdate(String roomID, ZegoUpdateType updateType,
      List<ZegoStream> streamList, Map<String, dynamic> extendedData) async {
    if (updateType == ZegoUpdateType.Add) {
      for (final stream in streamList) {
        // Skip our own stream
        if (stream.streamID == _myStreamId) continue;

        _remoteStreamId = stream.streamID;

        // Create a canvas for the remote video
        final remoteView = await ZegoExpressEngine.instance.createCanvasView((id) {
          ZegoExpressEngine.instance.startPlayingStream(
            stream.streamID,
            canvas: ZegoCanvas(id, viewMode: ZegoViewMode.AspectFill),
          );
        });

        if (!mounted) return;
        setState(() => _remoteView = remoteView);
      }
    } else if (updateType == ZegoUpdateType.Delete) {
      for (final stream in streamList) {
        if (stream.streamID == _remoteStreamId) {
          await ZegoExpressEngine.instance.stopPlayingStream(stream.streamID);
          if (!mounted) return;
          setState(() {
            _remoteView    = null;
            _remoteStreamId = null;
          });
        }
      }
    }
  }

  // ── Call controls ───────────────────────────────────────────────────────

  Future<void> _toggleMic() async {
    _micOn = !_micOn;
    await ZegoExpressEngine.instance.muteMicrophone(!_micOn);
    setState(() {});
  }

  Future<void> _toggleCamera() async {
    _cameraOn = !_cameraOn;
    await ZegoExpressEngine.instance.enableCamera(_cameraOn);
    setState(() {});
  }

  Future<void> _hangUp() async {
    if (_ending) return;
    _ending = true;

    final role = widget.professionalRole.toLowerCase();

    try {
      if (role == 'nurse') {
        await SupabaseHandler().client.rpc(
          'mark_nurse_triaged',
          params: {'p_booking_id': widget.bookingId},
        );
      } else {
        await SupabaseHandler().client.rpc(
          'mark_booking_completed',
          params: {'p_booking_id': widget.bookingId},
        );
      }
    } catch (_) {
      // Keep call cleanup non-blocking. The queue can be refreshed manually if
      // the network drops exactly when the call ends.
    }

    await RealtimeCallService().endCall(widget.callID);
    await _leaveAndDestroy();

    if (!mounted) return;
    navigatorKey.currentState?.pop();
  }

  Future<void> _leaveAndDestroy() async {
    try {
      await ZegoExpressEngine.instance.stopPreview();
      await ZegoExpressEngine.instance.stopPublishingStream();
      if (_remoteStreamId != null) {
        await ZegoExpressEngine.instance.stopPlayingStream(_remoteStreamId!);
      }
      await ZegoExpressEngine.instance.logoutRoom(widget.callID);
      await ZegoExpressEngine.destroyEngine();
    } catch (_) {}
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [

              // ── Remote video (full screen) ────────────────────────────
              if (_remoteView != null)
                Positioned.fill(child: _remoteView!)
              else
                Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
                        child: const Icon(Icons.person_rounded,
                            size: 48, color: Color(0xFF6366F1)),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _inRoom
                            ? 'Waiting for ${widget.patientName}...'
                            : 'Connecting...',
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ],
                  ),
                ),

              // ── Local video preview (picture-in-picture) ─────────────
              if (_localView != null)
                Positioned(
                  top: 16,
                  right: 16,
                  width: 100,
                  height: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _localView!,
                  ),
                ),

              // ── Top bar ───────────────────────────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.videocam_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${widget.professionalRole} · ${widget.patientName}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                        ),
                      ),
                      if (!_engineReady)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Bottom controls ───────────────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _controlButton(
                        icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                        label: _micOn ? 'Mute' : 'Unmute',
                        onTap: _toggleMic,
                        active: _micOn,
                      ),
                      // Hang up
                      GestureDetector(
                        onTap: _hangUp,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.call_end_rounded,
                              color: Colors.white, size: 28),
                        ),
                      ),
                      _controlButton(
                        icon: _cameraOn
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        label: _cameraOn ? 'Camera' : 'No cam',
                        onTap: _toggleCamera,
                        active: _cameraOn,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool active,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}
