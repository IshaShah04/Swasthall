import 'package:flutter/material.dart';
import 'main.dart' show switchToCompletedTab;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'queue_tab.dart';
import 'completed_tab.dart';

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
  String? _assignedLab;

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

  bool _isTechnician() => widget.userRole.toLowerCase() == "technician";
  bool _isNurse() => widget.userRole.toLowerCase() == "nurse";

  Future<void> _initializeProfessionalData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Fetch staff record via email
      final staffData = await supabase
          .from('staff')
          .select('id, role, assigned_lab')
          .eq('email', user.email ?? '')
          .maybeSingle();

      if (staffData != null) {
        String role = staffData['role'].toString().toLowerCase();
        String myStaffId = staffData['id'];
        String? lab = staffData['assigned_lab'];
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
            _filterId = finalFilterId;
            _assignedLab = lab;
            
            // 3. Setup the real-time stream
            if (role == 'technician') {
              _dashboardStream = supabase
                  .from('bookings')
                  .stream(primaryKey: ['id'])
                  .eq('lab_category', lab ?? 'Unknown');
            } else {
              // Both Doctors and Nurses filter by the doctor's ID in 'provider_id'
              _dashboardStream = supabase
                  .from('bookings')
                  .stream(primaryKey: ['id'])
                  .eq('provider_id', finalFilterId ?? '');
            }
            _isInitializing = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Critical Init Error: $e");
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _updateStatus(String id, String newStatus) async {
    try {
      await supabase
          .from('bookings')
          .update({
            'status': newStatus.toLowerCase(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);

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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          _isNurse() ? "Nursing Care Assistant" : "${widget.userRole} Professional Suite",
          style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 16),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildLiveStatsDashboard(),
                Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: brandIndigo,
                    unselectedLabelColor: Colors.grey,
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
                              userRole: widget.userRole,
                              tabController: _tabController,
                              selectedFilter: "Today",
                              filterId: _isTechnician() ? _assignedLab : _filterId,
                            ),
                            CompletedTab(
                              userRole: widget.userRole,
                              forceUploadMode: widget.forceUploadMode,
                              activePatientId: widget.activePatientId,
                              filterId: _isTechnician() ? _assignedLab : _filterId,
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
        
        final completed = allItems.where((e) => e['status']?.toString().toLowerCase() == 'completed').toList();
        final waiting = allItems.where((e) => [
              'confirmed', 'pending', 'pending_lab', 'collecting_sample'
            ].contains(e['status']?.toString().toLowerCase())).toList();
        
        final servingNow = allItems.firstWhere(
          (e) => ['consulting', 'calling', 'in_progress', 'processing'].contains(e['status']?.toString().toLowerCase()),
          orElse: () => {},
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
          child: Column(
            children: [
              if (servingNow.isNotEmpty) _buildActivePatientCard(servingNow),
              Row(
                children: [
                  _metricTile("Today", allItems.length.toString(), brandIndigo, Icons.calendar_today_rounded),
                  const SizedBox(width: 10),
                  _metricTile("Done", completed.length.toString(), healingGreen, Icons.check_circle_rounded),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _metricTile("Waiting", waiting.length.toString(), waitingOrange, Icons.hourglass_top_rounded),
                  const SizedBox(width: 10),
                  _metricTile("Role", _isNurse() ? "Nurse" : widget.userRole, Colors.blueGrey, Icons.person_pin_rounded),
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
        color: brandIndigo.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brandIndigo.withAlpha(50)),
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
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.black87)),
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
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(30)),
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