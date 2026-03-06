import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

import 'call_landing_page.dart';
import 'supabase_handler.dart';
import 'services/voice_service.dart';

// ✅ listen to global notifier declared in main.dart
import 'main.dart';

class BookingSuccessScreen extends StatefulWidget {
  final Map<String, dynamic> doctorData;
  final DateTime appointmentDate;
  final String appointmentTime;
  final String appointmentType;
  final String bookingId;
  final int queueNumber;

  const BookingSuccessScreen({
    super.key,
    required this.doctorData,
    required this.appointmentDate,
    required this.appointmentTime,
    required this.appointmentType,
    required this.bookingId,
    required this.queueNumber,
  });

  @override
  State<BookingSuccessScreen> createState() => _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends State<BookingSuccessScreen> {
  final supabase = Supabase.instance.client;

  StreamSubscription? _queueSubscription;

  bool _isIncomingCall = false;
  String _callerRoleLabel = "Medical Staff";
  int _currentlyServing = 0;
  int? _lastNotifiedNumber;

  final VoiceService _voiceService = VoiceService();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// callID received from invite (room id)
  String? _incomingRoomId;

  /// ✅ cache patient zego uid here
  String? _myZegoUid;

  /// ✅ listener handle for incomingInvite notifier
  late final VoidCallback _inviteListener;

  @override
  void initState() {
    super.initState();

    // SAFETY GATE: Prevent old appointments (older than 24h) from showing calls
    final now = DateTime.now();
    final difference = now.difference(widget.appointmentDate).inHours;

    if (difference > 24) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showSnackBar("This appointment record has expired.");
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return;
    }

    _initNotifications();
    _initVoiceAndAnnounce();

    // ✅ load zego uid once (so we can use it when accepting/tapping notification)
    _loadMyZegoUid();

    // ✅ Listen to Zego invite events coming from AuthGate init(invitationEvents)
    _bindIncomingInviteNotifier();

    // Queue is still Supabase-driven (unchanged)
    _setupQueueListener();
  }

  Future<void> _loadMyZegoUid() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // If already set in user metadata (optional), use it
    final metaUid = user.userMetadata?['zego_uid']?.toString().trim();
    if (metaUid != null && metaUid.isNotEmpty) {
      _myZegoUid = metaUid;
      return;
    }

