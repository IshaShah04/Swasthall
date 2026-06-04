import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zego_uikit/zego_uikit.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

import 'config/env_config.dart';
import 'theme_colors.dart';

class PatientVideoCallPage extends StatefulWidget {
  final String callID;
  final String userID;
  final String userName;
  final String professionalName;
  final String? bookingId;
  final String? professionalId;

  const PatientVideoCallPage({
    super.key,
    required this.callID,
    required this.userID,
    required this.userName,
    required this.professionalName,
    this.bookingId,
    this.professionalId,
  });

  @override
  State<PatientVideoCallPage> createState() => _PatientVideoCallPageState();
}

class _PatientVideoCallPageState extends State<PatientVideoCallPage>
    with WidgetsBindingObserver {
  static const int _maxCallMinutes = 60;
  static const int _backgroundMinutes = 5;

  final _supabase = Supabase.instance.client;

  Timer? _inactivityTimer;
  DateTime? _backgroundedAt;
  DateTime? _callStartTime;

  @override
  void initState() {
    super.initState();
    _callStartTime = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    _inactivityTimer = Timer(
      const Duration(minutes: _maxCallMinutes),
      _onInactivityTimeout,
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
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _backgroundedAt != null) {
      final diff = DateTime.now().difference(_backgroundedAt!);
      _backgroundedAt = null;
      if (diff > const Duration(minutes: _backgroundMinutes)) {
        _triggerAutoHangup();
      }
    }
  }

  void _onInactivityTimeout() {
    _triggerAutoHangup();
  }

  Future<void> _triggerAutoHangup() async {
    try {
      await ZegoUIKit().leaveRoom();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  int get _callDurationSeconds {
    if (_callStartTime == null) return 0;
    return DateTime.now().difference(_callStartTime!).inSeconds;
  }

  String _formatDuration(int seconds) {
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    if (m == 0) return "${s}s";
    return "${m}m ${s}s";
  }

  Future<void> _syncProfessionalAnalyticsForToday({
    required String doctorId,
  }) async {
    final today = DateTime.now().toIso8601String().split('T').first;

    try {
      final reviewRows = await _supabase
          .from('call_reviews')
          .select('rating, duration_seconds')
          .eq('doctor_id', doctorId)
          .gte('created_at', '${today}T00:00:00')
          .lt('created_at', '${today}T23:59:59.999999');

      final rows = (reviewRows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final completedCount = rows.length;

      final ratedRows = rows.where((r) => r['rating'] != null).toList();
      final avgRating = ratedRows.isEmpty
          ? 0.0
          : ratedRows
                  .map((r) => (r['rating'] as num).toDouble())
                  .reduce((a, b) => a + b) /
              ratedRows.length;

      final durationRows = rows
          .where((r) => r['duration_seconds'] != null && (r['duration_seconds'] as num).toInt() > 0)
          .toList();
      final avgDuration = durationRows.isEmpty
          ? 0.0
          : durationRows
                  .map((r) => (r['duration_seconds'] as num).toDouble())
                  .reduce((a, b) => a + b) /
              durationRows.length;

      final existing = await _supabase
          .from('professional_analytics_data')
          .select('id, cancelled_count')
          .eq('doctor_id', doctorId)
          .eq('date_period', today)
          .maybeSingle();

      final payload = <String, dynamic>{
        'doctor_id': doctorId,
        'date_period': today,
        'completed_count': completedCount,
        'cancelled_count': (existing?['cancelled_count'] as num?)?.toInt() ?? 0,
        'avg_rating': avgRating == 0 ? null : double.parse(avgRating.toStringAsFixed(2)),
        'avg_duration': avgDuration == 0 ? null : double.parse(avgDuration.toStringAsFixed(2)),
      };

      if (existing != null && existing['id'] != null) {
        await _supabase
            .from('professional_analytics_data')
            .update(payload)
            .eq('id', existing['id']);
      } else {
        await _supabase.from('professional_analytics_data').insert(payload);
      }
    } catch (e) {
      debugPrint('Professional analytics sync error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Rating sheet
  //
  // IMPORTANT: defaultAction is passed IN and called AFTER DB save.
  // This is the correct order:
  //   1. User submits rating → save to DB
  //   2. Call defaultAction() → ZEGO tears down room
  //   3. Navigator.pop() → dismiss the sheet
  //
  // Do NOT call defaultAction() before showing the sheet — it destroys the
  // widget tree and makes mounted checks fail.
  // ─────────────────────────────────────────────────────────────────────────
  void _showRatingSheet(int durationSeconds, VoidCallback defaultAction) {
    if (!mounted) {
      defaultAction();
      return;
    }

    int selectedRating = 0;
    final TextEditingController reviewController = TextEditingController();
    bool isSubmitting = false;
    BuildContext? ratingSheetContext;

    void closeRatingSheet() {
      final sheetContext = ratingSheetContext;
      if (sheetContext != null) {
        final navigator = Navigator.of(sheetContext);
        if (navigator.canPop()) {
          navigator.pop();
        }
      }
    }

    Future<void> saveAndEnd(int rating, String review) async {
      final currentUser = _supabase.auth.currentUser;
      try {
        final doctorId = widget.professionalId?.trim() ?? '';
        if (currentUser == null) {
          debugPrint('Rating save skipped: unauthenticated user');
        } else {
          await _supabase.from('call_reviews').insert({
            'booking_id': widget.bookingId,
            'doctor_id': widget.professionalId,
            'patient_id': currentUser.id,
            'rating': rating,
            'review_text': review.trim().isEmpty ? null : review.trim(),
            'duration_seconds': durationSeconds,
          });

          if (doctorId.isNotEmpty) {
            await _syncProfessionalAnalyticsForToday(doctorId: doctorId);
          }
        }
      } catch (e) {
        debugPrint('Rating save error: $e');
      }

      defaultAction();
      closeRatingSheet();
    }

    Future<void> skipAndEnd() async {
      final currentUser = _supabase.auth.currentUser;
      try {
        final doctorId = widget.professionalId?.trim() ?? '';
        if (currentUser == null) {
          debugPrint('Rating skip save skipped: unauthenticated user');
        } else {
          await _supabase.from('call_reviews').insert({
            'booking_id': widget.bookingId,
            'doctor_id': widget.professionalId,
            'patient_id': currentUser.id,
            'rating': null,
            'review_text': null,
            'duration_seconds': durationSeconds,
          });

          if (doctorId.isNotEmpty) {
            await _syncProfessionalAnalyticsForToday(doctorId: doctorId);
          }
        }
      } catch (e) {
        debugPrint('Rating skip save error: $e');
      }

      defaultAction();
      closeRatingSheet();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (sheetContext) {
        ratingSheetContext = sheetContext;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                left: 24,
                right: 24,
                top: 24,
              ),
              decoration: BoxDecoration(
                color: AppColors.cardBg(context),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Duration badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.indigoTint(context),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "Consultation: ${_formatDuration(durationSeconds)}",
                      style: const TextStyle(
                        color: Color(0xFF6366F1),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    "How was your consultation?",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "with ${widget.professionalName}",
                    style: TextStyle(color: AppColors.textMuted(context), fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  // Star rating
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final int star = i + 1;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedRating = star),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            selectedRating >= star
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 40,
                            color: selectedRating >= star
                                ? Colors.amber
                                : Colors.grey[300],
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),

                  // Comment field
                  TextField(
                    controller: reviewController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: "Leave a comment (optional)",
                      hintStyle: TextStyle(color: AppColors.textMuted(context), fontSize: 13),
                      filled: true,
                      fillColor: AppColors.inputFill(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: selectedRating == 0 || isSubmitting
                          ? null
                          : () async {
                              setSheetState(() => isSubmitting = true);
                              await saveAndEnd(selectedRating, reviewController.text);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        disabledBackgroundColor: Colors.grey[200],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: isSubmitting
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              "Submit & End",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Skip button
                  TextButton(
                    onPressed: isSubmitting ? null : () async => skipAndEnd(),
                    child: Text(
                      "Skip rating",
                      style: TextStyle(color: AppColors.textMuted(context), fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(reviewController.dispose);
  }

  @override
  Widget build(BuildContext context) {
    // room_id is already finalized and stored in the booking row.
    final String finalRoomID = widget.callID.trim();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ZegoUIKitPrebuiltCall(
          appID: EnvConfig.zegoAppId,
          appSign: '', // Security: token-based auth via zego-token edge function
          userID: widget.userID,
          userName: widget.userName,
          callID: finalRoomID,
          events: ZegoUIKitPrebuiltCallEvents(
            onCallEnd: (ZegoCallEndEvent event, VoidCallback defaultAction) {
              // ✅ CORRECT ORDER:
              // 1. Capture duration BEFORE defaultAction tears down state
              // 2. Show rating sheet FIRST
              // 3. defaultAction runs INSIDE the sheet after user submits
              //
              // ❌ WRONG (causes auto-cut):
              //   defaultAction();
              //   if (mounted) _showRatingSheet(...);
              final int duration = _callDurationSeconds;
              _showRatingSheet(duration, defaultAction);
            },
          ),
          config: ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
            ..audioVideoView.useVideoViewAspectFill = true
            ..audioVideoView.showAvatarInAudioMode = true
            ..audioVideoView.showUserNameOnView = false
            ..turnOnCameraWhenJoining = true
            ..topMenuBar = ZegoCallTopMenuBarConfig(
              title: "Consultation: ${widget.professionalName}",
              isVisible: true,
              buttons: const [ZegoCallMenuBarButtonName.switchCameraButton],
            )
            ..bottomMenuBar = ZegoCallBottomMenuBarConfig(
              buttons: const [
                ZegoCallMenuBarButtonName.toggleMicrophoneButton,
                ZegoCallMenuBarButtonName.hangUpButton,
                ZegoCallMenuBarButtonName.toggleCameraButton,
                ZegoCallMenuBarButtonName.switchAudioOutputButton,
              ],
            )
            ..layout = ZegoLayout.pictureInPicture(
              isSmallViewDraggable: true,
            ),
        ),
      ),
    );
  }
}