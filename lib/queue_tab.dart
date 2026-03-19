import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'supabase_handler.dart';
import 'main.dart';
import 'services/realtime_call_service.dart';
import 'services/queue_widget_service.dart';
import 'video_call_page.dart';
import 'shared_widgets.dart';

class QueueTab extends StatefulWidget {
  final String userRole;
  final TabController? tabController;
  final String selectedFilter;
  final String? filterId; // For nurses: assigned doctor ID

  const QueueTab({
    super.key,
    required this.userRole,
    this.tabController,
    required this.selectedFilter,
    this.filterId,
  });

  @override
  State<QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends State<QueueTab> with AutomaticKeepAliveClientMixin {
  final _supabase = SupabaseHandler().client;
  static const Color _brandIndigo = Color(0xFF6366F1);
  static const Color _nurseTeal = Color(0xFF0D9488);
  static const Color _labAmber = Color(0xFFD97706);

  Stream<List<Map<String, dynamic>>>? _bookingsStream;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  String? _myZegoUid;
  bool _loadingZegoUid = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMyZegoUid();
    _initBookingsStream();
  }

  @override
  void didUpdateWidget(covariant QueueTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterId != widget.filterId) {
      setState(() => _initBookingsStream());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────
  // Role helpers
  // ───────────────────────────────────────────────────────────────────────

  bool _isNurse() => widget.userRole.toLowerCase() == "nurse";
  bool _isTechnician() => widget.userRole.toLowerCase() == "technician";

  // ───────────────────────────────────────────────────────────────────────
  // Stream
  // ───────────────────────────────────────────────────────────────────────

  void _initBookingsStream() {
    if (widget.filterId != null) {
      if (_isTechnician()) {
        _bookingsStream = _supabase
            .from('bookings')
            .stream(primaryKey: ['id'])
            .eq('lab_category', widget.filterId!)
            .order('id', ascending: true);
      } else {
        _bookingsStream = _supabase
            .from('bookings')
            .stream(primaryKey: ['id'])
            .eq('provider_id', widget.filterId!)
            .order('id', ascending: true);
      }
    } else {
      _bookingsStream = _supabase
          .from('bookings')
          .stream(primaryKey: ['id'])
          .order('id', ascending: true);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Load professional's own Zego UID
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _loadMyZegoUid() async {
    if (_loadingZegoUid) return;
    _loadingZegoUid = true;

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _loadingZegoUid = false;
      return;
    }

    // 1. Try user metadata first (fastest)
    final String? metaUid = user.userMetadata?['zego_uid']?.toString().trim();
    if (metaUid != null && metaUid.isNotEmpty) {
      if (mounted) setState(() => _myZegoUid = metaUid);
      _loadingZegoUid = false;
      return;
    }

    // 2. Fall back to profiles table (staff reading their own row is always allowed)
    try {
      final data = await _supabase
          .from('profiles')
          .select('zego_uid')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      final String z = (data?['zego_uid'] ?? '').toString().trim();
      setState(() => _myZegoUid = z.isNotEmpty ? z : null);
    } catch (_) {
      if (mounted) setState(() => _myZegoUid = null);
    } finally {
      _loadingZegoUid = false;
    }
  }

  Future<String?> _readProfileZegoUid(String profileId) async {
    try {
      final data = await _supabase
          .from('profiles')
          .select('zego_uid')
          .eq('id', profileId)
          .maybeSingle();

      final String z = (data?['zego_uid'] ?? '').toString().trim();
      return z.isEmpty ? null : z;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistCallIdentityToBooking({
    required String bookingId,
    required String roomId,
    String? patientZegoUid,
    String? providerZegoUid,
  }) async {
    final Map<String, dynamic> patch = {};

    if (roomId.trim().isNotEmpty) {
      patch['room_id'] = roomId.trim();
    }
    if ((patientZegoUid ?? '').trim().isNotEmpty) {
      patch['patient_zego_uid'] = patientZegoUid!.trim();
    }
    if ((providerZegoUid ?? '').trim().isNotEmpty) {
      patch['provider_zego_uid'] = providerZegoUid!.trim();
    }

    if (patch.isEmpty) return;

    try {
      await _supabase.from('bookings').update(patch).eq('id', bookingId);
    } catch (_) {
      // Non-blocking best effort patch for legacy bookings.
    }
  }

  String _buildRoomId(Map<String, dynamic> booking) {
    return SupabaseHandler.getNormalizedRoomId(booking['room_id']?.toString() ?? '');
  }

  // ───────────────────────────────────────────────────────────────────────
  // Status update
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _updateStatus(
    String id,
    String status, {
    bool nurseSeen = false,
  }) async {
    try {
      final Map<String, dynamic> update = {'status': status.toLowerCase()};
      if (nurseSeen) update['nurse_seen'] = true;
      await _supabase.from('bookings').update(update).eq('id', id);
    } catch (e) {
      _showError("Action failed: $e");
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Start call
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _startCall(
    Map<String, dynamic> appt,
    String userId,
    bool asNurse,
  ) async {
    final String rawBookingId = appt['id'].toString();

    final String patientAuthUid =
        (appt['patient_id'] ?? appt['user_id'] ?? '').toString().trim();

    if (patientAuthUid.isEmpty) {
      _showError("Booking missing patient ID. Cannot place call.");
      return;
    }

    final String patientName =
        (appt['patient_name'] ?? appt['full_name'] ?? "Patient").toString();

    final String providerZegoUid =
        ((appt['provider_zego_uid'] ?? _myZegoUid) ?? '').toString().trim();

    final String resolvedProviderZegoUid = providerZegoUid.isNotEmpty
        ? providerZegoUid
        : ((await _readProfileZegoUid(
                _supabase.auth.currentUser?.id.toString() ?? '',
              )) ??
            '');

    if (resolvedProviderZegoUid.isEmpty) {
      _showError("Your profiles.zego_uid is missing. Cannot place call.");
      return;
    }

    String patientZegoUid =
        (appt['patient_zego_uid'] ?? '').toString().trim();

    if (patientZegoUid.isEmpty) {
      patientZegoUid = (await _readProfileZegoUid(patientAuthUid) ?? '').trim();
    }

    if (patientZegoUid.isEmpty) {
      await _updateStatus(rawBookingId, 'confirmed');
      _showError("Cannot reach patient — patient profiles.zego_uid is missing.");
      return;
    }

    final String normalizedRoomId = _buildRoomId(appt);

    if (normalizedRoomId.isEmpty) {
      await _updateStatus(rawBookingId, 'confirmed');
      _showError("Booking missing room_id. Please refresh and try again.");
      return;
    }

    await _persistCallIdentityToBooking(
      bookingId: rawBookingId,
      roomId: normalizedRoomId,
      patientZegoUid: patientZegoUid,
      providerZegoUid: resolvedProviderZegoUid,
    );

    // ── Set ringing status ────────────────────────────────────────────────
    final String ringingStatus = asNurse ? 'nurse_calling' : 'calling';
    await _updateStatus(rawBookingId, ringingStatus, nurseSeen: asNurse);
    if (!mounted) return;

    // ── Update nurse home screen widget when nurse starts pre-consultation ─
    if (asNurse && !kIsWeb) {
      QueueWidgetService.updateNurseWidget(
        taskId:      rawBookingId,
        taskType:    'Pre-consultation',
        patientName: patientName,
      );
    }

    // ── WEB: use Supabase Realtime signalling ─────────────────────────────
    if (kIsWeb) {
      final me = _supabase.auth.currentUser;
      if (me == null) {
        await _updateStatus(rawBookingId, 'confirmed');
        _showError("Not logged in.");
        return;
      }

      final myName = me.userMetadata?['full_name']?.toString() ?? 'Doctor';

      final result = await RealtimeCallService().initiateCall(
        callId: normalizedRoomId,
        callerId: me.id,
        callerName: myName,
        calleeId: patientAuthUid,
        bookingId: rawBookingId,
      );

      if (result == null) {
        await _updateStatus(rawBookingId, 'confirmed');
        _showError("Could not signal patient. Try again.");
        return;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Calling $patientName..."),
          duration: const Duration(seconds: 2),
          backgroundColor: _brandIndigo,
        ),
      );

      activeCallBookingId = rawBookingId;
      activeCallIsNurse = asNurse;

      // Navigate caller (doctor/nurse on web) directly into the Zego room
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoCallPage(
            callID: normalizedRoomId,
            userID: resolvedProviderZegoUid,
            userName: myName,
            patientID: patientAuthUid,
            patientName: patientName,
            professionalRole: asNurse ? 'nurse' : 'doctor',
            appointmentData: appt,
            bookingId: rawBookingId,
          ),
        ),
      );
      return;
    }

    // ── MOBILE: existing Zego invitation path ─────────────────────────────
    activeCallBookingId = rawBookingId;
    activeCallIsNurse = asNurse;

    try {
      await ZegoUIKitPrebuiltCallInvitationService().send(
        invitees: [ZegoCallUser(patientZegoUid, patientName)],
        isVideoCall: true,
        callID: normalizedRoomId,
        customData: rawBookingId,
        resourceID: "swasthall_push",
      );
    } catch (e) {
      activeCallBookingId = null;
      activeCallIsNurse = false;
      await _updateStatus(rawBookingId, 'confirmed');
      _showError("Call failed: $e");
      return;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Calling $patientName..."),
        duration: const Duration(seconds: 2),
        backgroundColor: _brandIndigo,
      ),
    );

    // ZEGO opens the doctor's call UI automatically via requireConfig in main.dart
  }

  // ───────────────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final String? currentUserId =
        (_myZegoUid ?? _supabase.auth.currentUser?.id)?.toString().trim();

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            key: ValueKey(widget.filterId),
            stream: _bookingsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text("Access Error: ${snapshot.error}"));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: _brandIndigo),
                );
              }

              final List<Map<String, dynamic>> data = snapshot.data ?? [];

              if (data.isEmpty) {
                if ((_isNurse() || _isTechnician()) && widget.filterId == null) {
                  return _buildEmptyState(message: "Waiting for Assignment...");
                }
                return _buildEmptyState();
              }

              final List<Map<String, dynamic>> activeBookings =
                  data.where((e) {
                final String status =
                    e['status']?.toString().toLowerCase() ?? '';
                final bool matchesStatus = _isTechnician()
                    ? [
                        'confirmed',
                        'pending_lab',
                        'collecting_sample',
                        'processing',
                        'scheduled',
                      ].contains(status)
                    : [
                        'pending',
                        'confirmed',
                        'consulting',
                        'scheduled',
                        'in_progress',
                        'nurse_calling',
                        'calling',
                      ].contains(status);

                final String patientName =
                    (e['patient_name'] ?? e['full_name'] ?? "")
                        .toString()
                        .toLowerCase();

                return matchesStatus &&
                    patientName.contains(_searchQuery.toLowerCase());
              }).toList();

              if (activeBookings.isEmpty) return _buildEmptyState();

              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: activeBookings.length,
                itemBuilder: (context, index) {
                  final Map<String, dynamic> appt = activeBookings[index];
                  final String status =
                      appt['status']?.toString().toLowerCase() ?? '';
                  final bool nurseSeen = appt['nurse_seen'] ?? false;
                  final bool isLive = _isTechnician()
                      ? status == 'processing'
                      : [
                          'consulting',
                          'in_progress',
                          'nurse_calling',
                          'calling',
                        ].contains(status);

                  return _buildQueueCard(
                    appt,
                    index,
                    isLive,
                    nurseSeen,
                    status,
                    currentUserId ?? '',
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Widgets
  // ───────────────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: "Search patient name...",
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: _brandIndigo, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildQueueCard(
    Map<String, dynamic> appt,
    int index,
    bool isLive,
    bool nurseSeen,
    String status,
    String userId,
  ) {
    final String patientId =
        (appt['patient_id'] ?? appt['user_id'] ?? '').toString();
    final String patientName =
        appt['patient_name'] ?? appt['full_name'] ?? "Unknown Patient";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLive
              ? (_isTechnician() ? _labAmber : _brandIndigo)
              : (nurseSeen ? Colors.green.shade200 : Colors.grey.shade100),
          width: isLive ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _buildBookingToken((index + 1).toString(), isLive),
            const SizedBox(width: 14),
            Expanded(
              child: InkWell(
                onTap: () => viewPatientHistory(context, patientId, patientName, userRole: widget.userRole),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            patientName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF1E293B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (nurseSeen && !_isTechnician())
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.green,
                            size: 16,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _infoTile(
                      _isTechnician()
                          ? Icons.biotech_rounded
                          : Icons.access_time_filled_rounded,
                      _isTechnician()
                          ? (appt['lab_category'] ?? "General Lab")
                          : (appt['appointment_time'] ?? "Waitlist"),
                    ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 24, thickness: 1, indent: 8, endIndent: 8),
            _buildRoleActions(appt, status, nurseSeen, userId),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleActions(
    Map<String, dynamic> appt,
    String status,
    bool nurseSeen,
    String userId,
  ) {
    // ── Technician ────────────────────────────────────────────────────────
    if (_isTechnician()) {
      String btnText = "Collect Sample";
      Color btnColor = _brandIndigo;

      if (status == 'collecting_sample') {
        btnText = "Start Test";
        btnColor = Colors.orange;
      } else if (status == 'processing') {
        btnText = "In Progress";
        btnColor = _labAmber;
      }

      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: btnColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onPressed: () {
          if (['confirmed', 'pending_lab', 'scheduled'].contains(status)) {
            _updateStatus(appt['id'].toString(), 'collecting_sample');
          } else if (status == 'collecting_sample') {
            _updateStatus(appt['id'].toString(), 'processing');
          }
        },
        child: Text(
          btnText,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    }

    // ── Nurse ─────────────────────────────────────────────────────────────
    if (_isNurse()) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (nurseSeen) _buildDoneBadge(),
          Material(
            color: nurseSeen
                ? Colors.grey.shade100
                : _nurseTeal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => _startCall(appt, userId, true),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  nurseSeen ? "Recall" : "Triage",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: nurseSeen ? Colors.grey.shade600 : _nurseTeal,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // ── Doctor ────────────────────────────────────────────────────────────
    final bool isNurseBusy = status == 'nurse_calling';
    final bool isActive =
        ['in_progress', 'consulting', 'calling'].contains(status);

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isNurseBusy
            ? Colors.grey
            : (isActive ? Colors.orange : _brandIndigo),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: () {
        if (isNurseBusy) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Nurse is currently triaging this patient."),
            ),
          );
          return;
        }
        _startCall(appt, userId, false);
      },
      child: Text(
        isActive ? "Resume" : "Connect",
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildBookingToken(String order, bool isLive) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: isLive
            ? (_isTechnician() ? _labAmber : _brandIndigo)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _isTechnician() ? "SLOT" : "NO.",
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: isLive ? Colors.white70 : Colors.grey.shade500,
            ),
          ),
          Text(
            order,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: isLive
                  ? Colors.white
                  : (_isTechnician() ? _labAmber : _brandIndigo),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: _brandIndigo.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDoneBadge() => const Padding(
        padding: EdgeInsets.only(bottom: 4),
        child: Text(
          "TRIAGED",
          style: TextStyle(
            color: Color(0xFF166534),
            fontSize: 8,
            fontWeight: FontWeight.w900,
          ),
        ),
      );

  Widget _buildEmptyState({String? message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isTechnician()
                ? Icons.biotech_outlined
                : Icons.auto_awesome_motion_rounded,
            size: 60,
            color: Colors.grey.shade200,
          ),
          const SizedBox(height: 16),
          Text(
            message ??
                (_searchQuery.isEmpty
                    ? "No Active Queue"
                    : "No matches for '$_searchQuery'"),
            style: TextStyle(
              color: Colors.grey.shade400,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}