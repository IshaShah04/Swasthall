import 'package:flutter/material.dart';
import 'supabase_handler.dart';
import 'shared_widgets.dart';
import 'services/queue_widget_service.dart'; // Import your new service

class PhysicalQueuePage extends StatefulWidget {
  final String userRole;

  const PhysicalQueuePage({super.key, required this.userRole});

  @override
  State<PhysicalQueuePage> createState() => _PhysicalQueuePageState();
}

class _PhysicalQueuePageState extends State<PhysicalQueuePage> {
  final Color brandIndigo = const Color(0xFF6366F1);
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  String? _providerId;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initializeRoleContext();
  }

  Future<void> _initializeRoleContext() async {
    final user = SupabaseHandler().client.auth.currentUser;
    if (user == null) return;

    try {
      final data = await SupabaseHandler()
          .client
          .from('nurse_staff_unified')
          .select('id, assigned_doctor_id')
          .or('doctor_email.eq.${user.email},nurse_email.eq.${user.email}')
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _providerId = (widget.userRole.toLowerCase() == "nurse")
              ? data['assigned_doctor_id']
              : data['id'];
          _isInitializing = false;
        });
      }
    } catch (e) {
      debugPrint("Context Error: $e");
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  /// Refreshes the External Widget Data based on the current live list
  void _syncWidget(List<Map<String, dynamic>> activeItems) {
    if (activeItems.isNotEmpty) {
      final topPatient = activeItems.first;
      QueueWidgetService.updateLiveWidget(
        patientName: topPatient['patient_name'] ?? "Unknown",
        queueNum: "1", // This represents the person currently 'up next'
        bookingId: topPatient['id'].toString(),
      );
    } else {
      QueueWidgetService.clearWidget();
    }
  }

  Future<void> _updateAppointmentStatus(String id, String status) async {
    final success = await SupabaseHandler().updateAppointmentStatus(id, status);

    if (mounted) {
      if (success) {
        // We don't need to manually call _syncWidget here because 
        // the StreamBuilder will detect the DB change and trigger it automatically.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Patient marked as $status"),
            backgroundColor: status.toLowerCase() == 'completed'
                ? Colors.green
                : Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Action failed"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            "Doctor Professional Suite",
            style: TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          bottom: TabBar(
            indicatorColor: brandIndigo,
            labelColor: brandIndigo,
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: "Live Queue"),
              Tab(text: "Records Vault"),
            ],
          ),
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child: TabBarView(
                children: [
                  _buildQueueList(isActiveTab: true),
                  _buildQueueList(isActiveTab: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueList({required bool isActiveTab}) {
    final supabase = SupabaseHandler().client;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase.from('bookings').stream(
          primaryKey: ['id']).order('appointment_time', ascending: true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allItems = snapshot.data ?? [];
        final filteredItems = allItems.where((e) {
          final isPhysical = e['type']?.toString().toLowerCase() == 'physical';
          final isMyQueue = e['provider_id'] == _providerId;
          final status = e['status']?.toString().toLowerCase() ?? '';

          bool matchesTab;
          if (isActiveTab) {
            matchesTab = ['confirmed', 'scheduled', 'pending', 'in_progress'].contains(status);
          } else {
            matchesTab = ['completed', 'skipped', 'absent'].contains(status);
          }

          final name = (e['patient_name'] ?? '').toString().toLowerCase();
          final matchesSearch = name.contains(_searchQuery.toLowerCase());

          return isPhysical && isMyQueue && matchesTab && matchesSearch;
        }).toList();

        // BRIDGE LOGIC: Update the external widget if we are on the Live Tab
        if (isActiveTab && _searchQuery.isEmpty) {
          // We only sync if there's no active search to avoid flickering
          _syncWidget(filteredItems);
        }

        if (filteredItems.isEmpty) return _buildEmptyState(isActiveTab);

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: filteredItems.length,
          itemBuilder: (context, index) {
            final patient = filteredItems[index];
            return _buildPatientCard(patient, index + 1, isLive: isActiveTab);
          },
        );
      },
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> patient, int queueNum,
      {required bool isLive}) {
    final status = patient['status']?.toString().toUpperCase() ?? "";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          _buildQueueIndicator(queueNum, isLive, status),
          const SizedBox(width: 16),
          Expanded(
            child: InkWell(
              onTap: () => viewPatientHistory(context, patient['user_id'] ?? '',
                  patient['patient_name'] ?? 'Patient'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient['patient_name'] ?? "Unknown Patient",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    patient['patient_phone'] ?? "No contact info",
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          if (isLive)
            Row(
              children: [
                _actionCircleButton(
                  icon: Icons.fast_forward_rounded,
                  color: Colors.orange,
                  label: "Skip",
                  onTap: () => _updateAppointmentStatus(
                      patient['id'].toString(), 'skipped'),
                ),
                const SizedBox(width: 12),
                _actionCircleButton(
                  icon: Icons.check_circle_rounded,
                  color: Colors.green,
                  label: "Done",
                  onTap: () => _updateAppointmentStatus(
                      patient['id'].toString(), 'completed'),
                ),
              ],
            )
          else
            _buildStatusBadge(status),
        ],
      ),
    );
  }

  Widget _buildQueueIndicator(int num, bool isLive, String status) {
    Color bgColor = isLive ? brandIndigo.withValues(alpha: 0.1) : Colors.grey.shade100;
    Color txtColor = isLive ? brandIndigo : Colors.grey.shade400;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      child: Center(
        child: Text("#$num",
            style: TextStyle(
                color: txtColor, fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }

  Widget _actionCircleButton(
      {required IconData icon,
      required Color color,
      required String label,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    bool isCompleted = status == "COMPLETED";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isCompleted
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: isCompleted ? Colors.green : Colors.orange,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: "Search patient name...",
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
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
            borderSide: BorderSide(color: brandIndigo),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isActiveTab) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
              isActiveTab
                  ? Icons.assignment_turned_in_rounded
                  : Icons.history_rounded,
              size: 60,
              color: Colors.grey.shade200),
          const SizedBox(height: 16),
          Text(isActiveTab ? "No Active Queue" : "No Records Found",
              style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}