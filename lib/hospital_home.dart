import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_screen.dart';
import 'hospital_insurance_requests_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'hospital_profile.dart';
import 'doctor_detail.dart';
import 'widgets/safe_network_image.dart';
import 'theme_colors.dart';

class HospitalHomeScreen extends StatefulWidget {
  const HospitalHomeScreen({super.key});

  @override
  State<HospitalHomeScreen> createState() => _HospitalHomeScreenState();
}

class _HospitalHomeScreenState extends State<HospitalHomeScreen> {
  final supabase = Supabase.instance.client;
  final Color brandBlue = const Color(0xFF6366F1);
  int _unreadCount = 0;
  String? _resolvedHospitalId;

  Future<List<Map<String, dynamic>>>? _staffFuture;
  Future<Map<String, dynamic>>? _profileFuture;
  Future<List<Map<String, dynamic>>>? _revenueFuture;

  Future<User?> _waitForUser() async {
    for (int i = 0; i < 20; i++) {
      final user = supabase.auth.currentUser ?? supabase.auth.currentSession?.user;
      if (user != null) return user;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return supabase.auth.currentUser ?? supabase.auth.currentSession?.user;
  }


  Future<String?> _resolveHospitalId(User user) async {
    try {
      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final role = (profile?['role'] ?? '').toString().trim().toLowerCase();
      if (role == 'hospital' || role == 'clinic') {
        return user.id;
      }

      final staffByUser = await supabase
          .from('staff')
          .select('hospital_id')
          .eq('user_id', user.id)
          .maybeSingle();

      final hid = staffByUser?['hospital_id']?.toString();
      if (hid != null && hid.isNotEmpty && hid != 'null') return hid;

      final email = user.email?.trim();
      if (email != null && email.isNotEmpty) {
        final staffByEmail = await supabase
            .from('staff')
            .select('hospital_id')
            .eq('email', email)
            .maybeSingle();
        final hid2 = staffByEmail?['hospital_id']?.toString();
        if (hid2 != null && hid2.isNotEmpty && hid2 != 'null') return hid2;
      }
    } catch (e) {
      debugPrint('Hospital id resolution error: $e');
    }
    return user.id;
  }

  // State Variables
  String _selectedFilter = "Month";
  String _searchQuery = "";
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _initStreams();
  }

  Future<void> _initStreams() async {
    final user = await _waitForUser();
    if (!mounted) return;

    if (user == null) {
      setState(() {
        _resolvedHospitalId = null;
        _staffFuture = Future<List<Map<String, dynamic>>>.value(<Map<String, dynamic>>[]);
        _profileFuture = Future<Map<String, dynamic>>.value(<String, dynamic>{});
        _revenueFuture = Future<List<Map<String, dynamic>>>.value(<Map<String, dynamic>>[]);
      });
      return;
    }

    final hospitalId = await _resolveHospitalId(user);

    setState(() {
      _resolvedHospitalId = hospitalId;
      _staffFuture = hospitalId == null
          ? Future<List<Map<String, dynamic>>>.value(<Map<String, dynamic>>[])
          : _fetchStaff(hospitalId);
      _profileFuture = _fetchProfile(user.id);
    });
    await _updateRevenueFuture();
  }

