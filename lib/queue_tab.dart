import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'supabase_handler.dart';
import 'video_call_page.dart';
import 'shared_widgets.dart';

class QueueTab extends StatefulWidget {
  final String userRole;
  final TabController? tabController;
  final String selectedFilter;
  final String? filterId; // For Nurses, this is the assigned_doctor_id from nurse_staff_unified

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
  final supabase = SupabaseHandler().client;
  final Color brandIndigo = const Color(0xFF6366F1);
  final Color nurseTeal = const Color(0xFF0D9488);
  final Color labAmber = const Color(0xFFD97706);

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  /// ✅ professional zego uid cache (Option A)
  String? _myZegoUid;
  bool _loadingZegoUid = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMyZegoUid(); // ✅ load once
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isNurse() => widget.userRole.toLowerCase() == "nurse";
  bool _isTechnician() => widget.userRole.toLowerCase() == "technician";

  Future<void> _loadMyZegoUid() async {
    if (_loadingZegoUid) return;
    _loadingZegoUid = true;

    final user = supabase.auth.currentUser;
    if (user == null) {
      _loadingZegoUid = false;
      return;
    }

    // 1) metadata
    final metaUid = user.userMetadata?['zego_uid']?.toString().trim();
    if (metaUid != null && metaUid.isNotEmpty) {
      if (mounted) setState(() => _myZegoUid = metaUid);
      _loadingZegoUid = false;
      return;
    }

    // 2) profiles table (✅ allowed for self; staff is reading their own profile here)
    try {
      final data = await supabase
          .from('profiles')
          .select('zego_uid')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      final z = (data?['zego_uid'] ?? '').toString().trim();
      setState(() => _myZegoUid = z.isNotEmpty ? z : user.id); // fallback
    } catch (_) {
      if (mounted) setState(() => _myZegoUid = user.id); // fallback
    } finally {
      _loadingZegoUid = false;
    }
  }

  Future<void> _updateStatus(String id, String status, {bool nurseSeen = false}) async {
    try {
      Map<String, dynamic> updateData = {'status': status.toLowerCase()};
      if (nurseSeen) updateData['nurse_seen'] = true;

      await supabase.from('bookings').update(updateData).eq('id', id);
    } catch (e) {
      _showErrorSnackBar(e);
    }
  }

  void _showErrorSnackBar(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Action failed: $e"), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // ✅ use professional zego uid if available (Option A)
    final String? currentUserId =
        (_myZegoUid ?? supabase.auth.currentUser?.id)?.toString().trim();

    Stream<List<Map<String, dynamic>>> getStream() {
      if (widget.filterId != null) {
        if (_isTechnician()) {
          return supabase
              .from('bookings')
              .stream(primaryKey: ['id'])
              .eq('lab_category', widget.filterId!)
              .order('id', ascending: true);
        } else {
          return supabase
              .from('bookings')
              .stream(primaryKey: ['id'])
              .eq('provider_id', widget.filterId!)
              .order('id', ascending: true);
        }
      }
      return supabase.from('bookings').stream(primaryKey: ['id']).order('id', ascending: true);
    }

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            key: ValueKey(widget.filterId),
            stream: getStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text("Access Error: ${snapshot.error}"));
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final data = snapshot.data ?? [];

              if (data.isEmpty) {
                if (_isNurse() || _isTechnician()) {
                  if (widget.filterId == null) {
                    return _buildEmptyState(message: "Waiting for Assignment...");
                  }
                }
                return _buildEmptyState();
              }

              final activeBookings = data.where((e) {
                final String status = e['status']?.toString().toLowerCase() ?? '';
                bool matchesStatus;

                if (_isTechnician()) {
                  matchesStatus = [
                    'confirmed',
                    'pending_lab',
                    'collecting_sample',
                    'processing',
                    'scheduled'
                  ].contains(status);
                } else {
                  matchesStatus = [
                    'pending',
                    'confirmed',
                    'consulting',
                    'scheduled',
                    'in_progress',
                    'nurse_calling',
                    'calling'
                  ].contains(status);
                }

                final String patientName = (e['patient_name'] ?? e['full_name'] ?? "")
                    .toString()
                    .toLowerCase();

                return matchesStatus && patientName.contains(_searchQuery.toLowerCase());
              }).toList();

