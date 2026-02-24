import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'professional_setting.dart';
import 'health_vault_screen.dart';
import 'quick_categories.dart';
import 'special_offers.dart';
import 'physical.dart';

class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({super.key});

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  final supabase = Supabase.instance.client;
  final Color brandBlue = const Color(0xFF6366F1);

  // Core State
  String _userRole = 'doctor';
  String? _myStaffId; 
  String? _assignedLab;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _loadInitialStaffData();
  }

  /// Fetches the logged-in user's role and staff ID once.
  Future<void> _loadInitialStaffData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final staffData = await supabase
          .from('staff')
          .select('id, role, assigned_lab')
          .eq('email', user.email ?? '')
          .maybeSingle();

      if (staffData != null) {
        setState(() {
          _myStaffId = staffData['id'];
          _userRole = (staffData['role'] ?? 'doctor').toString().toLowerCase();
          _assignedLab = staffData['assigned_lab'];
          _isInitializing = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching staff data: $e");
      setState(() => _isInitializing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadInitialStaffData,
              color: brandBlue,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 60),
                    _buildHeader(context),
                    const SizedBox(height: 20),
                    _buildSearchBar(),
                    const SizedBox(height: 24),
                    
                    // REAL-TIME SECTION
                    _buildRealtimeAppointmentSection(),

                    const Text("Quick Categories",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    QuickCategories(brandBlue: brandBlue),
                    const SizedBox(height: 24),
                    const Text("Special Offers",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    const SpecialOffers(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRealtimeAppointmentSection() {
    if (_userRole == 'nurse') {
      // Using the nurse_staff_unified view to get the assigned provider's ID
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase
            .from('nurse_staff_unified')
            .stream(primaryKey: ['nurse_id'])
            .eq('nurse_id', _myStaffId ?? ''),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingPlaceholder();
          }

          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return _buildNoConsultationCard();
          }

          // Use the assigned_doctor_id (which acts as the provider_id for the nurse)
          final providerId = snapshot.data!.first['assigned_doctor_id'];
          return _buildAppointmentsList(providerId);
        },
      );
    } else {
      // Doctors and others use their own staff ID as the filterId
      return _buildAppointmentsList(_myStaffId);
    }
  }

  Widget _buildAppointmentsList(String? filterId) {
    Stream<List<Map<String, dynamic>>> appointmentStream;

    try {
      if (_userRole == 'technician') {
        if (_assignedLab != null && _assignedLab!.isNotEmpty) {
          appointmentStream = supabase
              .from('bookings')
              .stream(primaryKey: ['id'])
              .eq('lab_category', _assignedLab!)
              .order('appointment_date', ascending: true);
        } else {
          return _buildNoConsultationCard();
        }
      } else {
        if (filterId != null && filterId.isNotEmpty) {
          // STRICT FILTER: Only looking at provider_id column
          appointmentStream = supabase
              .from('bookings')
              .stream(primaryKey: ['id'])
              .eq('provider_id', filterId)
              .order('appointment_date', ascending: true);
        } else {
          return _buildLoadingPlaceholder();
        }
      }
    } catch (e) {
      debugPrint("Stream Setup Error: $e");
      return _buildNoConsultationCard();
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: appointmentStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingPlaceholder();
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildNoConsultationCard();
        }

        // Local filtering for active status only
        final allRelevant = snapshot.data!.where((booking) {
          final status = (booking['status'] ?? '').toString().toLowerCase();
          return status != 'completed' && status != 'cancelled';
        }).toList();

        if (allRelevant.isEmpty) return _buildNoConsultationCard();

        final onlineApps = allRelevant.where((b) => b['type'].toString().toLowerCase() == 'online').toList();
        final physicalApps = allRelevant.where((b) => b['type'].toString().toLowerCase() == 'physical').toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onlineApps.isNotEmpty) ...[
              Text(_getDynamicTitle(false), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 12),
              _buildTeleConsultationCard(context, onlineApps.first, isPhysical: false),
              const SizedBox(height: 24),
            ],
            if (physicalApps.isNotEmpty) ...[
              Text(_getDynamicTitle(true), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 12),
              _buildTeleConsultationCard(context, physicalApps.first, isPhysical: true),
              const SizedBox(height: 24),
            ],
          ],
        );
      },
    );
  }

  // --- UI Helpers ---

  String _getDynamicTitle(bool isPhysical) {
    if (isPhysical) return "Upcoming Physical Appointment";
    switch (_userRole) {
      case 'technician': return "Next Lab Appointment";
      case 'nurse': return "Upcoming Nursing Care";
      case 'pharmacist': return "Prescription Review";
      default: return "Upcoming Online Consultation";
    }
  }

  Color _getCardColor({bool isPhysical = false}) {
    Color baseColor;
    switch (_userRole) {
      case 'technician': baseColor = const Color(0xFF0D9488); break;
      case 'nurse': baseColor = Colors.orangeAccent; break;
      case 'pharmacist': baseColor = Colors.deepPurpleAccent; break;
      default: baseColor = brandBlue;
    }
    return isPhysical ? Color.alphaBlend(Colors.black12, baseColor) : baseColor;
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProfessionalSettings(userRole: _userRole))),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: brandBlue.withAlpha(50), width: 2),
            ),
            child: const CircleAvatar(
              radius: 20,
              backgroundImage: NetworkImage('https://api.dicebear.com/7.x/avataaars/svg?seed=Felix'),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const CircleAvatar(radius: 4, backgroundColor: Colors.green),
        const Spacer(),
        IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_outlined, size: 28))
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      decoration: InputDecoration(
        hintText: _userRole == 'technician' ? "Search lab records..." : "Search patients...",
        prefixIcon: const Icon(Icons.search, color: Colors.grey),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: brandBlue)),
      ),
    );
  }

  Widget _buildTeleConsultationCard(BuildContext context, Map<String, dynamic> data, {bool isPhysical = false}) {
    final String status = data['status']?.toString().toUpperCase() ?? "PENDING";
    final cardColor = _getCardColor(isPhysical: isPhysical);

    return GestureDetector(
      onTap: () {
        if (isPhysical) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => PhysicalQueuePage(userRole: _userRole)));
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (context) => HealthVaultScreen(
            userRole: _userRole,
            activePatientId: data['patient_id']?.toString(),
            appointmentData: data,
          )));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: cardColor.withAlpha(75), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(data['patient_name'] ?? data['full_name'] ?? "Patient", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                if (_userRole == 'technician')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                    child: Text(data['lab_category']?.toString().toUpperCase() ?? "LAB", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                if (isPhysical) const Icon(Icons.location_on, color: Colors.white70, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text("${data['appointment_time'] ?? 'N/A'}", style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withAlpha(50), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                      const SizedBox(width: 6),
                      Text(status, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      height: 100,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildNoConsultationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.grey.shade100)),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 40, color: Colors.green.shade200),
          const SizedBox(height: 12),
          Text("All caught up! No active appointments.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}