  Future<List<Map<String, dynamic>>> _fetchStaff(String hospitalId) async {
    final data = await supabase
        .from('hospital_staff_unified')
        .select('id, name, speciality, avatar_url, daily_bookings, role, hospital_id')
        .eq('hospital_id', hospitalId)
        .limit(80);
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> _fetchProfile(String userId) async {
    final data = await supabase
        .from('profiles')
        .select('id, avatar_url, full_name')
        .eq('id', userId)
        .maybeSingle();
    return data == null ? <String, dynamic>{} : Map<String, dynamic>.from(data);
  }

  Future<void> _updateRevenueFuture() async {
    final user = await _waitForUser();
    if (!mounted) return;

    DateTime now = DateTime.now();
    setState(() {
      switch (_selectedFilter) {
        case "Today":
          _startDate = DateTime(now.year, now.month, now.day);
          break;
        case "Week":
          _startDate = now.subtract(const Duration(days: 7));
          break;
        case "15 Days":
          _startDate = now.subtract(const Duration(days: 15));
          break;
        default:
          _startDate = now.subtract(const Duration(days: 30));
          break;
      }

      _revenueFuture = (user == null || _resolvedHospitalId == null)
          ? Future<List<Map<String, dynamic>>>.value(<Map<String, dynamic>>[])
          : _fetchRevenue(_resolvedHospitalId!);
    });
  }


  Future<List<Map<String, dynamic>>> _fetchRevenue(String hospitalId) async {
    final rows = await supabase.rpc(
      'get_my_staff_revenue_analytics_range',
      params: {
        'p_from': _startDate.toIso8601String().split('T').first,
        'p_to': DateTime.now().toIso8601String().split('T').first,
      },
    );

    final list = (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((row) => row['hospital_id']?.toString() == hospitalId)
        .toList();

    final Map<String, double> byDate = {};
    for (final row in list) {
      final revenueDate = (row['revenue_date'] ?? '').toString();
      final amount = ((row['hospital_payout'] as num?)?.toDouble()) ??
          double.tryParse('${row['hospital_payout'] ?? 0}') ??
          0.0;
      if (revenueDate.isEmpty) continue;
      byDate[revenueDate] = (byDate[revenueDate] ?? 0) + amount;
    }

    final entries = byDate.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return entries
        .map((e) => {
              'revenue_date': e.key,
              'amount': e.value,
            })
        .toList();
  }

  Future<void> _handleRefresh() async {
    await _initStreams();
    await Future.delayed(const Duration(milliseconds: 300));
  }

  void _navigateToDoctorDetail(Map<String, dynamic> staffData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DoctorDetailScreen(staff: staffData),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredStaff(
      List<Map<String, dynamic>> allStaff) {
    if (_searchQuery.trim().isEmpty) return allStaff;
    final query = _searchQuery.trim().toLowerCase();
    return allStaff.where((doc) {
      final name = (doc['name'] ?? "").toString().toLowerCase();
      final spec = (doc['speciality'] ?? "").toString().toLowerCase();
      return name.contains(query) || spec.contains(query);
    }).toList();
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
    if (_profileFuture == null || _staffFuture == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        color: brandBlue,
        onRefresh: _handleRefresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _staffFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final allStaff = snapshot.data ?? [];
            final filteredStaff = _getFilteredStaff(allStaff);

            List<Map<String, dynamic>> topSpecialists = List.from(allStaff);
            topSpecialists.sort((a, b) =>
                (b['daily_bookings'] ?? 0).compareTo(a['daily_bookings'] ?? 0));

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchBar(),
                  _buildRevenueSection(),
                  if (topSpecialists.isNotEmpty && _searchQuery.isEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 16, 12),
                      child: Text("Top Specialists",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    _buildTopSpecialists(topSpecialists),
                  ],
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 32, 16, 0),
                    child: Text("Medical Team",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  _buildStaffGrid(filteredStaff),
                  const SizedBox(height: 100),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.cardBg(context),
      elevation: 0,
      leadingWidth: 56,
      leading: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          final avatarUrl = snapshot.data?['avatar_url'];
          return Padding(
            padding: const EdgeInsets.only(left: 12),
            child: GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const HospitalProfileScreen())),
              child: SafeAvatar(
                url: avatarUrl,
                radius: 20,
                fallbackIcon: Icons.person_outline,
                backgroundColor: const Color(0xFFE0E7FF),
              ),
            ),
          );
        },
      ),
      // ── Logo + wordmark — matches patient home appbar ──
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
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
          const Text(
            "Swasthall",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2937),
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_outlined,
                  color: Color(0xFF1F2937), size: 26),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const NotificationScreen(userRole: 'hospital')));
                setState(() => _unreadCount = 0);
              },
            ),
            if (_unreadCount > 0)
              Positioned(
                right: 8, top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                  child: Text(_unreadCount.toString(),
                      style: TextStyle(color: AppColors.cardBg(context),
                          fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.request_page_outlined,
              color: Color(0xFF6366F1), size: 24),
          tooltip: 'Insurance Requests',
          onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => const HospitalInsuranceRequestsScreen())),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: "Search name or speciality...",
          prefixIcon: Icon(Icons.search, color: AppColors.textMuted(context)),
          filled: true,
          fillColor: AppColors.inputFill(context),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildRevenueSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadow(context),
              blurRadius: 20,
              offset: const Offset(0, 10))
        ],
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Revenue Overview",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ["Today", "Week", "15 Days", "Month"].map((filter) {
                bool isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter,
                        style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey,
                            fontSize: 12)),
                    selected: isSelected,
                    selectedColor: brandBlue,
                    backgroundColor: AppColors.surfaceBg(context),
                    showCheckmark: false,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    onSelected: (bool selected) {
                      if (selected) {
                        setState(() {
                          _selectedFilter = filter;
                          _updateRevenueFuture();
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 25),
          SizedBox(
            height: 180,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _revenueFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final filteredData = snapshot.data ?? [];

                if (snapshot.hasError) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.bar_chart_rounded,
                          size: 36, color: const Color(0xFFCBD5E1)),
                      const SizedBox(height: 8),
                      Text("Could not load revenue",
                          style: TextStyle(color: const Color(0xFF94A3B8))),
                    ]),
                  );
                }

                if (filteredData.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.bar_chart_rounded,
                          size: 36, color: const Color(0xFFCBD5E1)),
                      const SizedBox(height: 8),
                      Text("No data for this period",
                          style: TextStyle(color: const Color(0xFF94A3B8))),
                    ]),
                  );
                }

                // BUG FIX 1: amount could be null or String — safe parse
                final spots = filteredData.asMap().entries.map((e) {
                  final raw = e.value['amount'];
                  final amount = (raw is num)
                      ? raw.toDouble()
                      : double.tryParse(raw?.toString() ?? '') ?? 0.0;
                  return FlSpot(e.key.toDouble(), amount);
                }).toList();

                // BUG FIX 2: LineChart crashes with only 1 point — show total instead
                if (spots.length == 1) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        "NPR ${filteredData.first['amount']?.toString() ?? '0'}",
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: brandBlue),
                      ),
                      Text("Total revenue",
                          style: TextStyle(color: const Color(0xFF94A3B8))),
                    ]),
                  );
                }

                return LineChart(
                  LineChartData(
                    gridData:
                        const FlGridData(show: true, drawVerticalLine: false),
                    titlesData: const FlTitlesData(
                      rightTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: false,
                        barWidth: 3,
                        color: brandBlue,
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              brandBlue.withValues(alpha: 0.2),
                              brandBlue.withValues(alpha: 0)
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSpecialists(List<Map<String, dynamic>> docs) {
    return SizedBox(
      height: 150,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: docs.length > 5 ? 5 : docs.length,
        itemBuilder: (context, index) {
          final doc = docs[index];
          return GestureDetector(
            onTap: () => _navigateToDoctorDetail(doc),
            child: Container(
              width: 130,
              margin: const EdgeInsets.only(right: 12, bottom: 10, top: 5),
              decoration: BoxDecoration(
                color: AppColors.cardBg(context),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 4))
                ],
                border: Border.all(color: brandBlue.withValues(alpha: 0.1)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SafeAvatar(
                    url: doc['avatar_url']?.toString(),
                    radius: 32,
                    name: doc['name']?.toString(),
                    backgroundColor: AppColors.surfaceBg(context),
                  ),
                  const SizedBox(height: 8),
                  Text(doc['name'] ?? "Doctor",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(doc['speciality'] ?? "Consultant",
                      style: TextStyle(color: AppColors.textMuted(context), fontSize: 11)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStaffGrid(List<Map<String, dynamic>> staff) {
    if (staff.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(40.0), child: Text("No staff found")));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 55, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.95, // Made wider/shorter to fill space better
        crossAxisSpacing: 16,
        mainAxisSpacing: 50, // Space for the popping avatar
      ),
      itemCount: staff.length,
      itemBuilder: (context, index) => _buildPoppingCard(staff[index]),
    );
  }

  Widget _buildPoppingCard(Map<String, dynamic> member) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        InkWell(
          onTap: () => _navigateToDoctorDetail(member),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 55, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                    color: AppColors.shadow(context),
                    blurRadius: 15,
                    offset: const Offset(0, 8))
              ],
            ),
            child: Column(
              children: [
                Text(member['name'] ?? "Unknown",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                Text(member['speciality'] ?? "Specialist",
                    style: TextStyle(
                        color: brandBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                const Divider(height: 16),
                _smallInfoRow(Icons.currency_rupee,
                    "Fee: ${member['first_consultation_fee'] ?? '0'}"),
                _smallInfoRow(Icons.verified_user_outlined,
                    member['qualifications']?.toString() ?? "Medical Degree"),
              ],
            ),
          ),
        ),
        Positioned(
          top: -42,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC), shape: BoxShape.circle),
            child: SafeAvatar(
              url: member['avatar_url']?.toString(),
              radius: 42,
              name: member['name']?.toString(),
              backgroundColor: AppColors.cardBg(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _smallInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: const Color(0xFF475569)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}