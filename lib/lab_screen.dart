import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lab_offer.dart';
import 'order_success_screen.dart';
import 'lab_description_screen.dart';
import 'global_search_bar.dart';
import 'universal_search_delegate.dart';
import 'services/voice_service.dart';
import 'theme_colors.dart';

class LabTestScreen extends StatefulWidget {
  final String? searchQuery;

  const LabTestScreen({super.key, this.searchQuery});

  @override
  State<LabTestScreen> createState() => _LabTestScreenState();
}

class _LabTestScreenState extends State<LabTestScreen> {
  final Color primaryIndigo = const Color(0xFF6366F1);
  final supabase = Supabase.instance.client;

  final VoiceService _voiceService = VoiceService();

  late final TextEditingController _searchController;
  String _currentSearchQuery = "";
  List<Map<String, dynamic>> _allLabs = [];
  final List<String> _labSearchHistory = ["Pathology", "Blood Test", "X-Ray"];

  // Track speaking state to update UI icons
  String? _currentlySpeakingId;
  Future<List<Map<String, dynamic>>>? _bookingsFuture;
  Future<List<Map<String, dynamic>>>? _labsFuture;

  @override
  void initState() {
    super.initState();
    _currentSearchQuery = widget.searchQuery ?? "";
    _searchController = TextEditingController(text: _currentSearchQuery);
    _bookingsFuture = _fetchMyBookings();
    _labsFuture = _fetchLabs();
    _initVoice();
  }

  Future<void> _initVoice() async {
    try {
      await _voiceService.initTts();
    } catch (e) {
      debugPrint('TTS initialization failed: $e');
    }
  }

  @override
  void dispose() {
    _voiceService.stop(); // Always stop voice when leaving screen
    _searchController.dispose();
    super.dispose();
  }

  // --- VOICE LOGIC ---

  void _speakBooking(Map<String, dynamic> booking) async {
    final String id = booking['id'].toString();

    if (_currentlySpeakingId == id) {
      await _voiceService.stop();
      setState(() => _currentlySpeakingId = null);
      return;
    }

    final lang = _voiceService.currentLanguage;
    String text = "";
    if (lang == VoiceService.nepali) {
      text =
          "तपाईको ${booking['test_names']} एपोइन्टमेन्ट ${booking['appointment_date']} मा छ।";
    } else if (lang == VoiceService.hindi) {
      text =
          "आपका ${booking['test_names']} अपॉइंटमेंट ${booking['appointment_date']} को है।";
    } else {
      text =
          "Your booking for ${booking['test_names']} is scheduled for ${booking['appointment_date']}.";
    }

    setState(() => _currentlySpeakingId = id);
    await _voiceService.speakWithSavedLanguage(text);
    if (mounted) setState(() => _currentlySpeakingId = null);
  }

  void _speakLabInfo(Map<String, dynamic> lab) async {
    final String id = lab['id'].toString();

    if (_currentlySpeakingId == id) {
      await _voiceService.stop();
      setState(() => _currentlySpeakingId = null);
      return;
    }

    final name = lab['full_name'] ?? "Medical Center";

    // ✅ UPDATED: prefer `location` from profile, fallback to `address`
    final address = lab['location'] ?? lab['address'] ?? "Available Location";

    final testsCount = (lab['lab_tests'] as List?)?.length ?? 0;

    final lang = _voiceService.currentLanguage;
    String text = "";
    if (lang == VoiceService.nepali) {
      text =
          "$name, $address मा अवस्थित छ। यहाँ $testsCount वटा जाँचहरू उपलब्ध छन्।";
    } else if (lang == VoiceService.hindi) {
      text = "$name, $address में स्थित है। यहाँ $testsCount टेस्ट उपलब्ध हैं।";
    } else {
      text =
          "$name is located at $address. They offer $testsCount different tests.";
    }

    setState(() => _currentlySpeakingId = id);
    await _voiceService.speakWithSavedLanguage(text);
    if (mounted) setState(() => _currentlySpeakingId = null);
  }


