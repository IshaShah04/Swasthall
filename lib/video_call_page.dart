import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zego_uikit/zego_uikit.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

import 'config/env_config.dart';
import 'supabase_handler.dart';
import 'main.dart';
import 'shared_widgets.dart';

class VideoCallPage extends StatefulWidget {
  final String callID;
  final String userID;
  final String userName;
  final String patientID;
  final String patientName;
  final String professionalRole;
  final Map<String, dynamic> appointmentData;
  final String bookingId;
  /// Optional: pass the parent TabController to switch to Completed tab after call
  final TabController? tabController;

  const VideoCallPage({
    super.key,
    required this.callID,
    required this.userID,
    required this.userName,
    required this.patientID,
    required this.patientName,
    required this.professionalRole,
    required this.appointmentData,
    required this.bookingId,
    this.tabController,
  });

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage>
    with WidgetsBindingObserver {
  static const int _maxCallMinutes = 60;
  static const int _backgroundMinutes = 5;

  bool get _isNurseTriage =>
      widget.professionalRole.toLowerCase() == 'nurse';

  Timer? _inactivityTimer;
  DateTime? _backgroundedAt;
  late final String _roomId;

  bool _ending = false;
  bool _navigatedAway = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Use the callID exactly as passed — caller and callee must match
    _roomId = widget.callID.trim();

    _inactivityTimer = Timer(
      const Duration(minutes: _maxCallMinutes),
      _triggerAutoHangup,
    );
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed && _backgroundedAt != null) {
      final diff = DateTime.now().difference(_backgroundedAt!);
      _backgroundedAt = null;
      if (diff > const Duration(minutes: _backgroundMinutes)) {
        _triggerAutoHangup();
      }
    }
  }

  Future<void> _triggerAutoHangup() async {
    if (_ending) return;
    try {
      await ZegoUIKit().leaveRoom();
    } catch (_) {}
    await _endCallAndNavigate();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // End-call flow
  //
  // CORRECT ORDER (matches ZEGO docs):
  //   1. Update DB status
  //   2. Call defaultAction() — ZEGO tears down room
  //   3. Navigate away (with 300ms delay so ZEGO finishes cleanup)
  //
  // This is wired from onCallEnd so defaultAction is always passed in.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _endCallAndNavigate({VoidCallback? defaultAction}) async {
    if (_ending) return;
    _ending = true;

    final String finalStatus = _isNurseTriage ? 'confirmed' : 'completed';
    await _updateCallStatus(finalStatus, widget.bookingId);

    // Run ZEGO's own cleanup if provided
    defaultAction?.call();

    // Give ZEGO 300ms to fully dispose its internal state before
    // we tear down the route — prevents "leaveRoom" race conditions
    _navigateAfterCall();
  }

  Future<void> _updateCallStatus(String status, String id) async {
    try {
      await SupabaseHandler().client.from('bookings').update({
        'status': status.toLowerCase(),
        'caller_role': widget.professionalRole.toLowerCase(),
        if (_isNurseTriage) 'nurse_seen': true,
      }).eq('id', id);

      debugPrint('Booking $id → $status');
    } catch (e) {
      debugPrint('DB sync error: $e');
    }
  }

  void _navigateAfterCall() {
    if (_navigatedAway) return;
    _navigatedAway = true;

    // 300ms lets ZEGO fully dispose before we touch the navigator
    Future.delayed(const Duration(milliseconds: 300), () {
      // Switch parent tab to Completed (index 1) if tabController provided
      widget.tabController?.animateTo(1);

      // Pop the VideoCallPage off the stack — no overlay, no new route
      final NavigatorState? nav = navigatorKey.currentState;
      nav?.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // ── Zego call UI (full screen) ───────────────────────────────
              ZegoUIKitPrebuiltCall(
                appID: EnvConfig.zegoAppId,
                appSign: EnvConfig.zegoAppSign,
                userID: widget.userID.trim(),
                userName: widget.userName,
                callID: _roomId,
                events: ZegoUIKitPrebuiltCallEvents(
                  onCallEnd: (ZegoCallEndEvent event, VoidCallback defaultAction) {
                    _endCallAndNavigate(defaultAction: defaultAction);
                  },
                ),
                config: ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
                  ..audioVideoView.useVideoViewAspectFill = true
                  ..turnOnCameraWhenJoining = true
                  ..topMenuBar = ZegoCallTopMenuBarConfig(
                    title: "${widget.professionalRole} Session: ${widget.patientName}",
                    isVisible: true,
                    buttons: const [
                      ZegoCallMenuBarButtonName.switchCameraButton,
                    ],
                  )
                  ..bottomMenuBar = ZegoCallBottomMenuBarConfig(
                    buttons: const [
                      ZegoCallMenuBarButtonName.toggleMicrophoneButton,
                      ZegoCallMenuBarButtonName.hangUpButton,
                      ZegoCallMenuBarButtonName.toggleCameraButton,
                      ZegoCallMenuBarButtonName.switchAudioOutputButton,
                    ],
                  ),
              ),

              // ── Patient history FAB (call continues underneath) ───────────
              // Only shown for professionals who have a patientID to look up
              if (widget.patientID.isNotEmpty)
                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    child: GestureDetector(
                      onTap: () => viewPatientHistory(
                        context,
                        widget.patientID,
                        widget.patientName,
                        userRole: widget.professionalRole,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.folder_shared_rounded,
                                color: Colors.white, size: 16),
                            SizedBox(width: 5),
                            Text(
                              'Records',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}