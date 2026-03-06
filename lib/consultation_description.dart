import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'consultation_booking.dart';
import 'patient_settings.dart'; 
import 'services/voice_service.dart';

class ConsultationDescription extends StatefulWidget {
  final Map<String, dynamic> doctorData;

  const ConsultationDescription({super.key, required this.doctorData});

  @override
  State<ConsultationDescription> createState() =>
      _ConsultationDescriptionState();
}

class _ConsultationDescriptionState extends State<ConsultationDescription> {
  final supabase = Supabase.instance.client;
  final Color primaryColor = const Color(0xFF6366F1);
  final Color accentColor = const Color(0xFF10B981);
  final VoiceService _voiceService = VoiceService();

  @override
  void initState() {
    super.initState();
    _voiceService.initTts();
  }

  @override
  void dispose() {
    // CRITICAL FIX: Stops the voice immediately when leaving the screen
    _voiceService.stop();
    super.dispose();
  }

  void _speakDoctorDetails(String name, String license, String bio) {
    // Stop any current speech before starting new speech to prevent overlapping
    _voiceService.stop(); 
    String text = "Doctor $name. License Number $license. $bio";
    _voiceService.speakWithSavedLanguage(text);
  }

  /// Handles the shared device logic before navigating to booking
  Future<void> _handleBookingNavigation(
      String type, double price, String nurseName) async {
    // Stop speaking when user starts the booking process
    _voiceService.stop();

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please login to book an appointment")),
      );
      return;
    }

    try {
      final currentUserProfile = await supabase
          .from('profiles')
          .select('full_name, id')
          .eq('id', user.id)
          .single();

      final response = await supabase.from('profiles').select('id');
      final bool isSharedDevice = response.length > 1;

      if (!mounted) return;

      if (isSharedDevice) {
        bool? confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Confirm Patient Profile"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("You are booking this appointment for:"),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: primaryColor,
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentUserProfile['full_name'] ?? "User",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              "Profile ID: ${currentUserProfile['id'].toString().substring(0, 8)}",
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Not you?",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context, false);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PatientSettings()),
                    );
                  },
                  icon: const Icon(Icons.switch_account, size: 18),
                  label: const Text("Switch account in Settings"),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: Colors.redAccent,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Yes, Proceed",
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );

        if (confirm != true) return;
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BookingScreen(
            doctorData: {
              ...widget.doctorData,
              'nurse_assigned': nurseName,
            },
            appointmentType: type,
            price: price,
          ),
        ),
      );
    } catch (e) {
      debugPrint("Booking Navigation Error: $e");
    }
  }

  Future<Map<String, dynamic>> _getDoctorFullDetails() async {
    final doctorId = widget.doctorData['id'].toString();

    final docProfile = await supabase
        .from('profiles')
        .select('full_name, license_number, bio')
        .eq('id', doctorId)
        .single();

    String nurseName = "None Assigned";
    
    try {
      final assignment = await supabase
          .from('staff_assignments_view')
          .select('nurse_name')
          .eq('doctor_id', doctorId)
          .maybeSingle();

      if (assignment != null && assignment['nurse_name'] != null) {
        nurseName = assignment['nurse_name'];
      }
    } catch (e) {
      debugPrint("Nurse View Fetch Error: $e");
    }

    return {
      'full_name': docProfile['full_name'],
      'license_number': docProfile['license_number'],
      'bio': docProfile['bio'],
      'nurse_name': nurseName,
    };
  }

  @override
  Widget build(BuildContext context) {
    final staticDoc = widget.doctorData;

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FutureBuilder<Map<String, dynamic>>(
        future: _getDoctorFullDetails(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          return FloatingActionButton(
            backgroundColor: primaryColor,
            onPressed: () => _speakDoctorDetails(
              snapshot.data?['full_name'] ?? "Doctor",
              snapshot.data?['license_number'] ?? "",
              snapshot.data?['bio'] ?? "",
            ),
            child: const Icon(Icons.volume_up, color: Colors.white),
          );
        },
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _getDoctorFullDetails(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final liveData = snapshot.data ?? {};
          final name = liveData['full_name'] ?? staticDoc['full_name'] ?? "Doctor";
          final license = liveData['license_number'] ?? "N/A";
          final bio = liveData['bio'] ?? "Professional clinical excellence.";
          final nurse = liveData['nurse_name'] ?? "None Assigned";

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 250,
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    _voiceService.stop(); // Stop voice when back button pressed
                    Navigator.pop(context);
                  },
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        staticDoc['avatar_url'] ?? 'https://via.placeholder.com/400',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.person, size: 80)),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.6)
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold)),
                                Text("License No: $license",
                                    style: const TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                          _buildHospitalRating(
                              staticDoc['hospital_rating']?.toDouble() ?? 4.7),
                        ],
                      ),
                      const SizedBox(height: 15),
                      _buildBadgeRow(staticDoc['speciality'] ?? "General",
                          staticDoc['hospitalName'] ?? "Hospital"),
                      const Divider(height: 40),
                      _buildInfoCard(
                        title: "Medical Staff Today",
                        content: "Assigned Nurse: $nurse",
                        icon: Icons.person_add_alt_1,
                        color: Colors.blue.shade50,
                      ),
                      const SizedBox(height: 20),
                      const Text("Education & History",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(bio,
                          style: TextStyle(
                              color: Colors.grey.shade700, height: 1.5)),
                      const SizedBox(height: 30),
                      _buildPricingSection(
                          "First Time Consultation",
                          (staticDoc['first_consultation_fee'] as num? ?? 0)
                              .toDouble(),
                          nurse),
                      const SizedBox(height: 20),
                      _buildPricingSection(
                          "Follow-up Consultation",
                          (staticDoc['followup_consultation_fee'] as num? ?? 0)
                              .toDouble(),
                          nurse),
                      const SizedBox(height: 30),
                      const Text("Patient Reviews",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      _buildRealTimeReviews(staticDoc['id'].toString()),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPricingSection(String title, double price, String nurseName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text("Rs ${price.toInt()}",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: accentColor)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _bookingButton("Physical", Icons.location_on,
                    Colors.blue, price, nurseName)),
            const SizedBox(width: 10),
            Expanded(
                child: _bookingButton(
                    "Online", Icons.videocam, primaryColor, price, nurseName)),
          ],
        ),
      ],
    );
  }

  Widget _bookingButton(String label, IconData icon, Color color, double price,
      String nurseName) {
    return ElevatedButton.icon(
      onPressed: () => _handleBookingNavigation(label, price, nurseName),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildBadgeRow(String specialty, String hospital) {
    return Wrap(
      spacing: 8,
      children: [
        Chip(
            label: Text(specialty),
            backgroundColor: primaryColor.withValues(alpha: 0.1),
            labelStyle: TextStyle(color: primaryColor)),
        Chip(
            label: Text(hospital),
            backgroundColor: Colors.grey.withValues(alpha: 0.1)),
      ],
    );
  }

  Widget _buildHospitalRating(double rating) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: Colors.amber.shade100,
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        const Icon(Icons.star, color: Colors.amber, size: 18),
        const SizedBox(width: 4),
        Text(rating.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold))
      ]),
    );
  }

  Widget _buildInfoCard(
      {required String title,
      required String content,
      required IconData icon,
      required Color color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)),
      child: Row(children: [
        Icon(icon, color: Colors.blue.shade700),
        const SizedBox(width: 15),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey)),
          Text(content,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ]),
      ]),
    );
  }

  Widget _buildRealTimeReviews(String doctorId) {
    return StreamBuilder(
      stream: supabase
          .from('reviews')
          .stream(primaryKey: ['id']).eq('doctor_id', doctorId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final reviews = snapshot.data as List;
        if (reviews.isEmpty) return const Text("No reviews yet.");
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: reviews.length,
          itemBuilder: (context, index) {
            final r = reviews[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(r['user_name']?[0] ?? "U")),
              title: Text(r['user_name'] ?? "Anonymous",
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(r['comment'] ?? ""),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star, size: 14, color: Colors.amber),
                const SizedBox(width: 4),
                Text(r['rating'].toString())
              ]),
            );
          },
        );
      },
    );
  }
}