              if (activeBookings.isEmpty) return _buildEmptyState();

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: activeBookings.length,
                itemBuilder: (context, index) {
                  final appt = activeBookings[index];
                  final String status = appt['status']?.toString().toLowerCase() ?? '';
                  final bool nurseSeen = appt['nurse_seen'] ?? false;
                  final bool isLive = _isTechnician()
                      ? status == 'processing'
                      : ['consulting', 'in_progress', 'nurse_calling', 'calling'].contains(status);

                  return _buildQueueCard(appt, index, isLive, nurseSeen, status, currentUserId ?? '');
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _startCall(Map<String, dynamic> appt, String userId, bool asNurse) async {
  final String rawBookingId = appt['id'].toString();

  // ✅ support both schemas
  final String patientAuthUid =
      (appt['user_id'] ?? appt['patient_id'] ?? '').toString().trim();

  if (patientAuthUid.isEmpty) {
    _showErrorSnackBar("Booking missing user_id/patient_id. Can't place call.");
    return;
  }

  final String patientName =
      (appt['patient_name'] ?? appt['full_name'] ?? "Patient").toString();

  // ✅ ensure professional zego uid is loaded
  if (_myZegoUid == null || _myZegoUid!.trim().isEmpty) {
    await _loadMyZegoUid();
    if (!mounted) return;
  }
  final String professionalZegoUid = (_myZegoUid ?? userId).toString().trim();

  // ✅ PRIMARY: read from bookings (RLS-safe)
  String patientZegoUid =
      (appt['patient_zego_uid'] ?? '').toString().trim();

  // ✅ FALLBACK: try profiles (may be blocked by RLS for staff)
  if (patientZegoUid.isEmpty) {
    try {
      final profile = await supabase
          .from('profiles')
          .select('zego_uid')
          .eq('id', patientAuthUid)
          .maybeSingle();

      if (!mounted) return;

      patientZegoUid = (profile?['zego_uid'] ?? '').toString().trim();
    } catch (_) {
      patientZegoUid = '';
    }
  }

  if (patientZegoUid.isEmpty) {
    _showErrorSnackBar(
      "Patient zego_uid not readable. Fix: store patient_zego_uid in bookings when booking is created.",
    );
    return;
  }

  final String ringingStatus = asNurse ? 'nurse_calling' : 'calling';
  await _updateStatus(rawBookingId, ringingStatus, nurseSeen: asNurse);
  if (!mounted) return;

  final String normalizedRoomId = SupabaseHandler.getNormalizedRoomId(rawBookingId);

  try {
    await ZegoUIKitPrebuiltCallInvitationService().send(
      invitees: [ZegoCallUser(patientZegoUid, patientName)],
      isVideoCall: true,
      callID: normalizedRoomId,
      customData: rawBookingId,
      resourceID: "swasthall_push",
    );
  } catch (e) {
    _showErrorSnackBar("Invite failed: $e");
    return;
  }

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text("Calling $patientName..."),
      duration: const Duration(seconds: 2),
      backgroundColor: brandIndigo,
    ),
  );

  if (!mounted) return;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => VideoCallPage(
        callID: normalizedRoomId,
        bookingId: rawBookingId,
        userID: professionalZegoUid,
        userName: widget.userRole,
        patientID: patientAuthUid,
        patientName: patientName,
        appointmentData: appt,
        professionalRole: widget.userRole,
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
    final String patientId = (appt['user_id'] ?? appt['patient_id'] ?? '').toString();
    final String patientName = appt['patient_name'] ?? appt['full_name'] ?? "Unknown Patient";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLive
              ? (_isTechnician() ? labAmber : brandIndigo)
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
                onTap: () => viewPatientHistory(context, patientId, patientName),
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
                          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _infoTile(
                      _isTechnician() ? Icons.biotech_rounded : Icons.access_time_filled_rounded,
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

  Widget _buildRoleActions(Map<String, dynamic> appt, String status, bool nurseSeen, String userId) {
    if (_isTechnician()) {
      String btnText = "Collect Sample";
      Color btnColor = brandIndigo;

      if (status == 'collecting_sample') {
        btnText = "Start Test";
        btnColor = Colors.orange;
      } else if (status == 'processing') {
        btnText = "In Progress";
        btnColor = labAmber;
      }

      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: btnColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onPressed: () {
          if (status == 'confirmed' || status == 'pending_lab' || status == 'scheduled') {
            _updateStatus(appt['id'].toString(), 'collecting_sample');
          } else if (status == 'collecting_sample') {
            _updateStatus(appt['id'].toString(), 'processing');
          }
        },
        child: Text(btnText, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }

    if (_isNurse()) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (nurseSeen) _buildDoneBadge(),
          Material(
            color: nurseSeen ? Colors.grey.shade100 : nurseTeal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => _startCall(appt, userId, true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  nurseSeen ? "Recall" : "Triage",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: nurseSeen ? Colors.grey.shade600 : nurseTeal,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    bool isNurseBusy = status == 'nurse_calling';
    bool isActive = ['in_progress', 'consulting', 'calling'].contains(status);

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isNurseBusy ? Colors.grey : (isActive ? Colors.orange : brandIndigo),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: () {
        if (isNurseBusy) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Nurse is currently triaging this patient.")),
          );
          return;
        }
        _startCall(appt, userId, false);
      },
      child: Text(isActive ? "Resume" : "Connect", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

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
              borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: brandIndigo, width: 1.5)),
        ),
      ),
    );
  }

  Widget _buildBookingToken(String order, bool isLive) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: isLive ? (_isTechnician() ? labAmber : brandIndigo) : const Color(0xFFF1F5F9),
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
              color: isLive ? Colors.white : (_isTechnician() ? labAmber : brandIndigo),
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
        Icon(icon, size: 13, color: brandIndigo.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
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
          style: TextStyle(color: Color(0xFF166534), fontSize: 8, fontWeight: FontWeight.w900),
        ),
      );

  Widget _buildEmptyState({String? message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isTechnician() ? Icons.biotech_outlined : Icons.auto_awesome_motion_rounded,
            size: 60,
            color: Colors.grey.shade200,
          ),
          const SizedBox(height: 16),
          Text(
            message ?? (_searchQuery.isEmpty ? "No Active Queue" : "No matches for '$_searchQuery'"),
            style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}