  Future<void> _openBookingDetails(Map<String, dynamic> booking) async {
    _voiceService.stop();

    final hospitalId = (booking['hospital_id'] ?? '').toString().trim();
    Map<String, dynamic> resolvedLabData = {};
    String resolvedStoreName = 'Lab Center';

    if (hospitalId.isNotEmpty && hospitalId != 'null') {
      try {
        final profile = await supabase
            .from('profiles')
            .select('id, full_name, role, location, address, avatar_url, facility_image_url')
            .eq('id', hospitalId)
            .maybeSingle();

        if (profile != null) {
          resolvedLabData = {
            ...Map<String, dynamic>.from(profile),
            'hospital_id': hospitalId,
          };
          resolvedStoreName = (profile['full_name'] ?? 'Lab Center').toString();
        }
      } catch (e) {
        debugPrint('Booking detail lab resolve error: $e');
      }
    }

    if (resolvedLabData.isEmpty) {
      resolvedLabData = {
        'id': hospitalId,
        'hospital_id': hospitalId,
        'full_name': booking['lab_name'] ?? 'Lab Center',
      };
      resolvedStoreName = (booking['lab_name'] ?? 'Lab Center').toString();
    }

    String formattedDate = (booking['appointment_date'] ?? '').toString().trim();
    try {
      if (formattedDate.isNotEmpty) {
        formattedDate = DateFormat('dd MMM yyyy').format(DateTime.parse(formattedDate));
      }
    } catch (e, st) {
      debugPrint('Failed to parse formattedDate: $formattedDate | $e | $st');
    }

    final paymentStatus = (booking['payment_status'] ?? '').toString().trim().toLowerCase();
    final paymentMethod = (booking['payment_method'] ?? '').toString().trim().toLowerCase();

    String paymentLabel;
    if (paymentStatus == 'paid') {
      paymentLabel = 'Paid';
    } else if (paymentMethod == 'cash' || paymentStatus == 'pending') {
      paymentLabel = 'Pay at Lab';
    } else {
      paymentLabel = 'Pending';
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderSuccessScreen(
          itemLabel: (booking['test_names'] ?? 'Lab Test').toString(),
          amount: (booking['total_amount'] ?? '0').toString(),
          storeName: resolvedStoreName,
          type: 'Lab',
          labData: resolvedLabData,
          extraDetails: {
            'date': formattedDate.isEmpty ? 'N/A' : formattedDate,
            'time': (booking['appointment_time'] ?? 'N/A').toString(),
            'appointment_id': booking['id']?.toString(),
            'status': paymentLabel,
            'appointment_status': (booking['status'] ?? 'scheduled').toString(),
          },
        ),
      ),
    );
  }

  // --- UI SECTIONS ---

  Widget _buildSearchTrigger() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GestureDetector(
        onTap: () async {
          _voiceService.stop();
          final result = await showSearch(
            context: context,
            delegate: UniversalSearchDelegate(
              data: _allLabs,
              scope: "lab_test",
              history: _labSearchHistory,
            ),
          );
          if (result != null) {
            setState(() {
              _currentSearchQuery = result.toString().toLowerCase();
              _searchController.text = result.toString();
            });
          }
        },
        child: AbsorbPointer(
          child: GlobalSearchBar(
            controller: _searchController,
            hintText: "Search Labs, Clinics...",
            onSearch: (value) {},
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchMyBookings() async {
    final user = supabase.auth.currentUser;
    if (user == null) return const [];

    final data = await supabase
        .from('lab_appointments')
        .select()
        .eq('user_id', user.id)
        .order('appointment_date', ascending: true);
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((row) {
          final status = (row['status'] ?? '').toString().toLowerCase().trim();
          final isExpired = row['is_expired'] == true;
          return !isExpired &&
              status != 'cancelled' &&
              status != 'completed';
        })
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchLabs() async {
    final data = await supabase
        .from('profiles')
        .select('*, lab_tests!fk_lab_provider(id, name)')
        .or('role.ilike.hospital,role.ilike.clinic');
    final allData = (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final hasTests = allData
        .where((p) => (p['lab_tests'] as List?)?.isNotEmpty == true)
        .toList();
    _allLabs = hasTests;
    return hasTests;
  }

  Widget _buildMyBookingsSection() {
    final user = supabase.auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _bookingsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Bookings fetch error: ${snapshot.error}');
          return const SizedBox.shrink();
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final bookings = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader("My Active Bookings"),
            SizedBox(
              height: 110,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: bookings.length,
                itemBuilder: (context, index) =>
                    _buildBookingMiniCard(bookings[index]),
              ),
            ),
            const SizedBox(height: 10),
            const Divider(indent: 20, endIndent: 20, thickness: 0.5),
          ],
        );
      },
    );
  }

  Widget _buildBookingMiniCard(Map<String, dynamic> booking) {
    bool isSpeaking = _currentlySpeakingId == booking['id'].toString();

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12, bottom: 8, top: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _speakBooking(booking),
            child: CircleAvatar(
              backgroundColor: isSpeaking
                  ? Colors.redAccent.withValues(alpha: 0.1)
                  : primaryIndigo.withValues(alpha: 0.1),
              child: Icon(isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                  color: isSpeaking ? Colors.redAccent : primaryIndigo, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => _openBookingDetails(booking),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    booking['test_names'] ?? "Lab Booking",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    _buildBookingScheduleLabel(booking),
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted(context)),
                  ),
                ],
              ),
            ),
          ),
          Icon(Icons.arrow_forward_ios, size: 12, color: AppColors.textMuted(context)),
        ],
      ),
    );
  }


  String _buildBookingScheduleLabel(Map<String, dynamic> booking) {
    final date = (booking['appointment_date'] ?? '').toString().trim();
    final time = (booking['appointment_time'] ?? '').toString().trim();
    if (date.isNotEmpty && time.isNotEmpty) return '$date | $time';
    if (date.isNotEmpty) return date;
    if (time.isNotEmpty) return time;
    return 'Schedule unavailable';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text("Labs & Diagnostics",
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary(context)),
      ),
      body: Column(
        children: [
          _buildSearchTrigger(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _bookingsFuture = _fetchMyBookings();
                  _labsFuture = _fetchLabs();
                });
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LabOffer(),
                    _buildMyBookingsSection(),
                    _buildSectionHeader("Verified Lab Partners"),
                    _buildLiveLabList(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLiveLabList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _labsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }

        final List<Map<String, dynamic>> allData = snapshot.data ?? [];
        final String cleanQuery = _currentSearchQuery.trim().toLowerCase();
        final filteredLabs = allData.where((lab) {
          if (cleanQuery.isEmpty) return true;
          return (lab['full_name'] ?? "")
              .toString()
              .toLowerCase()
              .contains(cleanQuery);
        }).toList();

        if (filteredLabs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text("No labs found."),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredLabs.length,
          itemBuilder: (context, index) =>
              _buildProviderFaceCard(filteredLabs[index]),
        );
      },
    );
  }

  Widget _buildProviderFaceCard(Map<String, dynamic> provider) {
    final String? profileImg =
        provider['avatar_url'] ?? provider['facility_image_url'];
    final List tests = provider['lab_tests'] ?? [];
    final String labId = provider['id'].toString();
    bool isSpeaking = _currentlySpeakingId == labId;

    // ✅ UPDATED: prefer `location` from profile, fallback to `address`
    final displayLocation =
        provider['location'] ?? provider['address'] ?? "Available Location";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 15,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: primaryIndigo.withValues(alpha: 0.05),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  image: (profileImg != null && profileImg.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(profileImg), fit: BoxFit.cover)
                      : null,
                ),
                child: (profileImg == null || profileImg.isEmpty)
                    ? Icon(Icons.business_rounded,
                        size: 40, color: primaryIndigo.withValues(alpha: 0.3))
                    : null,
              ),
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () => _speakLabInfo(provider),
                  child: CircleAvatar(
                    backgroundColor: AppColors.cardBg(context).withValues(alpha: 0.8),
                    child: Icon(
                      isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                      color: isSpeaking ? Colors.redAccent : primaryIndigo,
                    ),
                  ),
                ),
              ),
            ],
          ),
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(provider['full_name'] ?? "Medical Center",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: primaryIndigo),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        displayLocation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text("${tests.length} tests available",
                    style: TextStyle(
                        color: primaryIndigo,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
              ],
            ),
            trailing: ElevatedButton(
              onPressed: () {
                _voiceService.stop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => LabDescriptionScreen(labData: provider)),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryIndigo,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text("View Profile",
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}