    try {
      final data = await supabase
          .from('profiles')
          .select('zego_uid')
          .eq('id', user.id)
          .maybeSingle();

      final z = data?['zego_uid']?.toString().trim();
      if (z != null && z.isNotEmpty) {
        _myZegoUid = z;
      } else {
        // fallback (should not happen if you applied SQL trigger)
        _myZegoUid = user.id; // last resort
      }
    } catch (_) {
      _myZegoUid = user.id; // last resort
    }
  }

  void _bindIncomingInviteNotifier() {
    _inviteListener = () async {
      final data = incomingInvite.value;
      if (data == null) return;
      if (!mounted) return;

      // Only show on the correct BookingSuccessScreen
      if (data.bookingId.trim() != widget.bookingId.trim()) return;

      setState(() {
        _incomingRoomId = data.callID.trim();
        _isIncomingCall = true;
        _callerRoleLabel =
            data.callerName.toUpperCase().contains("NURSE") ? "NURSE" : "DOCTOR";
      });

      await _showCallNotification(_callerRoleLabel, widget.bookingId);
    };

    incomingInvite.addListener(_inviteListener);
  }

  Future<void> _handleNotificationTap(String bookingId) async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  // ensure we have zego uid
  if (_myZegoUid == null || _myZegoUid!.isEmpty) {
    await _loadMyZegoUid();
    if (!mounted) return;
  }

  // ✅ join the SAME room as inviter if we already received an invite
  final String roomId =
      (_incomingRoomId != null && _incomingRoomId!.trim().isNotEmpty)
          ? _incomingRoomId!.trim()
          : SupabaseHandler.getNormalizedRoomId(bookingId);

  if (!mounted) return;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => PatientVideoCallPage(
        callID: roomId,
        userID: (_myZegoUid ?? user.id).trim(),
        userName: user.userMetadata?['full_name'] ?? "Patient",
        professionalName: widget.doctorData['full_name'] ?? "Specialist",
      ),
    ),
  );
}

  Future<void> _initNotifications() async {
    if (kIsWeb) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // ✅ FIX: new versions require named parameter `settings:`
    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _handleNotificationTap(payload);
        }
      },
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
        'medical_call_channel',
        'Urgent Consultations',
        description: 'Notifications for incoming doctor/nurse calls',
        importance: Importance.max,
        playSound: true,
      );

      const AndroidNotificationChannel queueChannel = AndroidNotificationChannel(
        'queue_alerts',
        'Queue Progress',
        description: 'Notifications when your turn is approaching',
        importance: Importance.high,
        playSound: true,
      );

      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.createNotificationChannel(callChannel);
      await androidPlugin?.createNotificationChannel(queueChannel);
    }
  }

  Future<void> _initVoiceAndAnnounce() async {
    await _voiceService.initTts();
    _speakBookingDetails();
  }

  void _speakBookingDetails() {
    final String dateStr =
        DateFormat('EEEE, MMMM d').format(widget.appointmentDate);

    final String announcement =
        "Appointment booked with ${widget.doctorData['full_name'] ?? 'your doctor'} for $dateStr. "
        "Your queue number is ${widget.queueNumber}. "
        "We will notify you when your turn is approaching.";

    _voiceService.speakWithSavedLanguage(announcement);
  }

  // REAL-TIME QUEUE LISTENER (UNCHANGED)
  void _setupQueueListener() {
    final staffId = widget.doctorData['id'];
    if (staffId == null) return;

    _queueSubscription = supabase
        .from('staff_queues')
        .stream(primaryKey: ['staff_id'])
        .eq('staff_id', staffId)
        .listen((data) {
      if (data.isNotEmpty && mounted) {
        final int servingNow = data.first['currently_serving'] ?? 0;
        setState(() => _currentlyServing = servingNow);
        _processQueueLogic(servingNow);
      }
    });
  }

  void _processQueueLogic(int servingNow) {
    final int myNo = widget.queueNumber;
    final int gap = myNo - servingNow;

    if (gap <= 5 && gap > 0 && _lastNotifiedNumber != servingNow) {
      _lastNotifiedNumber = servingNow;
      _triggerQueueNotification(servingNow, gap);
    } else if (gap == 0 && _lastNotifiedNumber != servingNow) {
      _lastNotifiedNumber = servingNow;
      _triggerQueueNotification(servingNow, 0);
    }
  }

  Future<void> _triggerQueueNotification(int servingNow, int gap) async {
    final int myNo = widget.queueNumber;
    final String title = gap == 0 ? "It's Your Turn!" : "Queue Update";
    final String message = gap == 0
        ? "Doctor is ready for Number $myNo. Please proceed."
        : "Number $servingNow is being served. Only $gap people left before you.";

    if (!kIsWeb) {
      const androidDetails = AndroidNotificationDetails(
        'queue_alerts',
        'Queue Progress',
        importance: Importance.high,
        priority: Priority.high,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      );

      await _safeNotifShow(
        id: 1,
        title: title,
        body: message,
        details: details,
      );
    }

    _voiceService.speakWithSavedLanguage(message);
  }

  /// ✅ SAFE wrappers for flutter_local_notifications across versions
  Future<void> _safeNotifShow({
    required int id,
    required String title,
    required String body,
    required NotificationDetails details,
    String? payload,
  }) async {
    if (kIsWeb) return;

    try {
      // ignore: avoid_dynamic_calls
      await (_notificationsPlugin as dynamic).show(
        id,
        title,
        body,
        details,
        payload: payload,
      );
      return;
    } catch (_) {}

    try {
      // ignore: avoid_dynamic_calls
      await (_notificationsPlugin as dynamic).show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
      return;
    } catch (_) {}
  }

  Future<void> _safeNotifCancel(int id) async {
    if (kIsWeb) return;

    try {
      // ignore: avoid_dynamic_calls
      await (_notificationsPlugin as dynamic).cancel(id);
      return;
    } catch (_) {}

    try {
      // ignore: avoid_dynamic_calls
      await (_notificationsPlugin as dynamic).cancel(id: id);
      return;
    } catch (_) {}
  }

  Future<void> _safeNotifCancelAll() async {
    if (kIsWeb) return;
    try {
      await _notificationsPlugin.cancelAll();
    } catch (_) {}
  }

  Future<void> _showCallNotification(String role, String bookingId) async {
    if (kIsWeb) return;

    const androidDetails = AndroidNotificationDetails(
      'medical_call_channel',
      'Urgent Consultations',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _safeNotifShow(
      id: 0,
      title: 'Incoming Call',
      body: 'Your $role is ready.',
      details: details,
      payload: bookingId,
    );

    _voiceService.speakWithSavedLanguage("Incoming call from your $role.");
  }

  Future<void> _handleAcceptCall() async {
  await _safeNotifCancelAll();
  if (!mounted) return;

  setState(() => _isIncomingCall = false);

  final user = supabase.auth.currentUser;
  if (user == null) return;

  if (_myZegoUid == null || _myZegoUid!.isEmpty) {
    await _loadMyZegoUid();
    if (!mounted) return;
  }

  // ✅ ALWAYS join SAME room as professional used in invite
  final String roomId =
      (_incomingRoomId != null && _incomingRoomId!.trim().isNotEmpty)
          ? _incomingRoomId!.trim()
          : SupabaseHandler.getNormalizedRoomId(widget.bookingId);

  if (!mounted) return;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => PatientVideoCallPage(
        callID: roomId,
        userID: (_myZegoUid ?? user.id).trim(),
        userName: user.userMetadata?['full_name'] ?? "Patient",
        professionalName: widget.doctorData['full_name'] ?? "Specialist",
      ),
    ),
  );
}

  Future<void> _handleDeclineCall() async {
    await _safeNotifCancel(0);
    setState(() => _isIncomingCall = false);

    try {
      // ignore: avoid_dynamic_calls
      await (ZegoUIKitPrebuiltCallInvitationService() as dynamic).reject();
    } catch (_) {
      try {
        // ignore: avoid_dynamic_calls
        await (ZegoUIKitPrebuiltCallInvitationService() as dynamic).decline();
      } catch (_) {}
    }

    _incomingRoomId = null;
    incomingInvite.value = null;

    if (!mounted) return;
    _showSnackBar("Call declined.");
  }

  @override
  void dispose() {
    incomingInvite.removeListener(_inviteListener);
    _queueSubscription?.cancel();
    super.dispose();
  }

  // ---------------- UI (UNCHANGED) ----------------

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          appBar: _buildAppBar(),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF10B981), size: 60),
                const SizedBox(height: 10),
                _buildTitleRow(),
                const SizedBox(height: 20),
                _buildLiveQueueCard(),
                _buildAppointmentCard(),
                const SizedBox(height: 24),
                _buildActionButtons(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
        if (_isIncomingCall) _buildIncomingCallUI(),
      ],
    );
  }

  Widget _buildTitleRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Booked Successfully!",
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E293B))),
        IconButton(
          onPressed: _speakBookingDetails,
          icon: const Icon(Icons.volume_up_rounded, color: Color(0xFF6366F1)),
        ),
      ],
    );
  }

  Widget _buildLiveQueueCard() {
    int remaining = widget.queueNumber - _currentlyServing;
    bool isUrgent = remaining <= 5 && remaining > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isUrgent ? const Color(0xFFFFF1F2) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        children: [
          const Text("LIVE QUEUE STATUS",
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1.2)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _queueInfo("Your No.", widget.queueNumber.toString(),
                  const Color(0xFF6366F1)),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.grey, size: 16),
              _queueInfo("Serving", _currentlyServing.toString(), Colors.orange),
            ],
          ),
          if (remaining > 0) ...[
            const Divider(height: 30),
            Text("$remaining people ahead of you",
                style: TextStyle(
                    color: isUrgent ? Colors.red : Colors.grey[700],
                    fontWeight: FontWeight.w600)),
          ] else if (remaining == 0) ...[
            const Divider(height: 30),
            const Text("You are next! Please be ready.",
                style: TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold)),
          ]
        ],
      ),
    );
  }

  Widget _queueInfo(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value,
            style: TextStyle(
                fontSize: 32, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildAppointmentCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(30)),
      child: Column(
        children: [
          _buildDoctorHeader(),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _infoRow(Icons.calendar_today_rounded, "Date",
                    DateFormat('EEEE, MMM d').format(widget.appointmentDate)),
                const Divider(height: 25),
                _infoRow(Icons.access_time_rounded, "Time", widget.appointmentTime),
                const Divider(height: 25),
                _infoRow(Icons.location_on_rounded, "Type", widget.appointmentType),
                const Divider(height: 25),
                _infoRow(Icons.numbers_rounded, "ID",
                    widget.bookingId.split('-').first.toUpperCase()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.05),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Row(
        children: [
          CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFF6366F1),
              child: Text(widget.doctorData['full_name']?[0] ?? "D",
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold))),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.doctorData['full_name'] ?? "Doctor",
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                Text(widget.doctorData['speciality'] ?? 'Specialist',
                    style: const TextStyle(
                        color: Color(0xFF6366F1), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 18, color: Colors.grey),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
      const Spacer(),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildActionButtons() {
    return Column(children: [
      _largeBtn("Wait for Consultation", Icons.hourglass_top,
          const Color(0xFF6366F1), Colors.white,
          () => _showSnackBar("Monitoring your turn...")),
      const SizedBox(height: 12),
      _largeBtn("Return Home", Icons.home_filled, Colors.white, Colors.black87,
          () => Navigator.of(context).popUntil((route) => route.isFirst)),
    ]);
  }

  Widget _largeBtn(
      String label, IconData icon, Color bg, Color txt, VoidCallback tap) {
    return ElevatedButton.icon(
      onPressed: tap,
      icon: Icon(icon, color: txt, size: 20),
      label: Text(label,
          style: TextStyle(color: txt, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: bg == Colors.white
              ? BorderSide(color: Colors.grey.shade300)
              : BorderSide.none,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          icon: const Icon(Icons.close, color: Colors.grey),
        )
      ],
    );
  }

  Widget _buildIncomingCallUI() {
    return Material(
      color: const Color(0xFF0F172A),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(children: [
              const Text("INCOMING CALL",
                  style: TextStyle(color: Colors.white60, letterSpacing: 2)),
              const SizedBox(height: 30),
              const CircleAvatar(
                  radius: 45,
                  backgroundColor: Color(0xFF6366F1),
                  child: Icon(Icons.person, size: 40, color: Colors.white)),
              const SizedBox(height: 20),
              Text(widget.doctorData['full_name'] ?? "Doctor",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              Text("$_callerRoleLabel IS READY",
                  style: const TextStyle(
                      color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _callBtn(Icons.close, "Decline", Colors.red, _handleDeclineCall),
              _callBtn(Icons.videocam, "Accept", Colors.green, () {
                _handleAcceptCall();
              }),
            ])
          ],
        ),
      ),
    );
  }

  Widget _callBtn(IconData icon, String label, Color col, VoidCallback tap) {
    return Column(children: [
      GestureDetector(
        onTap: tap,
        child: CircleAvatar(
            radius: 35,
            backgroundColor: col,
            child: Icon(icon, color: Colors.white)),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white))
    ]);
  }

  void _showSnackBar(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
}