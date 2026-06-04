import 'package:flutter/material.dart';
import 'widgets/safe_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'consultation_description.dart';
import 'consultation_search.dart';
import 'booking_success_screen.dart';
import 'services/voice_service.dart';
import 'services/app_cache.dart';
import 'services/earliest_slot_service.dart';
import 'theme_colors.dart';

class ConsultationScreen extends StatefulWidget {
  final String patientId;
  const ConsultationScreen({super.key, required this.patientId});

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  final supabase = Supabase.instance.client;
  final VoiceService _voiceService = VoiceService();

  Map<String, dynamic>? selectedHospital;
  bool _speakerOn = false; // ← speaker must be explicitly turned on by user
  final Color primaryColor = const Color(0xFF6366F1);
  final Color emergencyRed = const Color(0xFFE11D48);

  @override
  void initState() {
    super.initState();
    _initializeVoiceAndSync();
  }

  Future<void> _initializeVoiceAndSync() async {
    try {
      await _voiceService.initTts();
      await _voiceService.loadSavedLanguage();

      if (!mounted) return;

      setState(() {});
    
    } catch (e) {
      debugPrint("Voice Init Error: $e");
    }
  }

  @override
  void dispose() {
    _voiceService.stop();
    super.dispose();
  }

  /// Plays screen-specific instructions — only fires if user has enabled speaker
  void _playInstructions() async {
    if (!_speakerOn) return;
    String text = "";
    final lang = _voiceService.currentLanguage;

    if (lang == VoiceService.nepali) {
      text = selectedHospital == null
          ? "कृपया पहिले अस्पताल छान्नुहोस्। त्यसपछि तपाईं डाक्टर वा फार्मासिस्टसँग परामर्श गर्न सक्नुहुन्छ।"
          : "तपाईंले ${selectedHospital!['name']} रोज्नुभएको छ। अब विशेषज्ञ डाक्टर वा फार्मासिस्ट छान्न सक्नुहुन्छ।";
    } else if (lang == VoiceService.hindi) {
      text = selectedHospital == null
          ? "कृपया पहले अस्पताल चुनें। उसके बाद आप डॉक्टर या फार्मासिस्ट से सलाह ले सकते हैं।"
          : "आपने ${selectedHospital!['name']} चुना है। अब आप विशेषज्ञ डॉक्टर या फार्मासिस्ट चुन सकते हैं।";
    } else {
      text = selectedHospital == null
          ? "Please choose a hospital first. Then you can consult with doctors or pharmacists."
          : "You have selected ${selectedHospital!['name']}. You can now choose a specialist or pharmacist.";
    }

    await _voiceService.speakWithSavedLanguage(text);
  }

