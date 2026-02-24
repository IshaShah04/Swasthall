import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

import 'config/env_config.dart';
import 'health_vault_screen.dart';
import 'supabase_handler.dart';

class VideoCallPage extends StatefulWidget {
  final String callID;
  final String userID;
  final String userName;
  final String patientID;
  final String patientName;
  final String professionalRole;
  final Map<String, dynamic> appointmentData;
  final String bookingId; // Fixed: Defined properly

  const VideoCallPage({
    super.key,
    required this.callID,
    required this.userID,
    required this.userName,
    required this.patientID,
    required this.patientName,
    required this.professionalRole,
    required this.appointmentData,
    required this.bookingId, // Fixed: Required properly
  });

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  bool get _isNurseTriage => widget.professionalRole.toLowerCase() == 'nurse';
  bool _statusUpdatedOnEnd = false; // Prevent double-triggering

  @override
  void initState() {
    super.initState();
    // Use the explicit bookingId passed from navigation
    _updateCallStatus('consulting', widget.bookingId);
  }

  // Unified exit logic
  Future<void> _handleEndCall() async {
    if (_statusUpdatedOnEnd) return;
    
    String finalStatus = _isNurseTriage ? 'confirmed' : 'completed';
    await _updateCallStatus(finalStatus, widget.bookingId);
    _statusUpdatedOnEnd = true;
    
    if (mounted) {
      _redirectToVault();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent accidental swipe-back during life-saving calls
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // If they try to exit, treat it as ending the call
        await _handleEndCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: ZegoUIKitPrebuiltCall(
            appID: EnvConfig.zegoAppId,
            appSign: EnvConfig.zegoAppSign,
            userID: widget.userID,
            userName: widget.userName,
            callID: widget.callID,
            events: ZegoUIKitPrebuiltCallEvents(
              onCallEnd: (ZegoCallEndEvent event, VoidCallback defaultAction) async {
                await _handleEndCall();
                defaultAction(); 
              },
            ),
            config: ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
              ..audioVideoView.useVideoViewAspectFill = true
              ..topMenuBar = ZegoCallTopMenuBarConfig(
                title: "${widget.professionalRole} Session: ${widget.patientName}",
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
              ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateCallStatus(String status, String id) async {
    try {
      await SupabaseHandler().client
          .from('bookings')
          .update({
            'status': status,
            'caller_role': widget.professionalRole.toLowerCase(),
            if (_isNurseTriage) 'nurse_seen': true,
          })
          .eq('id', id);
      debugPrint("Sync: Status set to $status for ID: $id");
    } catch (e) {
      debugPrint("DB Sync Error: $e");
    }
  }

  void _redirectToVault() {
    // Short delay to ensure Zego UI has unmounted
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HealthVaultScreen(
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