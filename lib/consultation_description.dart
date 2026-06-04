import 'package:flutter/material.dart';
import 'widgets/safe_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'consultation_booking.dart';
import 'patient_settings.dart';
import 'services/voice_service.dart';
import 'services/earliest_slot_service.dart';
import 'theme_colors.dart';

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

  Future<Map<String, dynamic>>? _detailsFuture;
  Future<String?>? _earliestSlotFuture;
  Future<List<Map<String, dynamic>>>? _reviewsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _getDoctorFullDetails();
    _earliestSlotFuture =
        fetchEarliestSlot(supabase, widget.doctorData['id'].toString());
    _reviewsFuture = _fetchReviews(widget.doctorData['id'].toString());
    _voiceService.initTts();
  }

  @override
  void dispose() {
    _voiceService.stop();
    super.dispose();
  }

  void _refreshDetails() {
    if (!mounted) return;
    setState(() {
      _detailsFuture = _getDoctorFullDetails();
      _earliestSlotFuture =
          fetchEarliestSlot(supabase, widget.doctorData['id'].toString());
      _reviewsFuture = _fetchReviews(widget.doctorData['id'].toString());
    });
  }

  void _speakDoctorDetails(String name, String license, String bio) {
    _voiceService.stop();
    final text = "Doctor $name. License Number $license. $bio";
    _voiceService.speakWithSavedLanguage(text);
  }

  Future<bool> _confirmProfileBeforeBooking(
    Map<String, dynamic> currentUserProfile,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
                color: const Color(0xFFF1F5F9),
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
                          currentUserProfile['full_name']?.toString() ?? "User",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          "Profile ID: ${(currentUserProfile['id'] ?? '').toString().padRight(8, '0').substring(0, 8)}",
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted(context),
                          ),
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
                Navigator.pop(dialogContext, false);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PatientSettings(),
                  ),
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
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Yes, Proceed",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    return confirm == true;
  }

  Future<void> _handleBookingNavigation(
    String type,
    double price,
    String nurseName,
  ) async {
    _voiceService.stop();

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final user = supabase.auth.currentUser;
    if (user == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Please login to book an appointment")),
      );
      return;
    }

    try {
      final currentUserProfile = await supabase
          .from('profiles')
          .select('full_name, id')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (currentUserProfile == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Your profile could not be loaded.")),
        );
        return;
      }

      final confirmed = await _confirmProfileBeforeBooking(currentUserProfile);
      if (!mounted || !confirmed) return;

      navigator.push(
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
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Unable to proceed with booking. Please try again."),
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _getDoctorFullDetails() async {
    final doctorId = widget.doctorData['id'].toString();
    String nurseName = "None Assigned";

    Map<String, dynamic>? publicProfile;
    try {
      final response = await supabase.rpc(
        'get_public_staff_directory',
        params: {
          'p_role': null,
          'p_hospital_id': null,
          'p_provider_ids': [doctorId],
          'p_search': null,
          'p_limit': 1,
        },
      );

      if (response is List && response.isNotEmpty) {
        publicProfile = Map<String, dynamic>.from(response.first as Map);
      }
    } catch (e) {
      debugPrint("Public doctor detail fetch error: $e");
    }

    // Staff assignment details are not public. Fetch only after login.
    try {
      if (supabase.auth.currentUser != null) {
        final assignment = await supabase
            .from('staff_assignments_view')
            .select('nurse_name')
            .eq('doctor_id', doctorId)
            .maybeSingle();

        if (assignment != null && assignment['nurse_name'] != null) {
          nurseName = assignment['nurse_name'].toString();
        }
      }
    } catch (e) {
      debugPrint("Doctor assignment fetch skipped/blocked: $e");
    }

    return {
      'full_name': publicProfile?['full_name'] ??
          widget.doctorData['full_name'] ??
          widget.doctorData['name'] ??
          'Doctor',
      'license_number': publicProfile?['license_number'] ??
          widget.doctorData['license_number'] ??
          '',
      'bio': publicProfile?['bio'] ?? widget.doctorData['bio'] ?? '',
      'nurse_name': nurseName,
    };
  }

  Future<List<Map<String, dynamic>>> _fetchReviews(
    String doctorId, {
    int limit = 20,
  }) async {
    final data = await supabase
        .from('reviews')
        .select()
        .eq('doctor_id', doctorId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final staticDoc = widget.doctorData;

    return Scaffold(
      backgroundColor: AppColors.cardBg(context),
      floatingActionButton: FutureBuilder<Map<String, dynamic>>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          return FloatingActionButton(
            heroTag: 'consultation_desc_tts',
            backgroundColor: primaryColor,
            onPressed: () => _speakDoctorDetails(
              snapshot.data?['full_name']?.toString() ?? "Doctor",
              snapshot.data?['license_number']?.toString() ?? "",
              snapshot.data?['bio']?.toString() ?? "",
            ),
            child: const Icon(Icons.volume_up, color: Colors.white),
          );
        },
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Failed to load doctor details'),
                  TextButton(
                    onPressed: _refreshDetails,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final liveData = snapshot.data ?? {};
          final name = liveData['full_name'] ??
              staticDoc['full_name'] ??
              staticDoc['name'] ??
              "Doctor";
          final license = liveData['license_number'] ?? "N/A";
          final bio = liveData['bio']?.toString().isNotEmpty == true
              ? liveData['bio'].toString()
              : "Professional clinical excellence.";
          final nurse = liveData['nurse_name'] ?? "None Assigned";

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 250,
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    _voiceService.stop();
                    Navigator.pop(context);
                  },
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        staticDoc['avatar_url'] ??
                            'https://via.placeholder.com/400',
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) => progress == null
                            ? child
                            : const ShimmerBox(
                                width: double.infinity,
                                height: 300,
                              ),
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: const Color(0xFFE2E8F0),
                          child: const Icon(Icons.person, size: 80),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.6),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.toString(),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  "License No: $license",
                                  style: TextStyle(
                                    color: AppColors.textMuted(context),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildHospitalRating(
                            ((staticDoc['hospital_rating'] ?? 4.7) as num)
                                .toDouble(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      _buildBadgeRow(
                        staticDoc['speciality']?.toString() ?? "General",
                        staticDoc['hospitalName']?.toString() ?? "Hospital",
                      ),
                      const Divider(height: 40),
                      _buildInfoCard(
                        title: "Medical Staff Today",
                        content: "Assigned Nurse: $nurse",
                        icon: Icons.person_add_alt_1,
                        color: Colors.blue.shade50,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Education & History",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bio.toString(),
                        style: const TextStyle(
                          color: Color(0xFF334155),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 30),
                      _buildPricingSection(
                        "First Time Consultation",
                        ((staticDoc['first_consultation_fee'] ?? 0) as num)
                            .toDouble(),
                        nurse.toString(),
                      ),
                      const SizedBox(height: 20),
                      _buildPricingSection(
                        "Follow-up Consultation",
                        ((staticDoc['followup_consultation_fee'] ?? 0) as num)
                            .toDouble(),
                        nurse.toString(),
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        "Patient Reviews",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      _buildRealTimeReviews(),
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
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              "Rs ${price.toInt()}",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<String?>(
          future: _earliestSlotFuture,
          builder: (context, snap) {
            if (!snap.hasData || snap.data == null) {
              return const SizedBox.shrink();
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.greenTint(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: Color(0xFF10B981),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Next available: ${snap.data!}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Row(
          children: [
            Expanded(
              child: _bookingButton(
                "Physical",
                Icons.location_on,
                Colors.blue,
                price,
                nurseName,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _bookingButton(
                "Online",
                Icons.videocam,
                primaryColor,
                price,
                nurseName,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bookingButton(
    String type,
    IconData icon,
    Color color,
    double price,
    String nurseName,
  ) {
    return ElevatedButton.icon(
      onPressed: () => _handleBookingNavigation(type, price, nurseName),
      icon: Icon(icon, color: Colors.white, size: 18),
      label: Text(type, style: const TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildHospitalRating(double rating) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeRow(String speciality, String hospital) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _badge(Icons.medical_information_outlined, speciality),
        _badge(Icons.local_hospital_outlined, hospital),
      ],
    );
  }

  Widget _badge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceBg(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: primaryColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String content,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(icon, color: primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(content),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealTimeReviews() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _reviewsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: TextButton.icon(
              onPressed: _refreshDetails,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry reviews'),
            ),
          );
        }

        final reviews = snapshot.data ?? [];
        if (reviews.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              "No reviews yet.",
              style: TextStyle(color: AppColors.textMuted(context)),
            ),
          );
        }

        return Column(
          children: reviews.map((r) {
            final ratingText = r['rating']?.toString() ?? '0';
            return Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceBg(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(child: Icon(Icons.person_outline)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r['review_text']?.toString().isNotEmpty == true
                              ? r['review_text'].toString()
                              : 'Good consultation experience.',
                          style:
                              TextStyle(color: AppColors.textPrimary(context)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          r['created_at']?.toString().split('T').first ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 2),
                      Text(ratingText),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
