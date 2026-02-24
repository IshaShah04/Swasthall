import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'consultation_description.dart';
import 'consultation_search.dart';
import 'booking_success_screen.dart'; 
import 'services/voice_service.dart'; // Import your singleton service

class ConsultationScreen extends StatefulWidget {
  final String patientId;
  const ConsultationScreen({super.key, required this.patientId});

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  final supabase = Supabase.instance.client;
  final VoiceService _voiceService = VoiceService(); // Access existing service

  Map<String, dynamic>? selectedHospital;
  final Color primaryColor = const Color(0xFF6366F1);
  final Color emergencyRed = const Color(0xFFE11D48);

  @override
  void initState() {
    super.initState();
    // No need to re-init TTS if already done at Home, but safe for iOS
    _voiceService.initTts();
  }

  /// Plays screen-specific instructions in the pre-selected language
  void _playInstructions() async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      // Floating Speaker Button for Voice Help
      floatingActionButton: FloatingActionButton(
        onPressed: _playInstructions,
        backgroundColor: primaryColor,
        child: const Icon(Icons.volume_up, color: Colors.white),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            automaticallyImplyLeading: false,
            floating: true,
            expandedHeight: 90,
            backgroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.fromLTRB(16, 50, 16, 0),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => _navigateToSearch(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
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
                                style: const TextStyle(
                                    color: Color(0xFF64748B), fontSize: 14),
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

              // SECTION 1: HOSPITALS
              _buildSectionWrapper(
                title: "1. Choose Hospital",
                child: _buildHospitalGrid(),
              ),

              // SECTION 2 & 3: STAFF
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
                _buildEmptyState(
                    "Please select a hospital to view available staff"),

              // SECTION 4: EMERGENCY
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

  Widget _buildYourBookingsSection() {
  return StreamBuilder<List<Map<String, dynamic>>>(
    stream: supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('user_id', supabase.auth.currentUser?.id ?? '') // Changed patient_id to user_id to match Payment Screen logic
        .order('appointment_date', ascending: true),
    builder: (context, snapshot) {
      if (!snapshot.hasData || snapshot.data!.isEmpty) {
        return const SizedBox.shrink();
      }

      final activeBookings = snapshot.data!
          .where((b) => b['status'] != 'completed' && b['status'] != 'cancelled')
          .toList();

      if (activeBookings.isEmpty) return const SizedBox.shrink();

      final booking = activeBookings.first;
      
      return _buildSectionWrapper(
        title: "Active Appointment",
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BookingSuccessScreen(
                    bookingId: booking['id'].toString(),
                    appointmentDate: DateTime.parse(booking['appointment_date']),
                    appointmentTime: booking['appointment_time'] ?? "",
                    appointmentType: booking['type'] ?? "Video Call", // 'type' is used in Payment Screen
                    queueNumber: booking['queue_number'] ?? 0, // SYNC FIX: Pass the real queue number
                    doctorData: {
                      'id': booking['provider_id'],
                      'full_name': booking['doctor_name'] ?? "Medical Specialist", // Matching key 'full_name'
                      'speciality': booking['doctor_speciality'] ?? "",
                      'avatar_url': booking['doctor_avatar'], // Ensure this is stored in your booking table
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
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                        Text(
                          "${booking['appointment_date']} • ${booking['appointment_time']}",
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
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
      decoration: const BoxDecoration(color: Colors.white),
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

  Widget _buildHospitalGrid() {
    return FutureBuilder(
      future: supabase.from('hospitals').select('id, name, location, avatar_url, rating'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
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
                    setState(() => selectedHospital = h);
                    _voiceService.speakWithSavedLanguage("Hospital ${h['name']} selected.");
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

  Widget _buildStaffGrid({required String role}) {
    final hospitalId = selectedHospital!['id'].toString();
    return FutureBuilder(
      future: supabase.from('staff').select('*').eq('hospital_id', hospitalId).ilike('role', '%$role%').limit(4),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final staffList = snapshot.data as List?;
        if (staffList == null || staffList.isEmpty) return _buildEmptyState("No ${role}s found.");

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 45, 16, 0),
          child: Wrap(
            spacing: 15,
            runSpacing: 50,
            alignment: WrapAlignment.center,
            children: staffList.map((s) {
              return FutureBuilder(
                future: supabase.from('profiles').select('full_name, avatar_url').eq('id', s['id']).maybeSingle(),
                builder: (context, profileSnapshot) {
                  final profile = profileSnapshot.data;
                  final String name = profile?['full_name'] ?? s['name'] ?? 'Medical Staff';
                  final String? img = profile?['avatar_url'] ?? s['avatar_url'];

                  return SizedBox(
                    width: (MediaQuery.of(context).size.width - 47) / 2,
                    child: _buildSquareBaseCard(
                      title: name,
                      subtitle: s['speciality'] ?? s['role'] ?? role,
                      imageUrl: img,
                      rating: (s['rating'] ?? 4.5).toDouble(),
                      firstFee: s['first_consultation_fee'],
                      followUpFee: s['followup_consultation_fee'],
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ConsultationDescription(
                              doctorData: {
                                ...s,
                                'name': name,
                                'avatar_url': img,
                                'hospitalName': selectedHospital!['name'],
                                'firstPrice': (s['first_consultation_fee'] ?? 0).toDouble(),
                                'followUpPrice': (s['followup_consultation_fee'] ?? 0).toDouble(),
                                'rating': (s['rating'] ?? 4.5).toDouble(),
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
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
            top: -38, left: 0, right: 0,
            child: Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xFFF1F5F9),
                backgroundImage: imageUrl != null && imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                child: imageUrl == null ? Text(title[0]) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeeInfo(String label, dynamic value) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
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
          decoration: BoxDecoration(color: const Color(0xFFFFF1F2), borderRadius: BorderRadius.circular(12), border: Border.all(color: emergencyRed.withValues(alpha: 0.2))),
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
    return Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Text(msg, style: const TextStyle(color: Colors.grey))));
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: primaryColor, behavior: SnackBarBehavior.floating));
  }
}