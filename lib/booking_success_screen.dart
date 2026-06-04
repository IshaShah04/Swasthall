import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'supabase_handler.dart';
import 'services/voice_service.dart';
import 'services/queue_widget_service.dart';
import 'main.dart';
import 'widgets/app_transitions.dart';
import 'theme_colors.dart';

class BookingSuccessScreen extends StatefulWidget {
  final Map<String, dynamic> doctorData;
  final DateTime appointmentDate;
  final String appointmentTime;
  final String appointmentType;
  final String bookingId;
  final int? queueNumber;

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
  final _supabase = Supabase.instance.client;

  StreamSubscription? _queueSubscription;

  // BUG-20 FIX: Enriched doctor data fetched from DB.
  // The doctorData passed by the caller may only have id + basic fields.
  // We always re-fetch the full profile to show accurate name, specialty, avatar.
  Map<String, dynamic> _enrichedDoctor = {};
  bool _isDoctorLoading = true;

  bool _isIncomingCall = false;
  Timer? _inviteAutoExpireTimer;
  String _callerRoleLabel = "Medical Staff";
  int _currentlyServing = 0;
  int? _lastNotifiedNumber;

  final VoiceService _voiceService = VoiceService();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Prevent double navigation when Android back, app bar back, close, or
  // Return Home are tapped quickly after payment success.
  bool _isNavigatingHome = false;

  VoidCallback? _inviteListener;

  int get _safeQueueNumber => widget.queueNumber ?? 0;

  String get _effectiveDoctorName =>
      (_enrichedDoctor['full_name'] ?? widget.doctorData['full_name'] ?? 'Doctor')
          .toString();

  Future<void> _syncPatientWidgetFromCurrentState() async {
    if (kIsWeb || widget.bookingId.trim().isEmpty) return;

    await QueueWidgetService.updatePatientRealtimeWidget(
      appointmentId: widget.bookingId,
      doctorName: _effectiveDoctorName,
      originalQueueNumber: _safeQueueNumber,
      currentlyServing: _currentlyServing,
    );
  }

