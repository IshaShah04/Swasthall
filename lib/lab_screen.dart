import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lab_offer.dart';
import 'order_success_screen.dart';
import 'lab_description_screen.dart';
import 'global_search_bar.dart';
import 'universal_search_delegate.dart';
import 'services/voice_service.dart'; // 1. Import VoiceService

class LabTestScreen extends StatefulWidget {
  final String? searchQuery;

  const LabTestScreen({super.key, this.searchQuery});

  @override
  State<LabTestScreen> createState() => _LabTestScreenState();
}

class _LabTestScreenState extends State<LabTestScreen> {
  final Color primaryIndigo = const Color(0xFF6366F1);
  final Color bgLight = const Color(0xFFF8FAFC);
  final supabase = Supabase.instance.client;

  // 2. Initialize VoiceService
  final VoiceService _voiceService = VoiceService();

  late final TextEditingController _searchController;
  String _currentSearchQuery = "";
  List<Map<String, dynamic>> _allLabs = [];
  final List<String> _labSearchHistory = ["Pathology", "Blood Test", "X-Ray"];

  @override
  void initState() {
    super.initState();
    _currentSearchQuery = widget.searchQuery ?? "";
    _searchController = TextEditingController(text: _currentSearchQuery);
    _voiceService.initTts(); // 3. Initialize TTS
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- VOICE LOGIC ---
  void _speakBooking(Map<String, dynamic> booking) {
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
    _voiceService.speakWithSavedLanguage(text);
  }

  void _speakLabInfo(Map<String, dynamic> lab) {
    final name = lab['full_name'] ?? "Medical Center";
    final address = lab['address'] ?? "Available Location";
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
    _voiceService.speakWithSavedLanguage(text);
  }

  // --- UI SECTIONS ---

  Widget _buildSearchTrigger() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GestureDetector(
        onTap: () async {
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

  Widget _buildMyBookingsSection() {
    final user = supabase.auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('lab_appointments')
          .stream(primaryKey: ['id'])
          .eq('user_id', user.id)
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final bookings = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader("My Active Bookings"),
            SizedBox(
              height: 110, // Increased height slightly for better spacing
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
    return Container(
      width: 280, // Slightly wider for voice button
      margin: const EdgeInsets.only(right: 12, bottom: 8, top: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _speakBooking(booking), // Voice trigger
            child: CircleAvatar(
              backgroundColor: primaryIndigo.withValues(alpha: 0.1),
              child:
                  Icon(Icons.volume_up_rounded, color: primaryIndigo, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OrderSuccessScreen(
                    itemLabel: booking['test_names'] ?? "Lab Test",
                    amount: booking['total_amount']?.toString() ?? "0",
                    storeName: "Lab Appointment",
                    type: "Lab",
                    labData: booking,
                    extraDetails: {
                      'date': booking['appointment_date'],
                      'time': booking['appointment_time'],
                      'appointment_id': booking['id'],
                      'status': booking['status'],
                    },
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(booking['test_names'] ?? "Lab Booking",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(
                      "${booking['appointment_date']} | ${booking['appointment_time']}",
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        title: const Text("Labs & Diagnostics",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          _buildSearchTrigger(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => setState(() {}),
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
      future: supabase
          .from('profiles')
          .select('*, lab_tests!fk_lab_provider(id, name)')
          .or('role.ilike.hospital,role.ilike.clinic'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }

        final List<Map<String, dynamic>> allData = snapshot.data ?? [];
        final List<Map<String, dynamic>> hasTests =
            allData.where((p) => (p['lab_tests'] as List).isNotEmpty).toList();
        final String cleanQuery = _currentSearchQuery.trim().toLowerCase();
        final filteredLabs = hasTests.where((lab) {
          if (cleanQuery.isEmpty) return true;
          return (lab['full_name'] ?? "")
              .toString()
              .toLowerCase()
              .contains(cleanQuery);
        }).toList();

        _allLabs = filteredLabs;

        if (filteredLabs.isEmpty) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(40), child: Text("No labs found.")));
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 15,
              offset: const Offset(0, 8))
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
              // VOICE ICON ON CARD
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () => _speakLabInfo(provider),
                  child: CircleAvatar(
                    backgroundColor: Colors.white.withValues(alpha: 0.8),
                    child: Icon(Icons.volume_up_rounded, color: primaryIndigo),
                  ),
                ),
              ),
            ],
          ),
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(provider['full_name'] ?? "Medical Center",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: primaryIndigo),
                    const SizedBox(width: 4),
                    Expanded(
                        child: Text(provider['address'] ?? "Available Location",
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
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
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          LabDescriptionScreen(labData: provider))),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryIndigo,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("View Profile",
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
