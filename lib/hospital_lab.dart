import 'package:flutter/material.dart';
import 'widgets/safe_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'new_lab_test.dart';
import 'hospital_lab_discription.dart';
import 'all_bookings_screen.dart';
import 'theme_colors.dart';

class HospitalLabScreen extends StatefulWidget {
  const HospitalLabScreen({super.key});

  @override
  State<HospitalLabScreen> createState() => _HospitalLabScreenState();
}

class _HospitalLabScreenState extends State<HospitalLabScreen> {
  final supabase = Supabase.instance.client;
  String searchQuery = '';

  Future<List<Map<String, dynamic>>>? _labFuture;
  Future<List<Map<String, dynamic>>>? _nextAppointmentFuture;
  final Map<String, String> _workingTimeCache = {};
  String? _resolvedHospitalId;
  bool _isRefreshing = false;

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
    _loadHospitalAndInitStreams();
  }

  Future<List<Map<String, dynamic>>> _emptyFuture() async => const [];

  List<String> _uniqueNonEmpty(Iterable<String?> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final value in values) {
      final normalized = value?.trim() ?? '';
      if (normalized.isEmpty || normalized == 'null' || seen.contains(normalized)) {
        continue;
      }
      seen.add(normalized);
      out.add(normalized);
    }
    return out;
  }

  List<Map<String, dynamic>> _mergeUniqueRows(List<List<Map<String, dynamic>>> batches) {
    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];

    for (final batch in batches) {
      for (final row in batch) {
        final id = row['id']?.toString().trim() ?? '';
        if (id.isEmpty || seen.contains(id)) continue;
        seen.add(id);
        merged.add(row);
      }
    }

    return merged;
  }

  Future<List<String>> _resolveHospitalCandidates(User user, String role) async {
    final candidates = <String>[user.id];

    try {
      final staffByUser = await supabase
          .from('staff')
          .select('hospital_id')
          .eq('user_id', user.id)
          .maybeSingle();
      final hospitalId = staffByUser?['hospital_id']?.toString();
      if (hospitalId != null) candidates.add(hospitalId);
    } catch (_) {}

    if (user.email?.trim().isNotEmpty ?? false) {
      try {
        final staffByEmail = await supabase
            .from('staff')
            .select('hospital_id')
            .eq('email', user.email!.trim())
            .maybeSingle();
        final hospitalId = staffByEmail?['hospital_id']?.toString();
        if (hospitalId != null) candidates.add(hospitalId);
      } catch (_) {}
    }

    if (role != 'hospital' && role != 'clinic') {
      candidates.removeWhere((id) => id == user.id);
      candidates.insert(0, user.id);
    }

    return _uniqueNonEmpty(candidates);
  }

  Future<Map<String, dynamic>> _fetchLabDataForCandidates(List<String> candidateIds) async {
    if (candidateIds.isEmpty) {
      return {
        'resolvedId': null,
        'labTests': <Map<String, dynamic>>[],
        'appointments': <Map<String, dynamic>>[],
      };
    }

    final hospitalBatches = <List<Map<String, dynamic>>>[];
    for (final candidateId in candidateIds) {
      hospitalBatches.add(await _fetchLabTestsByHospitalId(candidateId));
    }
    var labTests = _mergeUniqueRows(hospitalBatches);

    if (labTests.isEmpty) {
      final providerBatches = <List<Map<String, dynamic>>>[];
      for (final candidateId in candidateIds) {
        providerBatches.add(await _fetchLabTestsByProviderId(candidateId));
      }
      labTests = _mergeUniqueRows(providerBatches);
    }

    final appointments = await _fetchUpcomingAppointments(candidateIds);
    final resolvedId =
        labTests.firstWhere(
          (row) => (row['hospital_id']?.toString().trim().isNotEmpty ?? false),
          orElse: () => appointments.isNotEmpty ? appointments.first : <String, dynamic>{},
        )['hospital_id']?.toString() ??
        (candidateIds.isNotEmpty ? candidateIds.first : null);

    return {
      'resolvedId': resolvedId,
      'labTests': labTests,
      'appointments': appointments,
    };
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


  Future<void> _loadHospitalAndInitStreams() async {
    if (mounted) {
      setState(() => _isRefreshing = true);
    }

    final user = await _waitForUser();
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _resolvedHospitalId = null;
        _labFuture = _emptyFuture();
        _nextAppointmentFuture = _emptyFuture();
        _isRefreshing = false;
      });
      return;
    }

    try {
      final profileRes = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final role = (profileRes?['role'] ?? '').toString().trim().toLowerCase();
      final candidateIds = await _resolveHospitalCandidates(user, role);
      final payload = await _fetchLabDataForCandidates(candidateIds);
      final labTests = List<Map<String, dynamic>>.from(payload['labTests'] as List);
      final upcomingAppointments = List<Map<String, dynamic>>.from(payload['appointments'] as List);
      final resolvedId = payload['resolvedId']?.toString();

      await _loadWorkingTimes(labTests);

      if (!mounted) return;
      setState(() {
        _resolvedHospitalId = resolvedId;
        _labFuture = Future.value(labTests);
        _nextAppointmentFuture = Future.value(upcomingAppointments);
        _isRefreshing = false;
      });
    } catch (e) {
      debugPrint('HospitalLab init error: $e');
      if (!mounted) return;
      setState(() {
        _resolvedHospitalId = null;
        _labFuture = _emptyFuture();
        _nextAppointmentFuture = _emptyFuture();
        _isRefreshing = false;
      });
    }
  }


  Future<List<Map<String, dynamic>>> _fetchLabTestsByHospitalId(String hospitalId) async {
    final data = await supabase
        .from('lab_tests')
        .select('id, name, price, category, description, bookings, provider_id, hospital_id, created_at, images')
        .eq('hospital_id', hospitalId)
        .order('created_at', ascending: false)
        .limit(120);
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchLabTestsByProviderId(String providerId) async {
    final data = await supabase
        .from('lab_tests')
        .select('id, name, price, category, description, bookings, provider_id, hospital_id, created_at, images')
        .eq('provider_id', providerId)
        .order('created_at', ascending: false)
        .limit(120);
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchUpcomingAppointments(List<String> hospitalIds) async {
    if (hospitalIds.isEmpty) return const [];

    final data = await supabase
        .from('lab_appointments')
        .select('id, patient_name, appointment_date, appointment_time, status, is_expired, hospital_id')
        .inFilter('hospital_id', hospitalIds)
        .not('status', 'in', '(cancelled,completed,failed,missed,expired)')
        .order('appointment_date', ascending: true)
        .order('appointment_time', ascending: true)
        .limit(60);

    final rows = (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((row) => !_shouldHideExpiredOrStaleScheduled(row))
        .take(20)
        .toList();

    return rows;
  }

  Future<void> _loadWorkingTimes(List<Map<String, dynamic>> tests) async {
    _workingTimeCache.clear();
    final testIds = tests
        .map((test) => test['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty && id != 'null')
        .toList();

    if (testIds.isEmpty) return;

    try {
      final assignmentRows = await supabase
          .from('lab_test_assignments')
          .select('lab_test_id, technician_id')
          .inFilter('lab_test_id', testIds)
          .eq('is_active', true);

      final technicianByTest = <String, String>{};
      final technicianIds = <String>{};
      for (final row in assignmentRows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final labTestId = map['lab_test_id']?.toString();
        final technicianId = map['technician_id']?.toString();
        if (labTestId == null || technicianId == null || technicianId.isEmpty) continue;
        technicianByTest.putIfAbsent(labTestId, () => technicianId);
        technicianIds.add(technicianId);
      }

      final timeByTechnician = <String, String>{};
      if (technicianIds.isNotEmpty) {
        final slotRows = await supabase
            .from('availability_slots')
            .select('provider_id, start_time, end_time, created_at')
            .inFilter('provider_id', technicianIds.toList())
            .order('created_at', ascending: false);

        for (final row in slotRows as List) {
          final map = Map<String, dynamic>.from(row as Map);
          final technicianId = map['provider_id']?.toString();
          if (technicianId == null || timeByTechnician.containsKey(technicianId)) continue;
          final start = DateTime.tryParse((map['start_time'] ?? '').toString())?.toLocal();
          final end = DateTime.tryParse((map['end_time'] ?? '').toString())?.toLocal();
          if (start == null || end == null) {
            timeByTechnician[technicianId] = 'Time N/A';
          } else {
            timeByTechnician[technicianId] = "${DateFormat.jm().format(start)} - ${DateFormat.jm().format(end)}";
          }
        }
      }

      for (final test in tests) {
        final labTestId = test['id']?.toString();
        if (labTestId == null || labTestId.isEmpty || labTestId == 'null') continue;
        final technicianId = technicianByTest[labTestId];
        if (technicianId == null) {
          _workingTimeCache[labTestId] = 'No technician assigned';
        } else {
          _workingTimeCache[labTestId] = timeByTechnician[technicianId] ?? 'No slots set';
        }
      }
    } catch (e) {
      for (final test in tests) {
        final labTestId = test['id']?.toString();
        if (labTestId != null && labTestId.isNotEmpty) {
          _workingTimeCache[labTestId] = 'Time N/A';
        }
      }
    }
  }

  Future<void> _refreshHospitalLab() async {
    await _loadHospitalAndInitStreams();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBg(context),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
                child: TextField(
                  onChanged: (val) => setState(() => searchQuery = val),
                  decoration: InputDecoration(
                    hintText: "Search lab tests...",
                    prefixIcon: Icon(Icons.search, color: AppColors.textMuted(context)),
                    filled: true,
                    fillColor: AppColors.inputFill(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'Refresh',
                      onPressed: _isRefreshing ? null : _refreshHospitalLab,
                      icon: _isRefreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.refresh_rounded, color: AppColors.textMuted(context)),
                    ),
                  ),
                ),
              ),
              if (_nextAppointmentFuture == null)
                const SizedBox.shrink()
              else
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _nextAppointmentFuture,
                  builder: (context, snapshot) {
                    final appointments = snapshot.data ?? const <Map<String, dynamic>>[];
                    final hasAppointment = appointments.isNotEmpty;
                    final appointment = hasAppointment ? appointments.first : null;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AllBookingsScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.indigo.withValues(alpha: 0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Colors.white24,
                                child: Icon(Icons.calendar_month,
                                    color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Next Appointment",
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 12),
                                    ),
                                    Text(
                                      hasAppointment
                                          ? (appointment?['patient_name']?.toString() ??
                                              "Unknown Patient")
                                          : "No Recent Appointments",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Text(
                                "View All",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              Expanded(
                child: _labFuture == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.domain_disabled_rounded,
                                size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              'No hospital linked',
                              style: TextStyle(
                                color: AppColors.textMuted(context),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : FutureBuilder<List<Map<String, dynamic>>>(
                        future: _labFuture,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(child: Text("Error: ${snapshot.error}"));
                          }
                          if (snapshot.connectionState == ConnectionState.waiting &&
                              !snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          final allTests = snapshot.data ?? const <Map<String, dynamic>>[];
                          final filteredTests = allTests
                              .where((test) => (test['name'] ?? '')
                                  .toString()
                                  .toLowerCase()
                                  .contains(searchQuery.toLowerCase()))
                              .toList();

                          if (allTests.isEmpty) {
                            return Center(
                              child: Text(
                                _resolvedHospitalId == null ? "No hospital linked." : "No lab tests found for this hospital.",
                                style: TextStyle(color: AppColors.textMuted(context)),
                              ),
                            );
                          }

                          final double totalRevenue = allTests.fold(
                            0.0,
                            (sum, item) {
                              final price = item['price'];
                              final bookings = item['bookings'];
                              final priceNum = price is num
                                  ? price
                                  : (num.tryParse(price?.toString() ?? '') ?? 0);
                              final bookingsNum = bookings is num
                                  ? bookings
                                  : (num.tryParse(bookings?.toString() ?? '') ?? 0);
                              return sum + (priceNum.toDouble() * bookingsNum.toDouble());
                            },
                          );

                          return RefreshIndicator(
                            onRefresh: _refreshHospitalLab,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildRevenueCard(totalRevenue, allTests),
                                const SizedBox(height: 24),
                                const Text(
                                  "Popular Lab Tests",
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 16),
                                filteredTests.isEmpty
                                    ? const Center(child: Text("No tests found"))
                                    : GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          crossAxisSpacing: 16,
                                          mainAxisSpacing: 16,
                                          childAspectRatio: 0.68,
                                        ),
                                        itemCount: filteredTests.length,
                                        itemBuilder: (context, index) {
                                          final test = filteredTests[index];
                                          return GestureDetector(
                                            onTap: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    LabTestDetailScreen(test: test),
                                              ),
                                            ),
                                            child: _buildLabCard(
                                              test,
                                              _getCardColor(index),
                                            ),
                                          );
                                        },
                                      ),
                                const SizedBox(height: 80),
                              ],
                            ),
                          ),
                          );
                        },
                      ),
              ),
            ],
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'hospital_lab_add',
              backgroundColor: const Color(0xFF6366F1),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NewLabScreen()),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 30),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueCard(double total, List<Map<String, dynamic>> tests) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Lab Revenue",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Icon(Icons.trending_up, color: Colors.green),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 100,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: tests
                        .asMap()
                        .entries
                        .map((e) {
                          final bookings = e.value['bookings'];
                          final bookingsNum = bookings is num
                              ? bookings
                              : (num.tryParse(bookings?.toString() ?? '') ?? 0);
                          return FlSpot(e.key.toDouble(), bookingsNum.toDouble());
                        })
                        .toList(),
                    isCurved: true,
                    color: const Color(0xFF6366F1),
                    barWidth: 3,
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Total Income",
                  style: TextStyle(color: AppColors.textMuted(context))),
              Text(
                "\$${total.toStringAsFixed(0)}",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLabCard(Map<String, dynamic> test, Color color) {
    final labTestId = test['id']?.toString();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  margin: const EdgeInsets.all(8),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: (test['images'] != null &&
                            test['images'] is List &&
                            test['images'].isNotEmpty)
                        ? Image.network(
                            test['images'][0],
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) => progress == null
                                ? child
                                : const ShimmerBox(
                                    width: double.infinity, height: 120),
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.textMuted(context),
                              size: 40,
                            ),
                          )
                        : const Icon(Icons.biotech, color: Colors.black26),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        AppColors.cardBg(context).withValues(alpha: 0.9),
                    child: IconButton(
                      icon: const Icon(Icons.edit,
                          size: 16, color: Color(0xFF6366F1)),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NewLabScreen(existingTest: test),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  test['name'] ?? "Unnamed",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                ),
                Text(
                  "\$${test['price'] ?? 0}",
                  style: const TextStyle(
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time,
                        size: 12, color: AppColors.textMuted(context)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        (labTestId == null || labTestId.isEmpty || labTestId == 'null')
                            ? 'Working time unavailable'
                            : (_workingTimeCache[labTestId] ?? 'Loading...'),
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted(context),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  "Bookings: ${test['bookings'] ?? 0}",
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getCardColor(int index) {
    final colors = [
      Colors.red[50]!,
      Colors.blue[50]!,
      Colors.purple[50]!,
      Colors.green[50]!,
    ];
    return colors[index % colors.length];
  }
}
