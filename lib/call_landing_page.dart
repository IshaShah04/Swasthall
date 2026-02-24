import 'package:flutter/material.dart';
import 'package:zego_uikit/zego_uikit.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

import 'config/env_config.dart';

class PatientVideoCallPage extends StatelessWidget {
  final String callID;           
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

  @override
  Widget build(BuildContext context) {
    // ROOM ID NORMALIZATION:
    // This MUST match the professional side logic exactly.
    // The professional side uses: "room_" + bookingId.replaceAll('-', '')
    String finalRoomID = callID.startsWith('room_') 
        ? callID 
        : "room_${callID.replaceAll('-', '')}";

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ZegoUIKitPrebuiltCall(
          appID: EnvConfig.zegoAppId,
          appSign: EnvConfig.zegoAppSign,
          userID: userID,
          userName: userName,
          callID: finalRoomID,
          events: ZegoUIKitPrebuiltCallEvents(
            onCallEnd: (ZegoCallEndEvent event, VoidCallback defaultAction) {
              // Standard Zego hang-up logic
              defaultAction(); 
              
              if (context.mounted) {
                // Return to BookingSuccessScreen
                Navigator.of(context).pop(); 
              }
            },
          ),
          // Using One-on-One Video Call Config
          config: ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
            ..audioVideoView.useVideoViewAspectFill = true
            ..audioVideoView.showAvatarInAudioMode = true
            ..audioVideoView.showUserNameOnView = false // Clean UI: Professional name is in top bar
            ..topMenuBar = ZegoCallTopMenuBarConfig(
              title: "Consultation: $professionalName",
              isVisible: true,
              buttons: [
                ZegoCallMenuBarButtonName.switchCameraButton,
              ],
            )
            ..bottomMenuBar = ZegoCallBottomMenuBarConfig(
              buttons: [
                ZegoCallMenuBarButtonName.toggleMicrophoneButton,
                ZegoCallMenuBarButtonName.hangUpButton,
                ZegoCallMenuBarButtonName.toggleCameraButton,
                ZegoCallMenuBarButtonName.switchAudioOutputButton,
              ],
            )
            ..layout = ZegoLayout.pictureInPicture(
              isSmallViewDraggable: true,
              // Removed invalid parameter 'switchLargeViewClickedSmallView'
            ),
        ),
      ),
    );
  }
}