import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zego_uikit/zego_uikit.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

import 'config/env_config.dart';
import 'health_vault_screen.dart';
import 'supabase_handler.dart';

// IMPORTANT: this must export `navigatorKey` (GlobalKey<NavigatorState>)
import 'main.dart';

class VideoCallPage extends StatefulWidget {
  final String callID;
  final String userID;
  final String userName;

  final String patientID;
  final String patientName;

  final String professionalRole;
  final Map<String, dynamic> appointmentData;
  final String bookingId;

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
  });

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> with WidgetsBindingObserver {
  static const int _maxCallMinutes = 60;
  static const int _backgroundMinutes = 5;

  bool get _isNurseTriage => widget.professionalRole.toLowerCase() == 'nurse';

  Timer? _inactivityTimer;
  DateTime? _backgroundedAt;

  late final String roomId;

  bool _ending = false;        // prevents double end logic
  bool _navigatedAway = false; // prevents double navigation

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ✅ use EXACT callID used by invitation sender
    roomId = widget.callID.trim();

    // ✅ auto hangup after max duration
    _inactivityTimer = Timer(const Duration(minutes: _maxCallMinutes), _triggerAutoHangup);
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ✅ keep your own lifecycle logic (avoid calling super in older/varied plugins)
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
    // If already ending, do nothing
    if (_ending) return;

    try {
      await ZegoUIKit().leaveRoom();
    } catch (_) {}

    await _endCallAndNavigate();
  }

  /// ✅ Single source of truth for end-call flow
  Future<void> _endCallAndNavigate() async {
    if (_ending) return;
    _ending = true;

    final String finalStatus = _isNurseTriage ? 'confirmed' : 'completed';

    await _updateCallStatus(finalStatus, widget.bookingId);

    _navigateToVaultWithGlobalNavigator();
  }

  @override
  Widget build(BuildContext context) {
    final String zegoUserId = widget.userID.trim();

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: ZegoUIKitPrebuiltCall(
            appID: EnvConfig.zegoAppId,
            appSign: EnvConfig.zegoAppSign,
            userID: zegoUserId,
            userName: widget.userName,
            callID: roomId,

            // ✅ IMPORTANT: defaultAction FIRST to let Zego close its call UI
            events: ZegoUIKitPrebuiltCallEvents(
              onCallEnd: (ZegoCallEndEvent event, VoidCallback defaultAction) {
                defaultAction(); // Zego closes call + may pop this page internally
                _endCallAndNavigate(); // then do DB + navigation safely
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
        ),
      ),
    );
  }

  Future<void> _updateCallStatus(String status, String id) async {
    try {
      await SupabaseHandler().client.from('bookings').update({
        'status': status.toLowerCase(),
        'caller_role': widget.professionalRole.toLowerCase(),
        if (_isNurseTriage) 'nurse_seen': true,
      }).eq('id', id);

      debugPrint("Sync: Status set to $status for booking: $id");
    } catch (e) {
      debugPrint("DB Sync Error: $e");
    }
  }

  void _navigateToVaultWithGlobalNavigator() {
    if (_navigatedAway) return;
    _navigatedAway = true;

    // ✅ No BuildContext usage (avoids disposed-context crash / black screen)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav == null) return;

      nav.pushReplacement(
        MaterialPageRoute(
          builder: (_) => HealthVaultScreen(
            forceUploadMode: true,
            activePatientId: widget.patientID,
            userRole: widget.professionalRole,
            appointmentData: widget.appointmentData,
          ),
        ),
      );
    });
  }
}