import 'package:flutter/material.dart';
import 'main.dart' show switchToCompletedTab;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'queue_tab.dart';
import 'completed_tab.dart';
import 'theme_colors.dart';

class HealthVaultScreen extends StatefulWidget {
  final bool forceUploadMode;
  final String? activePatientId;
  final String userRole;
  final Map<String, dynamic>? appointmentData;

  const HealthVaultScreen({
    super.key,
    this.forceUploadMode = false,
    this.activePatientId,
    this.userRole = "Doctor",
    this.appointmentData,
  });

  @override
  State<HealthVaultScreen> createState() => _HealthVaultScreenState();
}

class _HealthVaultScreenState extends State<HealthVaultScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final supabase = Supabase.instance.client;

  Stream<List<Map<String, dynamic>>>? _dashboardStream;
  bool _isInitializing = true;
  
  String? _filterId;
  String? _effectiveRole;

  final ValueNotifier<int> _refreshNotifier = ValueNotifier<int>(0);

  final Color brandIndigo = const Color(0xFF6366F1);
  final Color healingGreen = const Color(0xFF10B981);
  final Color waitingOrange = Colors.orange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.forceUploadMode ? 1 : 0,
    );
    _initializeProfessionalData();

    // After doctor's call ends, ZEGO fires onCallEnd in main.dart which
    // toggles switchToCompletedTab. We listen here to switch to tab 1.
    switchToCompletedTab.addListener(_onCallEnded);
  }

  void _onCallEnded() {
    if (!mounted) return;
    _tabController.animateTo(1);
  }

  String get _normalizedRole => (_effectiveRole ?? widget.userRole).toLowerCase();
  bool _isTechnician() => _normalizedRole == "technician";
  bool _isNurse() => _normalizedRole == "nurse";

  Future<void> _initializeProfessionalData() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isInitializing = false);
      return;
    }

    try {
      // 1. Fetch staff record by auth uid first, then email fallback for legacy staff rows.
      Map<String, dynamic>? staffData = await supabase
          .from('staff')
          .select('id, role, assigned_lab')
          .or('id.eq.${user.id},user_id.eq.${user.id},profile_id.eq.${user.id}')
          .maybeSingle();

      staffData ??= await supabase
          .from('staff')
          .select('id, role, assigned_lab')
          .eq('email', user.email ?? '')
          .maybeSingle();

      if (staffData != null) {
        String role = staffData['role'].toString().toLowerCase();
        String myStaffId = staffData['id'];
        String? finalFilterId = myStaffId;

        // 2. Logic for Nurse to use the Unified View for the Doctor's queue
        if (role == 'nurse') {
          final unifiedData = await supabase
              .from('nurse_staff_unified')
              .select('assigned_doctor_id')
              .eq('nurse_id', myStaffId)
              .maybeSingle();
              
          if (unifiedData != null) {
            finalFilterId = unifiedData['assigned_doctor_id'];
          }
        }

        if (mounted) {
          setState(() {
            _effectiveRole = role;
            _filterId = finalFilterId;
            
            // 3. Setup the real-time stream
            // Technician: read lab_appointments by their own staff ID (professional_id).
            // myStaffId is the technician's staff.id which matches lab_appointments.professional_id
            // set at booking time from labData['id'] in lab_payment.dart.
            if (role == 'technician') {
              _dashboardStream = supabase
                  .from('lab_appointments')
                  .stream(primaryKey: ['id'])
                  .eq('professional_id', myStaffId);
            } else {
              // Both Doctors and Nurses filter by the doctor's ID in 'provider_id'
              if (finalFilterId != null && finalFilterId.isNotEmpty) {
                _dashboardStream = supabase
                    .from('bookings')
                    .stream(primaryKey: ['id'])
                    .eq('provider_id', finalFilterId);
              } else {
                debugPrint('health_vault: skipping stream — filterId empty');
              }
            }
            _isInitializing = false;
          });
        }
      } else {
        debugPrint('health_vault: no staff record found for current user');
        if (mounted) setState(() => _isInitializing = false);
      }
    } catch (e) {
      debugPrint("Critical Init Error: $e");
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _updateStatus(String id, String newStatus) async {
    try {
      final normalized = newStatus.toLowerCase();

      if (_isTechnician() && normalized == 'completed') {
        final labAppointmentId = int.tryParse(id);
        if (labAppointmentId == null) {
          throw Exception('Invalid lab appointment id');
        }
        await supabase.rpc(
          'mark_lab_appointment_completed',
          params: {'p_lab_appointment_id': labAppointmentId},
        );
      } else if (!_isTechnician()) {
        if (normalized == 'completed') {
          await supabase.rpc(
            'mark_booking_completed',
            params: {'p_booking_id': id},
          );
        } else {
          await supabase.rpc(
            'advance_queue_safely',
            params: {'target_booking_id': id, 'new_status': normalized},
          );
        }
      } else {
        await supabase
            .from('lab_appointments')
            .update({'status': normalized})
            .eq('id', int.tryParse(id) ?? id);
      }

      _refreshNotifier.value++;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Status updated to $newStatus"),
            backgroundColor: healingGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("Update Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to update status. Please try again."),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    switchToCompletedTab.removeListener(_onCallEnded);
    _tabController.dispose();
    _refreshNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          _isNurse() ? "Nursing Care Assistant" : "${_effectiveRole ?? widget.userRole} Professional Suite",
          style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary(context), fontSize: 16),
        ),
        centerTitle: true,
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary(context), size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildLiveStatsDashboard(),
                Container(
                  color: AppColors.cardBg(context),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: brandIndigo,
                    unselectedLabelColor: AppColors.textMuted(context),
                    indicatorColor: brandIndigo,
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    tabs: const [
                      Tab(text: "Live Queue"),
                      Tab(text: "Records Vault"),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                Expanded(
                  child: ValueListenableBuilder(
                      valueListenable: _refreshNotifier,
                      builder: (context, value, child) {
                        return TabBarView(
                          controller: _tabController,
                          children: [
                            QueueTab(
                              userRole: _effectiveRole ?? widget.userRole,
                              tabController: _tabController,
                              selectedFilter: "Today",
                              filterId: _filterId, // doctors/nurses: provider_id; technicians: professional_id in lab_appointments
                            ),
                            CompletedTab(
                              userRole: _effectiveRole ?? widget.userRole,
                              forceUploadMode: widget.forceUploadMode,
                              activePatientId: widget.activePatientId,
                              filterId: _filterId, // doctors/nurses: provider_id; technicians: professional_id in lab_appointments
                            ),
                          ],
                        );
                      }),
                ),
              ],
            ),
    );
  }

  Widget _buildLiveStatsDashboard() {
    if (_dashboardStream == null) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _dashboardStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox(height: 100, child: Center(child: Text("Connection Error")));
        if (!snapshot.hasData) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));

        final allItems = snapshot.data ?? [];
        final nonExpired =
            allItems.where((e) => e['is_expired'] != true).toList();

        final completed = nonExpired
            .where((e) => e['status']?.toString().toLowerCase() == 'completed')
            .toList();

        final waiting = nonExpired.where((e) => _isTechnician()
              ? ['scheduled', 'collecting_sample']
                  .contains(e['status']?.toString().toLowerCase())
              : ['confirmed', 'pending', 'pending_lab', 'collecting_sample']
                  .contains(e['status']?.toString().toLowerCase()))
            .toList();

        final servingNow = nonExpired.firstWhere(
          (e) => ['consulting', 'calling', 'in_progress', 'processing']
              .contains(e['status']?.toString().toLowerCase()),
          orElse: () => {},
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.cardBg(context), border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
          child: Column(
            children: [
              if (servingNow.isNotEmpty) _buildActivePatientCard(servingNow),
              Row(
                children: [
                  _metricTile("Today", nonExpired.length.toString(), brandIndigo, Icons.calendar_today_rounded),
                  const SizedBox(width: 10),
                  _metricTile("Done", completed.length.toString(), healingGreen, Icons.check_circle_rounded),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _metricTile("Waiting", waiting.length.toString(), waitingOrange, Icons.hourglass_top_rounded),
                  const SizedBox(width: 10),
                  _metricTile("Role", _isNurse() ? "Nurse" : (_effectiveRole ?? widget.userRole), Colors.blueGrey, Icons.person_pin_rounded),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActivePatientCard(Map<String, dynamic> servingNow) {
    String statusLabel = _isTechnician() ? "LAB PROCESSING" : "LIVE CONSULTATION";
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: brandIndigo.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brandIndigo.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(_isTechnician() ? Icons.science_rounded : Icons.record_voice_over_rounded, color: brandIndigo, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusLabel, style: TextStyle(color: brandIndigo, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2)),
                Text("${servingNow['patient_name'] ?? 'Unknown'}", 
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.textSecondary(context))),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.task_alt_rounded, color: healingGreen),
            onPressed: () => _updateStatus(servingNow['id'].toString(), 'completed'),
          ),
        ],
      ),
    );
  }

  Widget _metricTile(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color), overflow: TextOverflow.ellipsis),
                Text(label, style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}