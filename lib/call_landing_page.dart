import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zego_uikit/zego_uikit.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

import 'config/env_config.dart';

class PatientVideoCallPage extends StatefulWidget {
  /// ✅ For Option A: pass the exact callID used by inviter (already normalized)
  final String callID;

  /// ✅ For Option A: patient zego_uid (NOT auth UUID)
  final String userID;

  final String userName;
  final String professionalName;

  const PatientVideoCallPage({
    super.key,
    required this.callID,
    required this.userID,
    required this.userName,
    required this.professionalName,
  });

  static const String activeCallPrefsKey = "ACTIVE_VIDEO_CALL_ROOM";

  static Future<void> saveActiveCallRoom(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(activeCallPrefsKey, roomId);
  }

  static Future<void> clearActiveCallRoom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(activeCallPrefsKey);
  }

  static Future<String?> getSavedActiveCall() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(activeCallPrefsKey);
  }

  @override
  State<PatientVideoCallPage> createState() => _PatientVideoCallPageState();
}

class _PatientVideoCallPageState extends State<PatientVideoCallPage>
    with WidgetsBindingObserver {
  static const _maxCallMinutes = 60;
  static const _backgroundMinutes = 5;

  Timer? _inactivityTimer;
  DateTime? _backgroundedAt;

  late final String roomId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    /// ✅ IMPORTANT: do NOT renormalize here.
    /// Always join the exact callID used in the invitation sender.
    roomId = widget.callID.trim();

    // ✅ Save so we can auto-rejoin after crash/restart
    PatientVideoCallPage.saveActiveCallRoom(roomId);

    _inactivityTimer =
        Timer(const Duration(minutes: _maxCallMinutes), _onInactivityTimeout);
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

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

  void _onInactivityTimeout() => _triggerAutoHangup();

  Future<void> _triggerAutoHangup() async {
    try {
      await ZegoUIKit().leaveRoom();
    } catch (_) {}

    await PatientVideoCallPage.clearActiveCallRoom();

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final String zegoUserId = widget.userID.trim();
    final String zegoUserName =
        widget.userName.trim().isEmpty ? "Patient" : widget.userName.trim();

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: ZegoUIKitPrebuiltCall(
            appID: EnvConfig.zegoAppId,
            appSign: EnvConfig.zegoAppSign,
            userID: zegoUserId, // ✅ patient zego_uid
            userName: zegoUserName,
            callID: roomId, // ✅ exact room id from inviter

            events: ZegoUIKitPrebuiltCallEvents(
              onCallEnd: (ZegoCallEndEvent event, VoidCallback defaultAction) async {
                await PatientVideoCallPage.clearActiveCallRoom();
                defaultAction();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),

            config: ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
              ..audioVideoView.useVideoViewAspectFill = true
              ..audioVideoView.showAvatarInAudioMode = true
              ..audioVideoView.showUserNameOnView = false
              ..topMenuBar = ZegoCallTopMenuBarConfig(
                title: "Consultation: ${widget.professionalName}",
                isVisible: true,
                buttons: [ZegoCallMenuBarButtonName.switchCameraButton],
              )
              ..bottomMenuBar = ZegoCallBottomMenuBarConfig(
                buttons: [
                  ZegoCallMenuBarButtonName.toggleMicrophoneButton,
                  ZegoCallMenuBarButtonName.hangUpButton,
                  ZegoCallMenuBarButtonName.toggleCameraButton,
                  ZegoCallMenuBarButtonName.switchAudioOutputButton,
                ],
              )
              ..layout = ZegoLayout.pictureInPicture(isSmallViewDraggable: true),
          ),
        ),
      ),
    );
  }
}