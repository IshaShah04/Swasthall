import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Ensure these imports match your actual file structure
import 'call_landing_page.dart';
import 'supabase_handler.dart';
import 'services/voice_service.dart';

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

  StreamSubscription? _callSubscription;
  StreamSubscription? _queueSubscription;

  bool _isIncomingCall = false;
  String _callerRoleLabel = "Medical Staff";
  int _currentlyServing = 0;
  int? _lastNotifiedNumber;

  final VoiceService _voiceService = VoiceService();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

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
    _setupCallListener();
    _setupQueueListener();
  }

  Future<void> _initNotifications() async {
    // Local notifications are only supported on Mobile
    if (kIsWeb) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);

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

      final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(callChannel);
      await androidPlugin?.createNotificationChannel(queueChannel);
    }

    await _notificationsPlugin.initialize(initSettings);
  }

  Future<void> _initVoiceAndAnnounce() async {
    await _voiceService.initTts();
    _speakBookingDetails();
  }

  void _speakBookingDetails() {
    String dateStr = DateFormat('EEEE, MMMM d').format(widget.appointmentDate);
    String announcement =
        "Appointment booked with ${widget.doctorData['full_name'] ?? 'your doctor'} for $dateStr. "
        "Your queue number is ${widget.queueNumber}. "
        "We will notify you when your turn is approaching.";
    _voiceService.speakWithSavedLanguage(announcement);
  }

  // REAL-TIME QUEUE LISTENER
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
    int myNo = widget.queueNumber;
    int gap = myNo - servingNow;

    if (gap <= 5 && gap > 0 && _lastNotifiedNumber != servingNow) {
      _lastNotifiedNumber = servingNow;
      _triggerQueueNotification(servingNow, gap);
    } else if (gap == 0 && _lastNotifiedNumber != servingNow) {
      _lastNotifiedNumber = servingNow;
      _triggerQueueNotification(servingNow, 0);
    }
  }

  Future<void> _triggerQueueNotification(int servingNow, int gap) async {
    int myNo = widget.queueNumber;
    String title = gap == 0 ? "It's Your Turn!" : "Queue Update";
    String message = gap == 0
        ? "Doctor is ready for Number $myNo. Please proceed."
        : "Number $servingNow is being served. Only $gap people left before you.";

    if (!kIsWeb) {
      const androidDetails = AndroidNotificationDetails(
        'queue_alerts',
        'Queue Progress',
        importance: Importance.high,
        priority: Priority.high,
      );
      const notificationDetails = NotificationDetails(
          android: androidDetails, iOS: DarwinNotificationDetails());

      await _notificationsPlugin.show(1, title, message, notificationDetails);
    }
    
    _voiceService.speakWithSavedLanguage(message);
  }

  void _setupCallListener() {
    _callSubscription = supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('id', widget.bookingId)
        .listen((List<Map<String, dynamic>> data) {
      if (data.isNotEmpty && mounted) {
        final latestBooking = data.first;
        final String status = latestBooking['status']?.toString().toLowerCase() ?? '';
        
        if (status == 'cancelled') {
          _showSnackBar("Appointment expired or cancelled.");
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }

        bool isCalling = (status == 'consulting' || 
                          status == 'nurse_calling' || 
                          status == 'calling');

        if (isCalling && !_isIncomingCall) {
          String role = (status == 'nurse_calling') ? "NURSE" : "DOCTOR";
          _showCallNotification(role);
          setState(() {
            _isIncomingCall = true;
            _callerRoleLabel = role;
          });
        } 
        else if (_isIncomingCall && !isCalling) {
          if (!kIsWeb) _notificationsPlugin.cancel(0);
          setState(() => _isIncomingCall = false);
          _showSnackBar("Call timed out or was ended.");
        }
      }
    });
  }

  Future<void> _showCallNotification(String role) async {
    if (!kIsWeb) {
      const androidDetails = AndroidNotificationDetails(
        'medical_call_channel',
        'Urgent Consultations',
        importance: Importance.max,
        priority: Priority.high,
        fullScreenIntent: true,
      );
      await _notificationsPlugin.show(
          0,
          'Incoming Call',
          'Your $role is ready.',
          const NotificationDetails(
              android: androidDetails, iOS: DarwinNotificationDetails()));
    }
    _voiceService.speakWithSavedLanguage("Incoming call from your $role.");
  }

  void _handleAcceptCall() {
    if (!kIsWeb) _notificationsPlugin.cancelAll();
    setState(() => _isIncomingCall = false);
    final String normalizedRoomId = SupabaseHandler.getNormalizedRoomId(widget.bookingId);

    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PatientVideoCallPage(
            callID: normalizedRoomId,
            userID: supabase.auth.currentUser!.id,
            userName: supabase.auth.currentUser?.userMetadata?['full_name'] ?? "Patient",
            professionalName: widget.doctorData['full_name'] ?? "Specialist",
          ),
        ));
  }

  Future<void> _handleDeclineCall() async {
    if (!kIsWeb) await _notificationsPlugin.cancel(0);
    setState(() => _isIncomingCall = false);
    
    await supabase.from('bookings').update({'status': 'confirmed'}).eq('id', widget.bookingId);
    
    if (!mounted) return;
    _showSnackBar("Call declined.");
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    _queueSubscription?.cancel();
    super.dispose();
  }

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
                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 60),
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
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
        IconButton(
            onPressed: _speakBookingDetails,
            icon: const Icon(Icons.volume_up_rounded, color: Color(0xFF6366F1))),
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
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _queueInfo("Your No.", widget.queueNumber.toString(), const Color(0xFF6366F1)),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
              _queueInfo("Serving", _currentlyServing.toString(), Colors.orange),
            ],
          ),
          if (remaining > 0) ...[
            const Divider(height: 30),
            Text("$remaining people ahead of you",
                style: TextStyle(color: isUrgent ? Colors.red : Colors.grey[700], fontWeight: FontWeight.w600)),
          ] else if (remaining == 0) ...[
            const Divider(height: 30),
            const Text("You are next! Please be ready.",
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ]
        ],
      ),
    );
  }

  Widget _queueInfo(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildAppointmentCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
      child: Column(
        children: [
          _buildDoctorHeader(),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _infoRow(Icons.calendar_today_rounded, "Date", DateFormat('EEEE, MMM d').format(widget.appointmentDate)),
                const Divider(height: 25),
                _infoRow(Icons.access_time_rounded, "Time", widget.appointmentTime),
                const Divider(height: 25),
                _infoRow(Icons.location_on_rounded, "Type", widget.appointmentType),
                const Divider(height: 25),
                _infoRow(Icons.numbers_rounded, "ID", widget.bookingId.split('-').first.toUpperCase()),
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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          const SizedBox(width: 15),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.doctorData['full_name'] ?? "Doctor",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.doctorData['speciality'] ?? 'Specialist',
                style: const TextStyle(color: Color(0xFF6366F1), fontSize: 13)),
          ])),
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
      _largeBtn("Wait for Consultation", Icons.hourglass_top, const Color(0xFF6366F1), Colors.white,
          () => _showSnackBar("Monitoring your turn...")),
      const SizedBox(height: 12),
      _largeBtn("Return Home", Icons.home_filled, Colors.white, Colors.black87,
          () => Navigator.of(context).popUntil((route) => route.isFirst)),
    ]);
  }

  Widget _largeBtn(String label, IconData icon, Color bg, Color txt, VoidCallback tap) {
    return ElevatedButton.icon(
      onPressed: tap,
      icon: Icon(icon, color: txt, size: 20),
      label: Text(label, style: TextStyle(color: txt, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: bg == Colors.white ? BorderSide(color: Colors.grey.shade300) : BorderSide.none,
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
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              icon: const Icon(Icons.close, color: Colors.grey))
        ]);
  }

  Widget _buildIncomingCallUI() {
    return Material(
        color: const Color(0xFF0F172A),
        child: SafeArea(
            child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Column(children: [
            const Text("INCOMING CALL", style: TextStyle(color: Colors.white60, letterSpacing: 2)),
            const SizedBox(height: 30),
            const CircleAvatar(
                radius: 45,
                backgroundColor: Color(0xFF6366F1),
                child: Icon(Icons.person, size: 40, color: Colors.white)),
            const SizedBox(height: 20),
            Text(widget.doctorData['full_name'] ?? "Doctor",
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            Text("$_callerRoleLabel IS READY",
                style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _callBtn(Icons.close, "Decline", Colors.red, _handleDeclineCall),
            _callBtn(Icons.videocam, "Accept", Colors.green, _handleAcceptCall),
          ])
        ])));
  }

  Widget _callBtn(IconData icon, String label, Color col, VoidCallback tap) {
    return Column(children: [
      GestureDetector(
          onTap: tap,
          child: CircleAvatar(radius: 35, backgroundColor: col, child: Icon(icon, color: Colors.white))),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white))
    ]);
  }

  void _showSnackBar(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
}