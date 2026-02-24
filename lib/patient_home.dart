import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_handler.dart'; 
import 'call_landing_page.dart'; 
import 'quick_categories.dart';
import 'special_offers.dart';
import 'insurance_subscription.dart'; 
import 'all_plans_screen.dart';
import 'services/voice_service.dart'; 
import 'patient_settings.dart'; // Import for navigation

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  Map<String, dynamic>? _activeBooking;
  String? _avatarUrl; // State to hold the profile picture URL
  final VoiceService _voiceService = VoiceService();

  @override
  void initState() {
    super.initState();
    _checkForActiveCall();
    _initVoice();
    _loadUserProfile(); // Load avatar on start
  }

  /// Fetches the current user's profile picture
  Future<void> _loadUserProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final data = await Supabase.instance.client
          .from('profiles')
          .select('avatar_url')
          .eq('id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _avatarUrl = data['avatar_url'];
        });
      }
    } catch (e) {
      debugPrint("Error loading avatar: $e");
    }
  }

  Future<void> _initVoice() async {
    await _voiceService.initTts();
  }

  void _showLanguageSelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Select Voice Language",
          style: TextStyle(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageOption("English", VoiceService.english, "Language set to English."),
            const Divider(),
            _buildLanguageOption("नेपाली", VoiceService.nepali, "भाषा नेपालीमा मिलाइएको छ।"),
            const Divider(),
            _buildLanguageOption("हिंदी", VoiceService.hindi, "भाषा हिंदी में सेट की गई है।"),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption(String label, String code, String confirmationText) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      onTap: () {
        _voiceService.setLanguage(code);
        Navigator.pop(context);
        _voiceService.speakWithSavedLanguage(confirmationText).then((_) {
          _playCurrentScreenInstructions();
        });
      },
    );
  }

  void _playCurrentScreenInstructions() async {
    String text = "";
    if (_voiceService.currentLanguage == VoiceService.nepali) {
      text = "हेल्थ डिपार्टमेन्टमा स्वागत छ। यहाँ तपाईं औषधि खोज्न, विधा रोज्न, वा बिमा योजनाहरू हेर्न सक्नुहुन्छ।";
    } else if (_voiceService.currentLanguage == VoiceService.hindi) {
      text = "हेल्थ डिपार्टमेंट में आपका स्वागत है। यहाँ आप दवाइयाँ खोज सकते हैं, श्रेणियां चुन सकते हैं या बीमा प्लान देख सकते हैं।";
    } else {
      text = "Welcome to Health Department. Here you can search for medicines, choose categories, or check your insurance plans.";
    }
    await _voiceService.speakWithSavedLanguage(text);
  }

  Future<void> _checkForActiveCall() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final booking = await SupabaseHandler().getActiveBooking(user.id);
    if (mounted) {
      setState(() {
        _activeBooking = booking;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color brandBlue = Color(0xFF6366F1);
    final user = Supabase.instance.client.auth.currentUser;

    return RefreshIndicator(
      onRefresh: () async {
        await _checkForActiveCall();
        await _loadUserProfile();
      }, 
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 60),
            _buildHeader(brandBlue, user),

            if (_activeBooking != null) ...[
              const SizedBox(height: 20),
              _buildActiveCallBanner(brandBlue),
            ],

            const SizedBox(height: 25),
            _buildSearchBar(brandBlue),

            const SizedBox(height: 25),
            const _SectionHeader(title: "Quick Categories"),
            const SizedBox(height: 16),
            QuickCategories(brandBlue: brandBlue), 

            const SizedBox(height: 30),
            const _SectionHeader(title: "Special Offers"),
            const SizedBox(height: 16),
            const SpecialOffers(),

            const SizedBox(height: 30),
            _SectionHeader(
              title: "Insurance & Subscription",
              onSeeAllTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AllPlansScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
            const InsuranceSubscription(), 
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCallBanner(Color brandBlue) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brandBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(Icons.videocam_rounded, color: brandBlue),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Active Consultation", 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text("Your provider is waiting for you", 
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: _resumeCall,
            child: const Text("Join"),
          ),
        ],
      ),
    );
  }

  void _resumeCall() {
    if (_activeBooking == null) return;
    final roomId = SupabaseHandler.getNormalizedRoomId(_activeBooking!['id'].toString());

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PatientVideoCallPage(
          callID: roomId,
          userID: Supabase.instance.client.auth.currentUser!.id,
          userName: Supabase.instance.client.auth.currentUser?.userMetadata?['full_name'] ?? "Patient",
          professionalName: "Medical Specialist", 
        ),
      ),
    );
  }

  Widget _buildHeader(Color brandBlue, User? user) {
    return Row(
      children: [
        // Profile Icon with Avatar and Navigation
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PatientSettings()),
            );
          },
          child: CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFE0E7FF),
            backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
            child: _avatarUrl == null
                ? Text(
                    user?.email?.substring(0, 1).toUpperCase() ?? "H",
                    style: TextStyle(color: brandBlue, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          "Health Department",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
        ),
        const Spacer(),
        IconButton(
          onPressed: _showLanguageSelector,
          icon: const Icon(Icons.record_voice_over, color: Color(0xFF6366F1), size: 28),
          tooltip: "Choose Language & Listen",
        ),
        _buildAppBarIcon(Icons.notifications_none_outlined, badgeCount: "3"),
      ],
    );
  }

  Widget _buildSearchBar(Color brandBlue) {
    return TextField(
      decoration: InputDecoration(
        hintText: "Search medicines, labs...",
        prefixIcon: const Icon(Icons.search, color: Colors.grey),
        suffixIcon: Icon(Icons.tune, color: brandBlue),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildAppBarIcon(IconData icon, {String? badgeCount}) {
    return Stack(
      children: [
        Icon(icon, size: 28, color: Colors.black87),
        if (badgeCount != null)
          Positioned(
            right: 0, top: 0,
            child: CircleAvatar(
              radius: 8,
              backgroundColor: Colors.red,
              child: Text(badgeCount, style: const TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAllTap;

  const _SectionHeader({
    required this.title,
    this.onSeeAllTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        GestureDetector(
          onTap: onSeeAllTap,
          child: Text(
            "See All",
            style: TextStyle(
              color: onSeeAllTap != null ? const Color(0xFF6366F1) : Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}