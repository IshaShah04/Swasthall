// Reviewed for staff revenue analytics integration. No chart widget exists in this file yet, so no UI change was applied.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_screen.dart';
import 'professional_setting.dart';
import 'health_vault_screen.dart';
import 'quick_categories.dart';
import 'special_offers.dart';
import 'physical.dart';
import 'widgets/safe_network_image.dart';
import 'theme_colors.dart';
import 'package:intl/intl.dart';

class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({super.key});

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  final supabase = Supabase.instance.client;
  final Color brandBlue = const Color(0xFF6366F1);

  String _userRole = 'doctor';
  String? _myStaffId;
  String? _assignedLab;
  String? _avatarUrl;
  bool _isInitializing = true;

  int _unreadCount = 0;

  Future<User?> _waitForUser() async {
    for (int i = 0; i < 20; i++) {
      final user = supabase.auth.currentUser ?? supabase.auth.currentSession?.user;
      if (user != null) return user;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return supabase.auth.currentUser ?? supabase.auth.currentSession?.user;
  }

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _loadInitialStaffData();
  }

  Future<void> _loadInitialStaffData() async {
    final user = await _waitForUser();
    if (user == null) {
      if (mounted) setState(() => _isInitializing = false);
      return;
    }

    try {
      final results = await Future.wait([
        supabase
            .from('staff')
            .select('id, role, assigned_lab')
            .eq('email', user.email ?? '')
            .maybeSingle(),
        supabase
            .from('profiles')
            .select('avatar_url')
            .eq('id', user.id)
            .maybeSingle(),
      ]);

      final staffData = results[0];
      final profileData = results[1];

      if (mounted) {
        setState(() {
          if (staffData != null) {
            _myStaffId = staffData['id']?.toString();
            _userRole =
                (staffData['role'] ?? 'doctor').toString().toLowerCase();
            _assignedLab = staffData['assigned_lab']?.toString();
          }
          _avatarUrl = profileData?['avatar_url'];
          _isInitializing = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching staff data: $e");
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await Supabase.instance.client
          .rpc('get_unread_notification_count');
      if (mounted) setState(() => _unreadCount = (count as int?) ?? 0);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
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
                    _buildRealtimeAppointmentSection(),
                    const Text(
                      "Quick Categories",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    QuickCategories(brandBlue: brandBlue, userRole: _userRole),
                    const SizedBox(height: 24),
                    const Text(
                      "Special Offers",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
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
      return FutureBuilder<Map<String, dynamic>?>(
        future: _fetchAssignedDoctor(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingPlaceholder();
          }

          final providerId = snapshot.data?['assigned_doctor_id'];
          if (providerId == null) return _buildNoConsultationCard();
          return _buildAppointmentsList(providerId.toString());
        },
      );
    } else {
      return _buildAppointmentsList(_myStaffId);
    }
  }

  Future<Map<String, dynamic>?> _fetchAssignedDoctor() async {
    if (_myStaffId == null || _myStaffId!.isEmpty) return null;
    final data = await supabase
        .from('nurse_staff_unified')
        .select()
        .eq('nurse_id', _myStaffId!)
        .maybeSingle();
    return data == null ? null : Map<String, dynamic>.from(data);
  }


  DateTime? _parseAppointmentDateTime(Map<String, dynamic> row) {
    final date = (row['appointment_date'] ?? '').toString().trim();
    final time = (row['appointment_time'] ?? '').toString().trim();
    if (date.isEmpty || time.isEmpty) return null;

    final candidates = <String>[
      'yyyy-MM-dd hh:mm a',
      'yyyy-MM-dd h:mm a',
      'yyyy-MM-dd HH:mm',
      'yyyy-MM-dd HH:mm:ss',
    ];

    for (final pattern in candidates) {
      try {
        return DateFormat(pattern).parseStrict('$date $time');
      } catch (_) {}
    }

    return DateTime.tryParse('$date $time');
  }

  bool _shouldHideExpiredOrStaleScheduled(Map<String, dynamic> row) {
    final status = (row['status'] ?? '').toString().toLowerCase().trim();
    final isExpired = row['is_expired'] == true || status == 'expired';
    if (isExpired) return true;
    if (status != 'scheduled') return false;

    final appointmentAt = _parseAppointmentDateTime(row);
    if (appointmentAt == null) return false;

    return DateTime.now().isAfter(
      appointmentAt.add(const Duration(hours: 24)),
    );
  }


  Future<List<Map<String, dynamic>>> _fetchAppointments(String? filterId) async {
    try {
      dynamic query;
      if (_userRole == 'technician') {
        if (_myStaffId == null || _myStaffId!.isEmpty) return const [];
        query = supabase
            .from('lab_appointments')
            .select()
            .eq('professional_id', _myStaffId!)
            .order('appointment_date', ascending: true);
      } else {
        if (filterId == null || filterId.isEmpty) return const [];
        query = supabase
            .from('bookings')
            .select()
            .eq('provider_id', filterId)
            .order('appointment_date', ascending: true);
      }

      final data = await query;
      return (data as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } catch (e) {
      debugPrint("Appointment Load Error: $e");
      return const [];
    }
  }

  Widget _buildAppointmentsList(String? filterId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchAppointments(filterId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingPlaceholder();
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildNoConsultationCard();
        }

        final allRelevant = snapshot.data!.where((booking) {
          final status = (booking['status'] ?? '').toString().toLowerCase();
          if (_shouldHideExpiredOrStaleScheduled(booking)) return false;
          return status != 'completed' &&
              status != 'cancelled' &&
              status != 'failed' &&
              status != 'missed' &&
              status != 'expired';
        }).toList();

        if (allRelevant.isEmpty) return _buildNoConsultationCard();

        if (_userRole == 'technician') {
          final nextLabAppointment = allRelevant.first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getDynamicTitle(false),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              _buildTeleConsultationCard(context, nextLabAppointment),
              const SizedBox(height: 24),
            ],
          );
        }

        final onlineApps = allRelevant
            .where((b) => (b['type']?.toString().toLowerCase() ?? '') == 'online')
            .toList();
        final physicalApps = allRelevant
            .where((b) => (b['type']?.toString().toLowerCase() ?? '') == 'physical')
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onlineApps.isNotEmpty) ...[
              Text(
                _getDynamicTitle(false),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              _buildTeleConsultationCard(context, onlineApps.first,
                  isPhysical: false),
              const SizedBox(height: 24),
            ],
            if (physicalApps.isNotEmpty) ...[
              Text(
                _getDynamicTitle(true),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              _buildTeleConsultationCard(context, physicalApps.first,
                  isPhysical: true),
              const SizedBox(height: 24),
            ],
          ],
        );
      },
    );
  }

  String _getDynamicTitle(bool isPhysical) {
    if (isPhysical) return "Upcoming Physical Appointment";
    switch (_userRole) {
      case 'technician':
        return "Next Lab Appointment";
      case 'nurse':
        return "Upcoming Nursing Care";
      case 'pharmacist':
        return "Prescription Review";
      default:
        return "Upcoming Online Consultation";
    }
  }

  Color _getCardColor({bool isPhysical = false}) {
    Color baseColor;
    switch (_userRole) {
      case 'technician':
        baseColor = const Color(0xFF0D9488);
        break;
      case 'nurse':
        baseColor = Colors.orangeAccent;
        break;
      case 'pharmacist':
        baseColor = Colors.deepPurpleAccent;
        break;
      default:
        baseColor = brandBlue;
    }
    return isPhysical ? Color.alphaBlend(Colors.black12, baseColor) : baseColor;
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProfessionalSettings(userRole: _userRole),
            ),
          ),
          child: SafeAvatar(
            url: _avatarUrl,
            radius: 20,
            fallbackIcon: Icons.person_outline,
            backgroundColor: const Color(0xFFE0E7FF),
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/swasthall_icon.png',
                height: 32,
                width: 32,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.health_and_safety, color: brandBlue, size: 28),
              ),
              const SizedBox(width: 10),
              Text(
                "Swasthall",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(context),
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        Stack(
          children: [
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NotificationScreen(userRole: _userRole),
                  ),
                );
                setState(() => _unreadCount = 0);
              },
              icon: Icon(
                Icons.notifications_none_outlined,
                color: AppColors.textPrimary(context),
                size: 26,
              ),
              visualDensity: VisualDensity.compact,
            ),
            if (_unreadCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _unreadCount.toString(),
                    style: TextStyle(
                      color: AppColors.cardBg(context),
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      decoration: InputDecoration(
        hintText:
            _userRole == 'technician' ? "Search lab records..." : "Search patients...",
        prefixIcon: Icon(Icons.search, color: AppColors.textMuted(context)),
        filled: true,
        fillColor: AppColors.inputFill(context),
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: brandBlue),
        ),
      ),
    );
  }

  Widget _buildTeleConsultationCard(
    BuildContext context,
    Map<String, dynamic> data, {
    bool isPhysical = false,
  }) {
    final String status = data['status']?.toString().toUpperCase() ?? "PENDING";
    final cardColor = _getCardColor(isPhysical: isPhysical);

    final activePatientId =
        data['patient_id']?.toString() ?? data['user_id']?.toString();

    final technicianChipText =
        data['lab_category']?.toString() ??
        data['test_names']?.toString() ??
        _assignedLab ??
        "LAB";

    return GestureDetector(
      onTap: () {
        if (isPhysical) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PhysicalQueuePage(userRole: _userRole),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HealthVaultScreen(
                userRole: _userRole,
                activePatientId: activePatientId,
                appointmentData: data,
              ),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: cardColor.withValues(alpha: 0.29),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    data['patient_name'] ?? data['full_name'] ?? "Patient",
                    style: TextStyle(
                      color: AppColors.cardBg(context),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_userRole == 'technician')
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      technicianChipText.toUpperCase(),
                      style: TextStyle(
                        color: AppColors.cardBg(context),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (isPhysical)
                  const Icon(Icons.location_on, color: Colors.white70, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  color: Colors.white70,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  "${data['appointment_time'] ?? 'N/A'}",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg(context).withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.circle,
                          color: Colors.greenAccent, size: 8),
                      const SizedBox(width: 6),
                      Text(
                        status,
                        style: TextStyle(
                          color: AppColors.cardBg(context),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(25),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildNoConsultationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 40, color: Colors.green.shade200),
          const SizedBox(height: 12),
          const Text(
            "All caught up! No active appointments.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