  @override
  void initState() {
    super.initState();

    final DateTime now = DateTime.now();
    final int diffHours = now.difference(widget.appointmentDate).inHours;

    // Expire only if appointment was MORE than 24 hours in the past
    if (diffHours > 24) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showSnackBar("This appointment record has expired.");
        unawaited(_goHome());
      });
      return;
    }

    _fetchDoctorData(); // BUG-20 FIX: always re-fetch full doctor details from DB
    _initNotifications();
    _initVoiceAndAnnounce();
    _bindIncomingInviteNotifier();
    unawaited(_syncPatientWidgetFromCurrentState());
    _setupQueueListener();
  }


  // ───────────────────────────────────────────────────────────────────────
  // DB fetch — always get fresh doctor data (BUG-20 fix)
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _fetchDoctorData() async {
    final doctorId = widget.doctorData['id']?.toString();
    if (doctorId == null || doctorId.isEmpty) {
      if (mounted) {
        setState(() { _enrichedDoctor = Map.from(widget.doctorData); _isDoctorLoading = false; });
      }
      return;
    }

    try {
      // Fetch staff row for name + speciality
      final staffRow = await _supabase
          .from('staff')
          .select('id, full_name, speciality, email, hospital_id, hospital_name')
          .eq('id', doctorId)
          .maybeSingle();

      // Fetch profile row for avatar and license
      final profileRow = await _supabase
          .from('profiles')
          .select('full_name, avatar_url, license_number, bio')
          .eq('id', doctorId)
          .maybeSingle();

      // Merge: staff fields take priority for medical details,
      // profiles for avatar and display name fallback
      final merged = <String, dynamic>{
        ...widget.doctorData,              // base (has id at minimum)
        if (staffRow != null) ...staffRow, // overwrite with DB staff data
        if (profileRow != null) ...{
          'avatar_url':     profileRow['avatar_url'],
          'bio':            profileRow['bio'],
          'license_number': profileRow['license_number'],
          // Only use profile name if staff name is missing
          if ((staffRow?['full_name'] ?? '').toString().isEmpty)
            'full_name': profileRow['full_name'],
        },
      };

      if (mounted) setState(() { _enrichedDoctor = merged; _isDoctorLoading = false; });
      unawaited(_syncPatientWidgetFromCurrentState());
    } catch (e) {
      debugPrint('BookingSuccess: doctor fetch error: $e');
      // Fallback: use whatever was passed in
      if (mounted) setState(() { _enrichedDoctor = Map.from(widget.doctorData); _isDoctorLoading = false; });
      unawaited(_syncPatientWidgetFromCurrentState());
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Incoming call binding
  // ───────────────────────────────────────────────────────────────────────

  void _bindIncomingInviteNotifier() {
    _inviteListener = () async {
      final IncomingInvite? data = incomingInvite.value;
      if (data == null) return;
      if (!mounted) return;
      // Only react to invites for THIS booking
      if (data.bookingId.trim() != widget.bookingId.trim()) return;

      setState(() {
        _isIncomingCall = true;
        _callerRoleLabel =
            data.callerName.toUpperCase().contains("NURSE") ? "NURSE" : "DOCTOR";
      });

      await _showCallNotification(_callerRoleLabel, widget.bookingId);
      if (!mounted) return;
    };

    if (_inviteListener != null) {
      incomingInvite.addListener(_inviteListener!);
    }
  }

  void _setIncomingInvite(IncomingInvite? value) {
    _inviteAutoExpireTimer?.cancel();
    incomingInvite.value = value;
    if (value != null) {
      _inviteAutoExpireTimer = Timer(const Duration(seconds: 58), () {
        incomingInvite.value = null;
      });
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Notifications
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _initNotifications() async {
    if (kIsWeb) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();

    await _notificationsPlugin.initialize(
      settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final String? payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _handleNotificationTap(payload);
        }
      },
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'medical_call_channel',
          'Urgent Consultations',
          description: 'Notifications for incoming doctor/nurse calls',
          importance: Importance.max,
          playSound: true,
        ),
      );

      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'queue_alerts',
          'Queue Progress',
          description: 'Notifications when your turn is approaching',
          importance: Importance.high,
          playSound: true,
        ),
      );
    }
  }

  Future<void> _showCallNotification(String role, String bookingId) async {
    if (kIsWeb) return;

    await _notificationsPlugin.show(
      id: 0,
      title: 'Incoming Call',
      body: 'Your $role is ready.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'medical_call_channel',
          'Urgent Consultations',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: bookingId,
    );

    _voiceService.speakWithSavedLanguage("Incoming call from your $role.");
  }

  Future<void> _triggerQueueNotification(int servingNow, int gap) async {
    final int myNo = _safeQueueNumber;
    final String title = gap == 0 ? "It's Your Turn!" : "Queue Update";
    final String message = gap == 0
        ? "Doctor is ready for Number $myNo. Please proceed."
        : "Number $servingNow is being served. Only $gap people left before you.";

    if (!kIsWeb) {
      await _notificationsPlugin.show(
        id: 1,
        title: title,
        body: message,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'queue_alerts',
            'Queue Progress',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    }

    _voiceService.speakWithSavedLanguage(message);
  }

  Future<void> _handleNotificationTap(String bookingId) async {
    await _handleAcceptCall();
  }

  // ───────────────────────────────────────────────────────────────────────
  // Call accept / decline
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _handleAcceptCall() async {
    await _notificationsPlugin.cancelAll();
    if (!mounted) return;

    // Guard: timer already cleared the invite (60s expired)
    if (incomingInvite.value == null) {
      _showSnackBar('Call expired. Please ask the doctor to call again.');
      return;
    }

    setState(() => _isIncomingCall = false);

    try {
      await SupabaseHandler().setConsulting(widget.bookingId);
    } catch (_) {}

    // CRITICAL: Wait 500ms before calling accept().
    // ZEGO's page manager needs time to register the call page (inCallPage:true)
    // after the invitation arrives. Calling accept() too quickly causes
    // "restore to idle, inCallPage:false" → room killed immediately.
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    // Re-check: invitation may have expired during the delay
    if (incomingInvite.value == null) {
      _showSnackBar('Call expired. Please ask the doctor to call again.');
      return;
    }

    try {
      await ZegoUIKitPrebuiltCallInvitationService().accept();
      _setIncomingInvite(null);
    } catch (e) {
      debugPrint('ZEGO accept error: $e');
      _showSnackBar('Could not connect. Please ask the doctor to call again.');
    }
  }

  Future<void> _handleDeclineCall() async {
    await _notificationsPlugin.cancel(id: 0);
    if (!mounted) return;

    setState(() => _isIncomingCall = false);
    _setIncomingInvite(null);

    try {
      await ZegoUIKitPrebuiltCallInvitationService().reject();
    } catch (_) {}

    if (!mounted) return;
    _showSnackBar('Call declined.');
  }

  // ───────────────────────────────────────────────────────────────────────
  // Queue listener
  // ───────────────────────────────────────────────────────────────────────

  void _setupQueueListener() {
    final staffId = _enrichedDoctor['id'] ?? widget.doctorData['id'];
    if (staffId == null) return;

    try {
      _queueSubscription = _supabase
          .from('staff_queues')
          .stream(primaryKey: ['staff_id'])
          .eq('staff_id', staffId)
          .listen(
        (List<Map<String, dynamic>> data) {
          if (data.isNotEmpty && mounted) {
            final int servingNow =
                int.tryParse(data.first['currently_serving']?.toString() ?? '0') ?? 0;
            setState(() => _currentlyServing = servingNow);
            _processQueueLogic(servingNow);
            unawaited(_syncPatientWidgetFromCurrentState());
          }
        },
        onError: (Object e) {
          // RLS may block this query — screen still works without live queue
          debugPrint('Queue listener error: $e');
        },
      );
    } catch (e) {
      debugPrint('Queue stream setup error: $e');
    }
  }

  void _processQueueLogic(int servingNow) {
    final int myNo = _safeQueueNumber;
    final int gap = myNo - servingNow;

    if (gap <= 5 && gap > 0 && _lastNotifiedNumber != servingNow) {
      _lastNotifiedNumber = servingNow;
      _triggerQueueNotification(servingNow, gap);
    } else if (gap == 0 && _lastNotifiedNumber != servingNow) {
      _lastNotifiedNumber = servingNow;
      _triggerQueueNotification(servingNow, 0);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Voice
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _initVoiceAndAnnounce() async {
    await _voiceService.initTts();
    _speakBookingDetails();
  }

  void _speakBookingDetails() {
    final String dateStr =
        DateFormat('EEEE, MMMM d').format(widget.appointmentDate);
    final String announcement =
        "Appointment booked with ${_enrichedDoctor['full_name'] ?? widget.doctorData['full_name'] ?? 'your doctor'} "
        "for $dateStr. Your queue number is $_safeQueueNumber. "
        "We will notify you when your turn is approaching.";
    _voiceService.speakWithSavedLanguage(announcement);
  }

  // ───────────────────────────────────────────────────────────────────────
  // Navigation
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _goHome() async {
    if (_isNavigatingHome) return;
    _isNavigatingHome = true;

    try {
      _inviteAutoExpireTimer?.cancel();
      incomingInvite.value = null;
      if (!kIsWeb) {
        await _notificationsPlugin.cancelAll();
      }
    } catch (_) {}

    if (!mounted) return;

    // IMPORTANT FIX:
    // After payment, BookingSuccessScreen can become the first/root route
    // because payment screens often use pushReplacement/pushAndRemoveUntil.
    // In that case pop() and popUntil(route.isFirst) do nothing, so the user
    // feels trapped. Push AuthGate as a clean root; AuthGate detects the
    // active session and lands the user on the correct home/dashboard.
    final NavigatorState nav = navigatorKey.currentState ??
        Navigator.of(context, rootNavigator: true);

    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (Route<dynamic> route) => false,
    );
  }

  void _goBack() {
    // On a success screen, back should never return to payment/webview.
    // It should go to the logged-in home/dashboard.
    unawaited(_goHome());
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    if (_inviteListener != null) {
      incomingInvite.removeListener(_inviteListener!);
    }
    _inviteAutoExpireTimer?.cancel();
    _queueSubscription?.cancel();
    _voiceService.stop();
    if (!kIsWeb) {
      _notificationsPlugin.cancelAll();
    }
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          unawaited(_goHome());
        }
      },
      child: Stack(
        children: [
        Scaffold(
          backgroundColor: AppColors.scaffoldBg(context),
          appBar: _buildAppBar(),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 10),
                const AnimatedCheckmark(size: 80),
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
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        onPressed: _goBack,
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textMuted(context)),
      ),
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          onPressed: () => unawaited(_goHome()),
          icon: Icon(Icons.close, color: AppColors.textMuted(context)),
        ),
      ],
    );
  }

  Widget _buildTitleRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Booked Successfully!",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1E293B),
          ),
        ),
        IconButton(
          onPressed: _speakBookingDetails,
          icon: const Icon(Icons.volume_up_rounded, color: Color(0xFF6366F1)),
        ),
      ],
    );
  }

  Widget _buildLiveQueueCard() {
    final int remaining = _safeQueueNumber - _currentlyServing;
    final bool isUrgent = remaining <= 5 && remaining > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isUrgent ? AppColors.redTint(context) : AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            "LIVE QUEUE STATUS",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textMuted(context),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _queueInfo("Your No.", _safeQueueNumber.toString(), const Color(0xFF6366F1)),
              Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted(context), size: 16),
              _queueInfo("Serving", _currentlyServing.toString(), Colors.orange),
            ],
          ),
          if (remaining > 0) ...[
            const Divider(height: 30),
            Text(
              "$remaining people ahead of you",
              style: TextStyle(
                color: isUrgent ? Colors.red : Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else if (remaining == 0) ...[
            const Divider(height: 30),
            const Text(
              "You are next! Please be ready.",
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }

  Widget _queueInfo(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textMuted(context))),
        Text(
          value,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildAppointmentCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        children: [
          _buildDoctorHeader(),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _infoRow(
                  Icons.calendar_today_rounded,
                  "Date",
                  DateFormat('EEEE, MMM d').format(widget.appointmentDate),
                ),
                const Divider(height: 25),
                _infoRow(Icons.access_time_rounded, "Time", widget.appointmentTime),
                const Divider(height: 25),
                _infoRow(Icons.location_on_rounded, "Type", widget.appointmentType),
                const Divider(height: 25),
                _infoRow(
                  Icons.numbers_rounded,
                  "ID",
                  widget.bookingId.split('-').first.toUpperCase(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorHeader() {
    if (_isDoctorLoading) {
      return Container(
        height: 90,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withValues(alpha: 0.05),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1))),
      );
    }
    final String doctorName = _enrichedDoctor['full_name'] ?? widget.doctorData['full_name'] ?? 'Doctor';
    final String speciality = _enrichedDoctor['speciality'] ?? widget.doctorData['speciality'] ?? 'Specialist';
    final String? avatarUrl = _enrichedDoctor['avatar_url']?.toString();
    final String initial = doctorName.isNotEmpty ? doctorName[0].toUpperCase() : 'D';

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
            backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? NetworkImage(avatarUrl) : null,
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                : null,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doctorName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  speciality,
                  style: const TextStyle(color: Color(0xFF6366F1), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textMuted(context)),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: AppColors.textMuted(context), fontSize: 14)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        _largeBtn(
          "Wait for Consultation",
          Icons.hourglass_top,
          const Color(0xFF6366F1),
          Colors.white,
          () => _showSnackBar("Monitoring your turn..."),
        ),
        const SizedBox(height: 12),
        _largeBtn(
          "Return Home",
          Icons.home_filled,
          Colors.white,
          Colors.black87,
          () => unawaited(_goHome()),
        ),
      ],
    );
  }

  Widget _largeBtn(
    String label,
    IconData icon,
    Color bg,
    Color txt,
    VoidCallback tap,
  ) {
    return ElevatedButton.icon(
      onPressed: () {
        hapticMedium();
        tap();
      },
      icon: Icon(icon, color: txt, size: 20),
      label: Text(label, style: TextStyle(color: txt, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: bg == Colors.white
              ? BorderSide(color: const Color(0xFFCBD5E1))
              : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildIncomingCallUI() {
    return Material(
      color: AppColors.textPrimary(context),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                const Text(
                  "INCOMING CALL",
                  style: TextStyle(color: Colors.white60, letterSpacing: 2),
                ),
                const SizedBox(height: 30),
                CircleAvatar(
                  radius: 45,
                  backgroundColor: const Color(0xFF6366F1),
                  child: const Icon(Icons.person, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 20),
                Text(
                  _enrichedDoctor['full_name'] ?? widget.doctorData['full_name'] ?? 'Doctor',
                  style: TextStyle(
                    color: AppColors.cardBg(context),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "$_callerRoleLabel IS READY",
                  style: const TextStyle(
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _callBtn(Icons.close, "Decline", Colors.red, _handleDeclineCall),
                _callBtn(Icons.videocam, "Accept", Colors.green, _handleAcceptCall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _callBtn(IconData icon, String label, Color col, VoidCallback tap) {
    return Column(
      children: [
        GestureDetector(
          onTap: tap,
          child: CircleAvatar(
            radius: 35,
            backgroundColor: col,
            child: Icon(icon, color: AppColors.cardBg(context)),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: AppColors.cardBg(context))),
      ],
    );
  }
}