  void _navigateToSearch({String? initialRole}) {
    _voiceService.stop();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConsultationSearch(
          preSelectedHospital: selectedHospital,
          initialRoleFilter: initialRole,
          filter: initialRole,
        ),
      ),
    );
  }

  Future<void> _sendEmergencyRequest(String label) async {
    try {
      await supabase.from('consultation_requests').insert({
        'patient_id': widget.patientId,
        'hospital_id': selectedHospital?['id'],
        'request_type': 'EMERGENCY',
        'target_name': label,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
      _showSnackBar("Emergency Alert sent for $label!");
    } catch (e) {
      _showSnackBar("Failed: $e");
    }
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: primaryColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      floatingActionButton: FloatingActionButton(
        heroTag: 'consultation_accessibility',
        onPressed: () {
          setState(() => _speakerOn = !_speakerOn);
          if (_speakerOn) {
            // First tap: turn on and immediately read the current screen state
            _playInstructions();
          } else {
            // Second tap: turn off and stop any ongoing speech
            _voiceService.stop();
          }
        },
        backgroundColor: _speakerOn ? Colors.red : primaryColor,
        tooltip: _speakerOn ? 'Speaker ON – tap to turn off' : 'Tap to enable voice guidance',
        child: Icon(
          _speakerOn ? Icons.volume_up : Icons.volume_off,
          color: Colors.white,
        ),
      ),
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(), // No bounce — prevents glitch on content load
        slivers: [
          SliverAppBar(
            automaticallyImplyLeading: false,
            floating: true,
            expandedHeight: 90,
            backgroundColor: AppColors.cardBg(context),
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.fromLTRB(16, 50, 16, 0),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => _navigateToSearch(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceBg(context),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded, color: primaryColor),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                selectedHospital != null
                                    ? "Search in ${selectedHospital!['name']}..."
                                    : "Search doctors or hospitals...",
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 10),
              _buildYourBookingsSection(),
              _buildSectionWrapper(
                title: "1. Choose Hospital",
                child: _buildHospitalGrid(),
              ),
              if (selectedHospital != null) ...[
                _buildSectionWrapper(
                  title: "2. Specialists",
                  onViewAll: () => _navigateToSearch(initialRole: 'doctor'),
                  child: _buildStaffGrid(role: 'doctor'),
                ),
                _buildSectionWrapper(
                  title: "3. Pharmacists",
                  onViewAll: () => _navigateToSearch(initialRole: 'pharmacist'),
                  child: _buildStaffGrid(role: 'pharmacist'),
                ),
              ] else
                _buildEmptyState("Please select a hospital to view available staff"),
              _buildSectionWrapper(
                title: "4. Instant Help",
                titleColor: emergencyRed,
                child: _buildEmergencyGrid(),
              ),
              const SizedBox(height: 100),
            ]),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchYourBookings() async {
    final user = supabase.auth.currentUser;
    if (user == null) return <Map<String, dynamic>>[];

    final data = await supabase
        .from('bookings')
        .select(
          'id, provider_id, doctor_name, doctor_speciality, doctor_avatar, '
          'appointment_date, appointment_time, type, queue_number, status, is_expired',
        )
        .eq('user_id', user.id)
        .order('appointment_date', ascending: true)
        .limit(10);
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((b) {
          final status = (b['status'] ?? '').toString().toLowerCase();
          final isExpired = b['is_expired'] == true;
          return !isExpired &&
              status != 'completed' &&
              status != 'cancelled' &&
              status != 'failed' &&
              status != 'missed';
        })
        .toList();
  }

  Widget _buildYourBookingsSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchYourBookings(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();

        final activeBookings = snapshot.data!;

        if (activeBookings.isEmpty) return const SizedBox.shrink();
        final booking = activeBookings.first; // safe: isEmpty checked above

        return _buildSectionWrapper(
          title: "Active Appointment",
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              onTap: () {
                _voiceService.stop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BookingSuccessScreen(
                      bookingId: booking['id'].toString(),
                      appointmentDate: DateTime.parse(booking['appointment_date']),
                      appointmentTime: booking['appointment_time'] ?? "",
                      appointmentType: booking['type'] ?? "Video Call",
                      queueNumber: booking['queue_number'] ?? 0,
                      doctorData: {
                        'id': booking['provider_id'],
                        'full_name': booking['doctor_name'] ?? "Medical Specialist",
                        'speciality': booking['doctor_speciality'] ?? "",
                        'avatar_url': booking['doctor_avatar'],
                      },
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.calendar_today, color: Colors.white),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            booking['doctor_name'] ?? "Consultation",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            "${booking['appointment_date']} • ${booking['appointment_time']}",
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionWrapper({
    required String title,
    required Widget child,
    Color? titleColor,
    VoidCallback? onViewAll,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(color: AppColors.cardBg(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(title, color: titleColor, onViewAll: onViewAll),
          child,
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {Color? color, VoidCallback? onViewAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: color ?? const Color(0xFF1E293B),
              letterSpacing: -0.5,
            ),
          ),
          if (onViewAll != null)
            TextButton(
              onPressed: onViewAll,
              child: Text("View All", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Future<List> _fetchHospitalsCached() async {
    const key = 'hospitals_list';
    final cached = AppCache.get<List>(key);
    if (cached != null) return cached;
    final data = await supabase
        .from('hospitals')
        .select('id, name, location, avatar_url, rating');
    AppCache.set(key, data, ttl: const Duration(minutes: 10));
    return data;
  }

  /// Fetches staff + all their profiles in exactly 2 queries (no N+1).
  Future<Map<String, dynamic>> _fetchStaffWithProfiles(
      String hospitalId, String role) async {
    final response = await supabase.rpc(
      'get_public_staff_directory',
      params: {
        'p_role': role,
        'p_hospital_id': hospitalId,
        'p_provider_ids': null,
        'p_search': null,
        'p_limit': 4,
      },
    );

    final staffList = (response is List ? response : <dynamic>[])
        .map<Map<String, dynamic>>((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final fullName = (row['full_name'] ?? row['name'] ?? 'Medical Staff')
          .toString();
      return <String, dynamic>{
        ...row,
        'name': fullName,
        'hospitalName': row['hospital_name'],
        'first_consultation_fee': row['first_consultation_fee'],
        'followup_consultation_fee': row['followup_consultation_fee'],
      };
    }).toList();

    return {'staff': staffList, 'profiles': <String, dynamic>{}};
  }

  Widget _buildHospitalGrid() {
    return FutureBuilder(
      future: _fetchHospitalsCached(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // Fixed height skeleton — prevents layout jump when real cards load
          return SizedBox(
            height: 340,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 0),
              child: Wrap(
                spacing: 15,
                runSpacing: 45,
                children: List.generate(4, (_) => SizedBox(
                  width: (MediaQuery.of(context).size.width - 47) / 2,
                  child: const DoctorCardSkeleton(),
                )),
              ),
            ),
          );
        }
        final hospitals = snapshot.data as List;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 40, 16, 0),
          child: Wrap(
            spacing: 15,
            runSpacing: 45,
            alignment: WrapAlignment.center,
            children: hospitals.map((h) {
              bool isSelected = selectedHospital?['id'] == h['id'];
              return SizedBox(
                width: (MediaQuery.of(context).size.width - 47) / 2,
                child: GestureDetector(
                  onTap: () {
                    _voiceService.stop();
                    setState(() => selectedHospital = h);
                    // Only announce if the user has explicitly turned speaker ON
                    if (_speakerOn) {
                      _voiceService.speakWithSavedLanguage("Hospital ${h['name']} selected.");
                    }
                  },
                  child: _buildSquareBaseCard(
                    title: h['name'] ?? 'Hospital',
                    subtitle: h['location'] ?? 'Location',
                    imageUrl: h['avatar_url'],
                    rating: (h['rating'] ?? 5.0).toDouble(),
                    isSelected: isSelected,
                    isHospital: true,
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // ── Earliest available slot helpers ──────────────────────────────────────

  /// Returns a human label like "Today 9 AM", "Tomorrow 2 PM", "Wed 10 AM"
  /// Checks up to 7 days ahead. Returns null if nothing found.
  Future<String?> _fetchEarliestSlot(String doctorId) =>
      fetchEarliestSlot(supabase, doctorId);

  /// Small green "Next available" chip — uses existing card space, not bulky
  Widget _buildNextSlotChip(String doctorId) {
    return FutureBuilder<String?>(
      future: _fetchEarliestSlot(doctorId),
      builder: (context, snap) {
        if (!snap.hasData || snap.data == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(top: 5),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.greenTint(context),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.access_time_rounded, size: 9, color: Color(0xFF10B981)),
              const SizedBox(width: 3),
              Text(
                snap.data!,
                style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStaffGrid({required String role}) {
    final hospitalId = selectedHospital!['id'].toString();
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchStaffWithProfiles(hospitalId, role),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(
            height: 380,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 45, 16, 0),
              child: Wrap(
                spacing: 15,
                runSpacing: 50,
                alignment: WrapAlignment.center,
                children: List.generate(4, (_) => SizedBox(
                  width: (MediaQuery.of(context).size.width - 47) / 2,
                  child: const DoctorCardSkeleton(),
                )),
              ),
            ),
          );
        }
        final staffList = (snapshot.data!['staff'] as List?) ?? [];
        final profileMap = snapshot.data!['profiles'] is Map
            ? Map<String, dynamic>.from(snapshot.data!['profiles'] as Map)
            : <String, dynamic>{};
        if (staffList.isEmpty) return _buildEmptyState("No ${role}s found.");

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 45, 16, 0),
          child: Wrap(
            spacing: 15,
            runSpacing: 50,
            alignment: WrapAlignment.center,
            children: staffList.map((s) {
              final profile =
                  profileMap[s['id'].toString()] as Map? ?? {};
              final String name =
                  profile['full_name'] ?? s['name'] ?? 'Medical Staff';
              final String? img =
                  profile['avatar_url'] ?? s['avatar_url'];
              return SizedBox(
                width: (MediaQuery.of(context).size.width - 47) / 2,
                child: _buildSquareBaseCard(
                  doctorId: s['id'].toString(),
                  title: name,
                  subtitle: s['speciality'] ?? s['role'] ?? role,
                  imageUrl: img,
                  rating: (s['rating'] ?? 4.5).toDouble(),
                  firstFee: s['first_consultation_fee'],
                  followUpFee: s['followup_consultation_fee'],
                  onTap: () {
                    _voiceService.stop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ConsultationDescription(
                          doctorData: {
                            ...s,
                            'name': name,
                            'avatar_url': img,
                            'hospitalName': selectedHospital!['name'],
                            'firstPrice':
                                (s['first_consultation_fee'] ?? 0).toDouble(),
                            'followUpPrice':
                                (s['followup_consultation_fee'] ?? 0)
                                    .toDouble(),
                            'rating': (s['rating'] ?? 4.5).toDouble(),
                          },
                        ),
                      ),
                    );
                  },
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildSquareBaseCard({
    required String title,
    required String subtitle,
    String? imageUrl,
    required double rating,
    dynamic firstFee,
    dynamic followUpFee,
    bool isSelected = false,
    bool isHospital = false,
    String? doctorId,         // ← new: used to show earliest available slot
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 48, 12, 12),
            decoration: BoxDecoration(
              color: isSelected ? primaryColor.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? primaryColor : const Color(0xFFE2E8F0), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(subtitle.toUpperCase(), style: TextStyle(color: primaryColor, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                  Text(rating.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ]),
                // Earliest available slot chip — compact, uses spare space
                if (!isHospital && doctorId != null)
                  _buildNextSlotChip(doctorId),
                if (!isHospital) ...[
                  const Divider(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _buildFeeInfo("1st", firstFee),
                    _buildFeeInfo("Follow", followUpFee),
                  ]),
                ]
              ],
            ),
          ),
          Positioned(
            top: -35,
            left: 0,
            right: 0,
            child: Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xFFE2E8F0),
                child: ClipOval(
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          width: 72,
                          height: 72,
                          loadingBuilder: (_, child, progress) =>
                              progress == null ? child : const ShimmerBox(width: 72, height: 72, borderRadius: 36),
                          errorBuilder: (context, error, stackTrace) =>
                              Text(title[0], style: const TextStyle(fontSize: 20)),
                        )
                      : Text(title[0], style: const TextStyle(fontSize: 20)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeeInfo(String label, dynamic value) {
    return Column(children: [
      Text(label, style: TextStyle(fontSize: 9, color: AppColors.textMuted(context))),
      Text("Rs ${value ?? '0'}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
    ]);
  }

  Widget _buildEmergencyGrid() {
    final List<Map<String, dynamic>> items = [
      {"label": "Ambulance", "icon": Icons.airport_shuttle},
      {"label": "Trauma ER", "icon": Icons.healing},
      {"label": "Cardiac", "icon": Icons.favorite},
      {"label": "ICU", "icon": Icons.monitor_heart},
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 2.8, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: items.length,
      itemBuilder: (context, index) => InkWell(
        onTap: () => _sendEmergencyRequest(items[index]['label']),
        child: Container(
          decoration: BoxDecoration(color: AppColors.redTint(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: emergencyRed.withValues(alpha: 0.2))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(items[index]['icon'], color: emergencyRed, size: 18),
            const SizedBox(width: 8),
            Text(items[index]['label'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Text(msg, style: TextStyle(color: AppColors.textMuted(context)))));
  }
}